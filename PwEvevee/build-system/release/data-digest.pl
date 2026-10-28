#!/usr/bin/env perl
# ============================================================================
# data-digest.pl — "did the deployable site actually change?"
# ============================================================================
#
#   perl PwEvevee/build-system/release/data-digest.pl [--tree DIR] [--verbose]
#
# Prints one line:  <sha256>  <files>  <tree>
#
# The digest covers every file of the tree, but the volatile bookkeeping is
# normalized away first, in the two places it lives:
#
#   1. in the generated JSON — generated_at, release_data_generated_at,
#      per-repository fetched_at / stale_since / etag, per-asset / per-record
#      verified_at, checked_at, refreshed_at. These say *when* a refresh ran,
#      not what it found.
#   2. in the rendered pages — the same refresh timestamps are embedded as
#      machine-readable `<time datetime="...">` values (and the browser
#      freshness check reads the data files directly). Each such ISO timestamp
#      is replaced by a placeholder wherever it appears, so a page rendered a
#      minute later is recognized as the same page.
#
# Without this a fifteen-minute cycle could never prove "nothing changed": it
# would commit and re-publish a byte-different but content-identical site
# forever. Everything else is hashed exactly as written, so the digest can
# under-report a change in a volatile field and never a change in content — and
# because the pages are hashed too, any change a visitor could actually see
# (a version, a date, a number, a link) still moves the digest.
#
# JSON that does not parse is hashed byte for byte: a broken data file is a
# change, not something to normalize away.
#
# Options
#   --tree DIR    directory to digest (default: website)
#   --verbose     list each file's path and the digest it contributed
#   --quiet       print the bare digest only (for shell substitution)
#   -h, --help
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/lib";
use File::Find ();
use File::Spec ();
use Digest::SHA qw(sha256_hex);
use JSON::PP ();

my %opt = (tree => 'website');
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--tree')    { $opt{tree}    = shift @ARGV }
    elsif ($a eq '--verbose') { $opt{verbose} = 1 }
    elsif ($a eq '--quiet')   { $opt{quiet}   = 1 }
    elsif ($a eq '-h' || $a eq '--help') { usage(); exit 0 }
    else { die "unknown option: $a (try --help)\n" }
}
defined $opt{tree} && length $opt{tree} or die "--tree needs a directory\n";
-d $opt{tree} or die "not a directory: $opt{tree}\n";

# Bookkeeping that records *when* something was refreshed. None of it is shown
# as content a visitor could act on differently, and all of it changes on every
# successful run.
my %VOLATILE = map { $_ => 1 }
    qw(generated_at release_data_generated_at fetched_at stale_since
       verified_at checked_at refreshed_at etag
       pushed_at);

# pushed_at is normalized for the same reason as the timestamps, but it has a
# sharper edge: committing a refreshed snapshot IS a push, so a run that
# compared it would see its own previous commit as new data — and a scheduler
# that commits on change would commit again, forever. It is repository
# bookkeeping, not something the site renders.

my @files;
File::Find::find({
    no_chdir => 1,
    wanted   => sub {
        my $p = $File::Find::name;
        return unless -f $p && !-l $p;
        push @files, $p;
    },
}, $opt{tree});
@files = sort @files;

my (%content, %stamp);
for my $path (@files) {
    open(my $fh, '<:raw', $path) or die "open $path: $!\n";
    local $/;
    my $bytes = <$fh>;
    close $fh;

    if ($path =~ /\.json$/i) {
        my $decoded = eval { JSON::PP->new->utf8->decode($bytes) };
        if (defined $decoded) {
            strip_volatile($decoded);
            $bytes = JSON::PP->new->utf8->canonical->allow_nonref->encode($decoded);
        }
    }
    $content{$path} = $bytes;
}

my $acc = Digest::SHA->new(256);
my @stamps = sort { length($b) <=> length($a) || $a cmp $b } keys %stamp;
for my $path (@files) {
    my $rel = File::Spec->abs2rel($path, $opt{tree});
    $rel =~ s{\\}{/}g;              # one spelling of the path on every platform

    my $bytes = $content{$path};
    # Only ISO-8601 instants are substituted: they are unambiguous, they cannot
    # collide with prose, and they are exactly what the pages embed.
    $bytes =~ s/\Q$_\E/\x00VOLATILE\x00/g for @stamps;

    $acc->add($rel, "\0", $bytes, "\0");
    print "  $rel\n" if $opt{verbose};
}

my $digest = $acc->hexdigest;
if ($opt{quiet}) {
    print "$digest\n";
} else {
    printf "%s  %d files  %s\n", $digest, scalar(@files), $opt{tree};
    printf "  (%d volatile timestamp%s normalized)\n", scalar(@stamps), (@stamps == 1 ? '' : 's');
}
exit 0;

# Remove the volatile keys anywhere in the structure, remembering the ISO
# instants they held so the same values can be neutralized inside the pages.
sub strip_volatile {
    my ($node) = @_;
    if (ref $node eq 'HASH') {
        for my $k (keys %$node) {
            if ($VOLATILE{$k}) {
                my $v = $node->{$k};
                $stamp{$v} = 1
                    if defined $v && !ref $v
                    && $v =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
                delete $node->{$k};
                next;
            }
            strip_volatile($node->{$k});
        }
    } elsif (ref $node eq 'ARRAY') {
        strip_volatile($_) for @$node;
    }
    return $node;
}

sub usage {
    print <<'USAGE';
usage: perl PwEvevee/build-system/release/data-digest.pl [options]

  --tree DIR    directory to digest (default: website)
  --verbose     list each file's path
  --quiet       print the bare digest only

Prints  <sha256>  <files>  <tree>  for a tree whose generated JSON has had its
volatile bookkeeping fields normalized away and whose pages have had the same
refresh instants neutralized, so "nothing changed" is provable.
USAGE
}
