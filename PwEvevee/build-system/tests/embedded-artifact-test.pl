#!/usr/bin/env perl
# ============================================================================
# embedded-artifact-test.pl — the SHIPPED IPA's embedded dylib must be the pin
# ============================================================================
#
#   perl PwEvevee/build-system/tests/embedded-artifact-test.pl
#   PWEEVEE_IPA=dist/some.ipa perl .../embedded-artifact-test.pl
#   PWEEVEE_IPA_HOST=1 perl .../embedded-artifact-test.pl   (also inflate `Spotify`)
#
# Regression for the 3.1.0 launch-crash lineage, where every check in the tree
# looked at the *standalone* component file while the artifact that actually
# shipped carried a different object:
#
#   * the migrated baseline IPA embedded a dylib whose Substrate dependency was
#     the absolute /Library/Frameworks/... path (dyld "Library missing" crash),
#   * the crash-fix IPA embedded a byte-swapped build with NO signature at all,
#   * the pinned component carried a CodeDirectory with flags=0 and an
#     '.unsigned' identifier, which codesign reports as "no signature".
#
# component-manifest-test.pl proves the pinned file matches its manifest;
# dylib-guard-test.pl proves the pinned file is the migrated implementation.
# Neither looks inside an IPA, so a stale/broken embedded object could ship with
# a fully green suite. This test unzips the candidate IPA, extracts the embedded
# Frameworks/spotifyglass.dylib and asserts that it is the pinned component, that
# its Substrate edge is bundle-relative, that the implementation markers hold,
# and that it carries a signature codesign-class tools accept (ad-hoc flag set or
# a real CMS blob) rather than the '.unsigned' state.
#
# With no candidate IPA present the test reports the skip and exits 0, so it is
# safe to run in a tree that only holds source.
# ============================================================================
use strict;
use warnings;
use File::Basename qw(dirname);
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use IO::Uncompress::RawInflate qw(rawinflate);
use lib dirname($0) . '/../../build-system/lib';
use macho;

binmode STDOUT, ':encoding(UTF-8)';

my $ROOT  = dirname($0) . '/../../..';
my $SPEC  = "$ROOT/PwEvevee/components/spotipw/manifest.json";
my $PIN   = "$ROOT/PwEvevee/components/spotipw/dylibs/spotifyglass.dylib";

my $MEMBER_DYLIB = 'Payload/Spotify.app/Frameworks/spotifyglass.dylib';
my $MEMBER_HOST  = 'Payload/Spotify.app/Spotify';

my $LC_CODE_SIGNATURE = 0x1D;
my $CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0;
my $CSMAGIC_CODEDIRECTORY = 0xFADE0C02;
my $CSMAGIC_BLOBWRAPPER = 0xFADE0B01;   # CMS signature slot

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++ } else { push @failures, $what } }

sub slurp_raw { local $/; open my $fh, '<:raw', $_[0] or die "open $_[0]: $!"; return <$fh> }

# ---- candidate IPA selection -------------------------------------------------
sub pick_ipa {
  my @explicit = (
    "$ROOT/dist/rebuild-3.1.6.1/PwEevee-3.1.6.1-rebuild.ipa",
    "$ROOT/dist/PwEevee-3.1.6.1.ipa",
  );
  if (defined $ENV{PWEEVEE_IPA}) {
    return ("$ENV{PWEEVEE_IPA}", 1);   # explicit: absence is a failure, not a skip
  }
  for my $c (@explicit) { return ($c, 0) if -f $c }
  return (undef, 0);
}

# ---- minimal zip reader (store + deflate, core modules only) ----------------
sub zip_member {
  my ($zip, $want) = @_;
  my $data = slurp_raw($zip);
  my $eocd = rindex($data, pack('V', 0x06054B50));
  return undef if $eocd < 0;
  my ($count, $cd_size, $cd_off) = unpack('x10 v V V', substr($data, $eocd, 22));
  my $p = $cd_off;
  for my $i (1 .. $count) {
    return undef if $p + 46 > length($data);
    my $sig = unpack('V', substr($data, $p, 4));
    return undef if $sig != 0x02014B50;
    # central-directory entry: sig(4) made(2) need(2) flags(2) method(2)
    #  time(2) date(2) crc(4) csize(4) usize(4) namelen(2) extralen(2)
    #  commentlen(2) disk(2) intattr(2) extattr(4) local_off(4) name...
    my ($method, $csize, $usize, $namelen, $extralen, $commentlen, $local_off)
      = unpack('x10 v x8 V V v v v x8 V', substr($data, $p, 46));
    my $name = substr($data, $p + 46, $namelen);
    if ($name eq $want) {
      my $lh = $local_off;
      return undef if $lh + 30 > length($data);
      return undef if unpack('V', substr($data, $lh, 4)) != 0x04034B50;
      my ($l_namelen, $l_extralen) = unpack('v v', substr($data, $lh + 26, 4));
      my $start = $lh + 30 + $l_namelen + $l_extralen;
      my $raw = substr($data, $start, $csize);
      return $raw if $method == 0;
      return undef if $method != 8;
      my $out = '';
      rawinflate(\$raw => \$out) or return undef;
      return $out;
    }
    $p += 46 + $namelen + $extralen + $commentlen;
  }
  return undef;
}

# ---- code-signature inspection ----------------------------------------------
sub cs_report {
  my ($data) = @_;
  my %r = (present => 0, codedir => 0, flags => undef, ident => '', cms => 0);
  my @cmds = eval { macho::load_commands($data) };
  my ($off, $size);
  for my $c (@cmds) {
    next unless $c->{cmd} == $LC_CODE_SIGNATURE;
    $off  = unpack('V', substr($data, $c->{off} + 8, 4));
    $size = unpack('V', substr($data, $c->{off} + 12, 4));
  }
  return \%r unless defined $off && defined $size && $size > 12;
  $r{present} = 1;
  my $sb = substr($data, $off, $size);
  return \%r if unpack('N', substr($sb, 0, 4)) != $CSMAGIC_EMBEDDED_SIGNATURE;
  my $count = unpack('N', substr($sb, 8, 4));
  for my $i (0 .. $count - 1) {
    my ($type, $bo) = unpack('N N', substr($sb, 12 + $i * 8, 8));
    my $magic = unpack('N', substr($sb, $bo, 4));
    my $len   = unpack('N', substr($sb, $bo + 4, 4));
    if ($magic == $CSMAGIC_CODEDIRECTORY) {
      $r{codedir} = 1;
      $r{flags} = unpack('N', substr($sb, $bo + 12, 4));
      my $identoff = unpack('N', substr($sb, $bo + 20, 4));
      my $chunk = substr($sb, $bo + $identoff, 512);
      my $z = index($chunk, "\0");
      $r{ident} = $z >= 0 ? substr($chunk, 0, $z) : $chunk;
    } elsif ($magic == $CSMAGIC_BLOBWRAPPER && $len > 8) {
      $r{cms} = $len;
    }
  }
  return \%r;
}

# ---- run --------------------------------------------------------------------
my $spec = eval { JSON::PP->new->decode(slurp_raw($SPEC)) };
unless ($spec && ref($spec) eq 'HASH') { print "EMBEDDED ARTIFACT TESTS FAILED:\n  - component manifest unparseable\n"; exit 1 }
my $pin_entry = ($spec->{files} // [])->[0] // {};
my $guard = $spec->{implementation_guard} // {};

my ($ipa, $required) = pick_ipa();
if (!defined $ipa || (!-f $ipa && !$required)) {
  print "EMBEDDED ARTIFACT TESTS SKIPPED (no candidate IPA at dist/rebuild-3.1.6.1/PwEevee-3.1.6.1-rebuild.ipa or dist/PwEevee-3.1.6.1.ipa; set PWEEVEE_IPA=<path> to check a specific build)\n";
  exit 0;
}
unless (-f $ipa) {
  print "EMBEDDED ARTIFACT TESTS FAILED:\n  - PWEEVEE_IPA points at a missing file: $ipa\n";
  exit 1;
}
(my $ipa_rel = $ipa) =~ s{^\Q$ROOT\E/?}{};
print "candidate IPA: $ipa_rel\n";

my $dylib = zip_member($ipa, $MEMBER_DYLIB);
ok(defined $dylib, "IPA contains $MEMBER_DYLIB");
if (!defined $dylib) {
  print "EMBEDDED ARTIFACT TESTS FAILED:\n  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}

# 1. identity: the embedded object IS the pinned component
ok($pin_entry->{size} && length($dylib) == $pin_entry->{size},
   "embedded dylib size matches the component pin ($pin_entry->{size} vs " . length($dylib) . ')');
my $sha = sha256_hex($dylib);
ok($pin_entry->{sha256} && $sha eq $pin_entry->{sha256},
   "embedded dylib sha256 matches the component pin (" . substr($pin_entry->{sha256} // 'absent', 0, 16)
     . " vs " . substr($sha, 0, 16) . ')');
if (-f $PIN) {
  my $pin_bytes = slurp_raw($PIN);
  ok($pin_bytes eq $dylib, 'embedded dylib is byte-identical to the pinned component file');
}

# 2. dependency shape: bundle-relative Substrate, no absolute /Library edges
my @deps = eval { macho::dylibs($dylib) };
ok(!$@, 'embedded dylib parses as Mach-O');
my $substrate = grep { $_ eq '@rpath/CydiaSubstrate.framework/CydiaSubstrate' } @deps;
ok($substrate, 'embedded dylib loads @rpath/CydiaSubstrate.framework/CydiaSubstrate (rootless)');
my @absolute = grep { m{^/Library/} } @deps;
ok(!@absolute, 'embedded dylib has no absolute /Library dependency' . (@absolute ? ' (found: ' . join(', ', @absolute) . ')' : ''));
my $self_id = grep { $_ eq '@rpath/spotifyglass.dylib' } @deps;
ok($self_id, 'embedded dylib install name is @rpath/spotifyglass.dylib');

# 3. implementation markers (same contract unified.sh and dylib-guard-test.pl use)
for my $m (@{$guard->{required} // []}) {
  ok(index($dylib, $m) >= 0, "embedded dylib carries required marker: $m");
}
for my $m (@{$guard->{forbidden} // []}) {
  ok(index($dylib, $m) < 0, "embedded dylib does not carry forbidden marker: $m");
}

# 4. signature state: present, parseable, and not the '.unsigned' defect
my $cs = cs_report($dylib);
ok($cs->{present}, 'embedded dylib carries an LC_CODE_SIGNATURE');
ok($cs->{codedir}, 'embedded dylib has a CodeDirectory');
my $adhoc = defined $cs->{flags} && ($cs->{flags} & 0x2);
ok($adhoc || $cs->{cms},
   "embedded dylib signature is usable (ad-hoc flag or CMS blob;"
     . " flags=" . (defined $cs->{flags} ? sprintf('0x%x', $cs->{flags}) : 'none')
     . ", cms=" . ($cs->{cms} || 0) . ')');
ok(($cs->{ident} // '') !~ /\.unsigned$/,
   'embedded dylib identifier is not the Theos .unsigned intermediate (' . ($cs->{ident} || 'none') . ')');

# 5. host binary must resolve the bundle-relative Substrate (opt-in: 200 MB+ inflate)
if ($ENV{PWEEVEE_IPA_HOST}) {
  my $host = zip_member($ipa, $MEMBER_HOST);
  ok(defined $host, "IPA contains $MEMBER_HOST");
  if (defined $host) {
    my @hr = eval { macho::rpaths($host) };
    my $ok_rpath = grep { $_ eq '@executable_path/Frameworks' } @hr;
    ok($ok_rpath, 'host binary declares the @executable_path/Frameworks rpath');
    my @hd = eval { macho::dylibs($host) };
    my $loads = grep { m{spotifyglass\.dylib$} } @hd;
    ok($loads, 'host binary loads spotifyglass.dylib');
  }
} else {
  print "  (host-binary checks skipped; set PWEEVEE_IPA_HOST=1 to inflate Payload/Spotify.app/Spotify)\n";
}

if (@failures) {
  print "EMBEDDED ARTIFACT TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "EMBEDDED ARTIFACT TESTS PASSED ($pass checks)\n";
exit 0;
