#!/usr/bin/env perl
# extract-components.pl - rebuild the extracted component directories from the
# committed source artifacts and regenerate each component's manifest.json.
#
# Reconstructed in the Oct 2026 audit: every README/docs/manifest references
# this tool, but it had never been committed. Behavior follows the documented
# contract; manifests are byte-format-identical to the existing ones.
#
# Usage:
#   perl component/extract-components.pl [--force] [--deb=<name>] [component]
#     default (no --force): verify mode - byte-compare the manifest against the
#         files on disk (and against the origin deb when it is present)
#     --force  : wipe + re-extract the component from its source deb
#     --deb=<n>: override the source deb (name inside source-artifacts/, or a
#                direct path). Default: the manifest's origin deb, so plain
#                rebuilds are idempotent.
#     component: 'eeveespotify' (default) or 'spotipw'
#
# Extraction rules (from the deb layouts, audit evidence):
#   eeveespotify, selfcontained layout (v6.6.8 deb):
#     Spotify.app/*.png                       -> resources/
#     Spotify.app/EeveeSpotify.bundle/**      -> bundles/EeveeSpotify.bundle/
#     Spotify.app/Frameworks/**               -> frameworks/
#     var/jb/.../DynamicLibraries/*           -> package/dynamic-libraries/
#   eeveespotify, jb layout (>= 0.47, e.g. the v7.0.0 deb):
#     var/jb/.../DynamicLibraries/*           -> package/dynamic-libraries/
#        (dylib + filter plist + *.metallib ride along)
#     var/jb/.../Application Support/EeveeSpotify.bundle/**
#                                             -> bundles/EeveeSpotify.bundle/
#     var/jb/Library/Frameworks/**            -> frameworks/
#   Orion.framework is NOT part of the jb layout; it is preserved from the
#   existing pin (upstream does not provide it and the unified build needs it).
#   spotipw:
#     Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib
#                                             -> dylibs/
#     Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist
#                                             -> package/dynamic-libraries/
#   Both component kinds: deb control tar ./control -> <component>/package/control
#
# Manifests are written with JSON::PP canonical->pretty (the committed format).
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catfile catdir);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Find;

# ---------- roots -------------------------------------------------------------
	my $tool_dir  = dirname(abs_path($0));           # Evevee Spotify/component
my $comp_root = dirname($tool_dir);             # Evevee Spotify
my $repo      = dirname($comp_root);            # repo root

my %COMPONENT = (
    eeveespotify => {
        name     => 'eeveespotify',
        comp_dir => catdir($comp_root, 'component'),   # Evevee Spotify/component
        manifest => catfile($comp_root, 'component', 'manifest.json'),
        roots    => [ 'package', 'bundles', 'frameworks', 'resources' ],
    },
    spotipw => {
        name     => 'spotipw',
        comp_dir => catdir($repo, 'PwEvevee', 'components', 'spotipw'),
        manifest => catfile($repo, 'PwEvevee', 'components', 'spotipw', 'manifest.json'),
        roots    => [ 'dylibs', 'package' ],
    },
);

# ---------- arguments ----------------------------------------------------------
my ($FORCE, $OVER);
my $component_name = 'eeveespotify';
for (my $i = 0; $i < @ARGV; $i++) {
    if    ($ARGV[$i] eq '--force')                  { $FORCE = 1 }
    elsif ($ARGV[$i] =~ /^--deb=(.+)$/)             { $OVER = $1 }
    elsif ($ARGV[$i] eq '--deb')                    { $OVER = $ARGV[++$i] or die "--deb requires a name\n" }
    elsif ($ARGV[$i] =~ /^--?h(elp)?$/)             { print "usage: extract-components.pl [--force] [--deb=<name>] [eeveespotify|spotipw]\n"; exit 0 }
    elsif ($ARGV[$i] =~ /^(eeveespotify|spotipw)$/) { $component_name = $1 }
    else  { die "unknown argument '$ARGV[$i]'\n" }
}
my $C = $COMPONENT{$component_name} or die "unknown component '$component_name'\n";
print "extract-components.pl: component=$component_name, force=", ($FORCE ? 1 : 0), "\n";

# ---------- provenance: resolve the source deb ----------------------------------
sub deb_for_run {
    my ($comp) = @_;
    if (defined $OVER) {
        return $OVER if -f $OVER;                                        # a direct path
        my $in_src = catfile($comp_root, 'source-artifacts', $OVER);
        return $in_src if -f $in_src;
        die "deb '$OVER': not found neither as path nor under source-artifacts/\n";
    }
    # otherwise: the manifest's own origin, resolved from the repo root
    my $manifest = $comp->{manifest};
    -f $manifest or die "no manifest and no --deb: nothing to rebuild/verify\n";
    open my $f, '<', $manifest or die "read $manifest: $!\n";
    local $/; my $txt = <$f>;
    close $f;
    my $m = eval { JSON::PP::decode_json($txt) } or die "manifest invalid JSON: $@\n";
    return undef unless $m->{origin};
    my $joined = catfile($repo, split m{/}, $m->{origin});
    die "origin deb '$m->{origin}' not found on disk\n" unless -f $joined;
    return $joined;
}
my $deb = deb_for_run($C) or die "no source deb resolvable\n";

# ---------- small utilities ------------------------------------------------------
sub slurp_bin { open my $f, '<:raw', $_[0] or die "slurp $_[0]: $!\n"; binmode $f; local $/; my $d = <$f>; close $f; return $d }
sub _shq { my $p = shift; $p =~ s/'/'"'"'/g; return "'$p'" }

# ---------- ar / tar -------------------------------------------------------------
sub read_deb_members {
    my ($deb) = @_;
    open my $f, '<:raw', $deb or die "open $deb: $!\n";
    binmode $f;
    my $magic; read($f, $magic, 8) or die "short magic read on $deb: $!\n";
    $magic eq "!<arch>\n" or die "$deb: not an ar archive\n";
    my %m;
    while (1) {
        read($f, my $h, 60) or last;
        length($h) == 60 or die "$deb: short ar header\n";
        my $n = substr($h, 0, 16); $n =~ s/[\0\s]+$//;
        my $s = substr($h, 48, 10); $s =~ s/[\0\s]//g;
        next unless $s =~ /^\d+$/;                    # GNU index members etc.
        my $d = '';
        while (length($d) < $s) {
            read($f, my $c, $s - length($d));
            defined($c) && length($c) or die "short read inside $n\n";
            $d .= $c;
        }
        read($f, my $pad, 1) if $s % 2;               # consume odd-member pad byte
        $m{$n} = $d;
    }
    close $f;
    return \%m;
}

sub spill {
    my ($scr, $name, $bytes) = @_;
    my $p = catfile($scr, $name);
    open my $o, '>:raw', $p or die "spill $p: $!\n";
    binmode $o; print $o $bytes; close $o;
    return $p;
}

sub data_tar_path {
    my ($mb, $scr) = @_;
    my ($name) = grep { /^data\.tar\./ } sort keys %$mb or die "no data.tar.* in deb\n";
    return decode_member_tar($mb, $name, $scr);
}
sub control_tar_path {
    my ($mb, $scr) = @_;
    my ($name) = grep { /^control\.tar\./ } sort keys %$mb or die "no control.tar.* in deb\n";
    return decode_member_tar($mb, $name, $scr);
}
sub decode_member_tar {
    my ($mb, $name, $scr) = @_;
    my $spilled = spill($scr, $name, $mb->{$name});
    (my $base = $name) =~ s/\.[^.]+$//;               # data.tar.xz -> data.tar
    my $plain = catfile($scr, $base);
    if ($name =~ /\.(xz|lzma)$/) {
        system("lzmadec -d -c " . _shq($spilled) . " > " . _shq($plain) . " 2>/dev/null") == 0
            or die "lzmadec failed on $name\n";
    }
    elsif ($name =~ /\.gz$/) {
        system("gzip -dc " . _shq($spilled) . " > " . _shq($plain)) == 0
            or die "gzip failed on $name\n";
    }
    else { die "unsupported tar compression: $name\n" }
    return $plain;
}

sub tar_tree {                                        # extract a tar as a tree
    my ($scr, $tar, $sub) = @_;
    my $tree = catdir($scr, $sub || 'tree');
    remove_tree($tree);
    make_path($tree);
    system("tar -xf " . _shq($tar) . " -C " . _shq($tree)) == 0
        or die "tar -xf $tar: $!\n";
    return $tree;
}

sub tar_file_list {
    my ($tar) = @_;
    open my $t, '-|', "tar -tf " . _shq($tar) or die "tar -tf: $!\n";
    chomp(my @l = <$t>); close $t;
    my @files = grep { !m{/\z} } @l;                  # entries only (no dirs,. )
    for (@files) { s{^\./}{} }
    return @files;
}

sub read_control_fields {
    my ($ctrl_tar, $scr) = @_;
    my $tree = tar_tree($scr, $ctrl_tar, 'control-tree');
    open my $c, '<', catfile($tree, 'control') or die "control file missing in deb\n";
    my %kv; while (my $l = <$c>) { chomp $l; if ($l =~ /^([^:]+):\s*(.*)\z/) { $kv{$1} = $2 } }
    close $c;
    return \%kv;
}

# ---------- mapping rules ---------------------------------------------------------
sub eevee_dest_for {
    my ($p) = @_;
    return "bundles/EeveeSpotify.bundle/$1"
        if $p =~ m{^Spotify\.app/EeveeSpotify\.bundle/(.+)\z};
    return "frameworks/$1"
        if $p =~ m{^Spotify\.app/Frameworks/(.+)\z};
    return "resources/$1"
        if $p =~ m{^Spotify\.app/([^/]+\.png)\z};
    return "package/dynamic-libraries/$1"
        if $p =~ m{^var/jb/Library/MobileSubstrate/DynamicLibraries/([^/]+)\z};
    return "bundles/EeveeSpotify.bundle/$1"
        if $p =~ m{^var/jb/Library/Application Support/EeveeSpotify\.bundle/(.+)\z};
    return "frameworks/$1"
        if $p =~ m{^var/jb/Library/Frameworks/(.+)\z};
    return undef;                                     # deb helper scripts etc.
}

sub spotipw_dest_for {
    my ($p) = @_;
    if ($p =~ m{^Library/MobileSubstrate/DynamicLibraries/(.+)\z}) {
        my $f = $1;
        return "dylibs/$f"                    if $f =~ /\.dylib\z/;
        return "package/dynamic-libraries/$f" if $f =~ /\.plist\z/;
        return undef;
    }
    return undef;
}

# ---------- extraction (--force) --------------------------------------------------
sub bytes_equiv {
    my ($a, $b) = @_;
    return 1 if $a eq $b;
    (my $na = $a) =~ s/\r\n/\n/g;      # CRLF-checkout tolerance for text files
    (my $nb = $b) =~ s/\r\n/\n/g;
    return $na eq $nb;
}
sub run_extract {
    my ($scr) = @_;
    my $mb = read_deb_members($deb);
    my $data_tar = data_tar_path($mb, $scr);
    my $ctrl_tar = control_tar_path($mb, $scr);
    my $ctrl = read_control_fields($ctrl_tar, $scr);
    my $tree = tar_tree($scr, $data_tar);
    my @paths = tar_file_list($data_tar);
    my $mapper = $component_name eq 'eeveespotify' ? \&eevee_dest_for : \&spotipw_dest_for;

    my (%files_for);                                  # dest -> [tar relpaths]
    for my $p (@paths) {
        my $d = $mapper->($p);
        next unless defined $d;
        push @{ $files_for{$d} }, $p;
    }
    die "$deb: no extractable payload under the documented mapping rules\n" unless %files_for;

    # Idempotency guard: plain --force must reproduce the origin deb exactly. If the
    # deb's payload would CHANGE committed component content, the committed
    # payload is newer than the origin deb (provenance note in the manifest
    # describes exactly that for spotipw/the CI-refresh case) - refuse and
    # require an explicit --deb for a deliberate refresh.
    if (not defined $OVER) {
        my @clash;
        for my $d (sort keys %files_for) {
            my @segments = split m{/}, $d;
            my $abs = catfile($C->{comp_dir}, @segments);
            next unless -f $abs;
            my $existing = slurp_bin($abs);
            my $incoming = slurp_bin(catfile($tree, split m{/}, $files_for{$d}[0]));
            push @clash, $d unless bytes_equiv($existing, $incoming);
        }
        if (@clash) {
            die "refusing plain --force: the origin deb's payload differs from the
committed component for '$clash[0]'. The committed file was refreshed from a
newer source than the origin deb (see the provenance note in the manifest).
To refresh deliberately, run: extract-components.pl --force --deb=<newer deb>\n";
        }
    }

    # what to wipe: everything the deb supplies, never what it doesn't
    my (%wipe_dirs, %wipe_frameworks);
    for my $d (keys %files_for) {
        if    ($d =~ m{^(package|dylibs)/})           { $wipe_dirs{$1} = 1 }
        elsif ($d =~ m{^(bundles/EeveeSpotify\.bundle)/}) { $wipe_dirs{$1} = 1 }
        elsif ($d =~ m{^(resources)/})                { $wipe_dirs{$1} = 1 }   # only the selfcontained layout ships icons
        elsif ($d =~ m{^frameworks/([^/]+)/})         { $wipe_frameworks{$1} = 1 }
    }
    for my $d (sort keys %wipe_dirs) {
        my $abs = catdir($C->{comp_dir}, split m{/}, $d);
        if (-d $abs) { remove_tree($abs); print "  wiped $d/\n" }
    }
    for my $fw (sort keys %wipe_frameworks) {
        my $abs = catdir($C->{comp_dir}, 'frameworks', $fw);
        if (-d $abs) { remove_tree($abs); print "  wiped frameworks/$fw/\n" }
    }

    my $copied = 0; my $skipped_dirs = 0;
    for my $d (sort keys %files_for) {
        for my $p (@{ $files_for{$d} }) {
            my $src = catfile($tree, split m{/}, $p);
            # some tar packs dir entries without a trailing '/'; skip them
            unless (-f $src) { $skipped_dirs++; next }
            my $dst = catdir($C->{comp_dir}, split m{/}, $d);
            make_path(dirname($dst));
            copy($src, $dst) or die "copy $p -> $dst: $!\n";
            $copied++;
        }
    }
    # control -> package/control (both component kinds record package/control)
    my $ctrl_tree = tar_tree($scr, $ctrl_tar, 'control-tree');   # fresh tree either way
    make_path(catdir($C->{comp_dir}, 'package'));
    copy(catfile($ctrl_tree, 'control'), catfile($C->{comp_dir}, 'package', 'control'))
        or die "install deb control: $!\n";

    printf "  extracted %d payload files (%d dir entries skipped) from %s (deb version=%s)\n",
           $copied, $skipped_dirs, basename($deb), ($ctrl->{Version} // '?');
    return $ctrl;
}

# ---------- manifest regeneration --------------------------------------------------
sub component_file_rows {
    my ($comp) = @_;
    my @rows;
    my $top = $comp->{comp_dir};
    find({
        no_chdir => 1,
        wanted => sub {
            my $n = $File::Find::name;
            return unless -f $n;
            my $rel = substr($n, length($top) + 1);
            $rel =~ s{\\}{/}g;                        # manifest paths use '/'
            return if $rel eq 'manifest.json';
            return if $rel =~ m{\.extract-scr};
            my $keep = 0;
            for my $root (@{ $comp->{roots} }) {
                ++$keep if $rel =~ m{^\Q$root\E(?:/|\z)};
            }
            return unless $keep;
            my $data = slurp_bin($n);
            push @rows, { path => $rel, sha256 => sha256_hex($data), size => length($data) };
        },
    }, $top);
    return [ sort { $a->{path} cmp $b->{path} } @rows ];
}

sub write_manifest {
    my ($comp, $ctrl, $extra) = @_;
    my $rows = component_file_rows($comp);

    my %out = (
        extracted_with => 'Evevee Spotify/component/extract-components.pl',
        file_count     => scalar @$rows,
        files          => [ map { +{ path => $_->{path}, sha256 => $_->{sha256}, size => $_->{size} } } @$rows ],
        name           => $comp->{name},
        origin         => join('/', basename($comp_root), 'source-artifacts', basename($deb)),
        origin_sha256  => sha256_hex(slurp_bin($deb)),
        package        => ($ctrl->{Package} // $comp->{name}),
        version        => ($ctrl->{Version} // 'unknown'),
    );
    # provenance keys the extractor does not own are carried over verbatim
    my %owned = map { $_ => 1 } qw(extracted_with file_count files name origin origin_sha256 package version);
    if ($extra) {
        for my $k (keys %$extra) {
            $out{$k} = $extra->{$k} unless $owned{$k};
        }
    }
    my $json = JSON::PP->new->canonical->pretty->encode(\%out);
    $json .= "\n" unless $json =~ /\n\z/;
    return ($json, $rows);                            # rows used by verify too
}

sub load_manifest {
    my ($comp) = @_;
    return undef unless -f $comp->{manifest};
    open my $f, '<', $comp->{manifest} or die "read $comp->{manifest}: $!\n";
    local $/; my $txt = <$f>;
    close $f;
    my $m = eval { JSON::PP::decode_json($txt) } or die "manifest invalid JSON: $@\n";
    return $m;
}

# ---------- verify -----------------------------------------------------------------
# text files may be CRLF-translated by the Windows checkout (core.autocrlf=true);
# the manifest describes committed repository content. Fall back to a comparison
# against the HEAD blob before declaring real drift.
sub git_blob_sha256 {
    my ($relpath) = @_;                          # repo-relative, '/'-separated
    local $SIG{__DIE__};
    my $cmd = q(git -C ) . _shq($repo) . q( cat-file -p ) . _shq("HEAD:$relpath") . q( 2>/dev/null);
    my $out = `$cmd`;
    return undef unless defined $out && length $out;
    return sha256_hex($out);
}
sub _shq_path { my $p = shift; $p =~ s/\"/\\"/g; return "\"$p\"" }

sub run_verify {
    my ($scratch_ok) = @_;
    my $m = load_manifest($C);
    unless ($m) { print "  no manifest: nothing to verify\n"; return 1 }
    unless ($m->{files} && @{ $m->{files} }) { print "  manifest has no files[]: nothing to verify\n"; return 1 }

    my $ok = 1;
    my $via_blob = 0;
    my $gitbase = substr($C->{comp_dir}, length($repo) + 1);
    $gitbase =~ s{\\}{/}g;
    $gitbase =~ s{/$}{};
    for my $fe (@{ $m->{files} }) {
        my @segments = split m{/}, $fe->{path};
        my $abs = catfile($C->{comp_dir}, @segments);
        unless (-f $abs) {
            print "  MISSING on disk: $fe->{path}\n"; $ok = 0; next;
        }
        my $data = slurp_bin($abs);
        my $size_ok = length($data) == ($fe->{size} // -1);
        my $hash_ok = sha256_hex($data) eq ($fe->{sha256} // '');
        if ($hash_ok && $size_ok) { next }
        my $relgit = $gitbase ? "$gitbase/$fe->{path}" : $fe->{path};
        my $bs = git_blob_sha256($relgit);
        if (defined $bs && $bs eq $fe->{sha256}) { $via_blob++; next }
        print "  HASH differs : $fe->{path}\n"; $ok = 0; next;
    }
    # files on disk that the manifest does not know about
    my $listed = join "\n", map { (split m{/}, $_->{path})[-1] } @{ $m->{files} };
    my %known = map { $_->{path} => 1 } @{ $m->{files} };
    for my $row (@{ component_file_rows($C) }) {
        next if $known{ $row->{path} };
        print "  EXTRA on disk: $row->{path}\n"; $ok = 0;
    }
    unless ($ok) { print "verify: FAILED\n"; return 0 }

    # cross-check the origin deb (if resolvable and present)
    if (defined $deb and -f $deb) {
        my $h = sha256_hex(slurp_bin($deb));
        if (defined $m->{origin_sha256} && $h ne $m->{origin_sha256}) {
            print "verify: origin deb hash differs from manifest ($deb)\n";
            return 0;
        }
    }
    else { print "verify: origin deb not present locally, skipped that check\n" }

    printf "verify: OK (%d files; %d checkout-raw, %d via git blob)\n",
           scalar @{ $m->{files} }, scalar @{ $m->{files} } - $via_blob, $via_blob;
    return 1;
}

# ---------- main dispatch ----------------------------------------------------------
my $scratch = catdir($C->{comp_dir}, '.extract-scr');
if ($FORCE) {
    -d $scratch and die "scratch $scratch already exists (a prior run did not clean up?)\n";
    make_path($scratch);
    my $extra = load_manifest($C);
    my $ctrl = run_extract($scratch);
    remove_tree($scratch);
    my ($json, $rows) = write_manifest($C, $ctrl, $extra);
    open my $m, '>', $C->{manifest} or die "write manifest: $!\n";
    print $m $json; close $m;
    print "wrote $C->{manifest} (" . scalar @$rows . " files)\n";
}
else {
    my $ok = run_verify();
    exit($ok ? 0 : 1);
}
