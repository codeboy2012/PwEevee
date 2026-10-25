#!/usr/bin/env perl
# Regression tests for lib/bplist.pm (XML + binary property lists).
#
#   perl PwEvevee/build-system/tests/plist-roundtrip-tests.pl
#
# Covers the bugs found during the v3.1.0 audit work:
#   * writer emitted little-endian ref/offset fields (readers then threw)
#   * dict marker encoded pairs instead of 2x pair references
#   * trailer offsetTableOffset pointed after the table
#   * 8-byte ints collapsed through float arithmetic (-5 read back as 0)
#   * more than 256 objects was fatal
#   * same() compared dict key strings as nodes (always false)
use strict;
use warnings;
use File::Basename qw(dirname);
use lib dirname($0) . '/../lib';
use bplist;

my $pass = 0;
my @failures;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++ } else { push @failures, $what } }

# dies_like( \&code, qr/pattern/, $msg ): the code must die with a matching message.
sub dies_like {
  my ($code, $re, $what) = @_;
  my $ok_run = eval { $code->(); 1 };
  if (!$ok_run && $@ =~ $re) { $pass++; return }
  push @failures, $what . ' (did not die as expected: ' . ($ok_run ? 'no exception' : $@ =~ s/\s+\z//r) . ')';
}

my $tree = bplist::mkdict(
  s  => bplist::mkstr('ascii'),
  u  => bplist::mkstr("caf\xE9 \x{1F600}"),
  i  => bplist::mkint(-5),
  j  => bplist::mkint(70000),
  k  => bplist::mkint(0),
  ir => bplist::mkreal(1.5),
  bb => bplist::mkbool(1),
  d  => bplist::mkdata("\x00\x01\xff"),
  t2 => bplist::mkdate(1700000000),
  u2 => ['uid', 7],
  a  => bplist::mkarray(bplist::mkint(1), bplist::mkstr('x')));

my $bytes = bplist::write_bplist($tree);
ok(substr($bytes, 0, 8) eq 'bplist00', 'binary magic');

# ---------- round-trips ----------
ok(bplist::same($tree, bplist::read_bplist($bytes, 't1')), 'binary round-trip of mixed types');

# xml has no <uid> element; drop it for the xml legs
my @pairs = @{ $tree->[1] };
my $noUIDtree;
{
  my @q;
  for (my $i = 0; $i < @pairs; $i += 2) {
    next if $pairs[$i] eq 'u2';
    push @q, $pairs[$i], $pairs[$i + 1];
  }
  $noUIDtree = bplist::mkdict(@q);
}
my $xml = bplist::write_xml($noUIDtree);
ok(bplist::same($noUIDtree, bplist::read_xml($xml, 'x1')), 'xml round-trip of mixed types');

my $reread = bplist::read_data($xml, 'xmem');
ok($reread->{fmt} eq 'xml', 'xml payload detected as xml');
ok($reread->{root}[0] eq 'dict', 'xml root is a dict');

# cross-format: tree -> binary -> parsed -> xml -> parsed keeps the tree
my $uidFreeBin = bplist::write_bplist($noUIDtree);
ok(bplist::same($noUIDtree, bplist::read_xml(bplist::write_xml(bplist::read_bplist($uidFreeBin, 'xf')))), 'binary->parsed->xml->parsed keeps the tree');
ok(bplist::write_bplist(bplist::read_xml(bplist::write_xml($noUIDtree), 'xt')) eq bplist::write_bplist($noUIDtree), 'xml leg produces the same canonical binary');

# ---------- negative integers are exact (float-arithmetic bug) ----------
for my $n (-1, -5, -256, -70000) {
  my $y = bplist::read_bplist(bplist::write_bplist(bplist::mkint($n)), "neg$n");
  ok($y->[1] == $n, "negative int $n round-trips exactly");
}
dies_like(sub { bplist::write_bplist(bplist::mkint(-9331999999999999999999)) },
          qr/beyond signed 64-bit/, 'integers below -2**63 are rejected, not silently wrapped');

# ---------- more than 256 objects (object-ref cells grow) ----------
my @kv; push @kv, "key$_", bplist::mkstr("val$_") for 0 .. 499;          # 1001 objects
my $big = bplist::mkdict(@kv);
my $bb  = bplist::write_bplist($big);
my $brt = bplist::read_bplist($bb, 'big');
ok($brt->[1][0] eq 'key0' && scalar(@{ $brt->[1] }) == 1000, 'a 1001-object tree survives (2-byte refs)');
ok(bplist::write_bplist($big) eq $bb, 'big-tree output is deterministic');

# nested shared structure + unrelated keys stay intact
my $shared = bplist::mkstr('shared');
my $nest = bplist::mkdict(
  a => $shared, b => $shared, keepme => bplist::mkint(1),   # same refaddr twice
  deep => bplist::mkdict(x => bplist::mkarray($shared, bplist::mkbool(0))));
my $nest_rt = bplist::read_bplist(bplist::write_bplist($nest));
ok(bplist::same($nest, $nest_rt), 'shared subnodes and unrelated keys survive a rewrite');

# ---------- offset-table cell growth (offsets beyond 1 byte) ----------
my @big2; push @big2, "k$_", bplist::mkstr('y' x 900) for 0 .. 199;      # body ~183 KB
my $big2tree = bplist::mkdict(@big2);
my $f2 = bplist::write_bplist($big2tree);
my $trailer = substr($f2, -32, 32);
ok(unpack('C', substr($trailer, 6, 1)) >= 2, 'offsetIntSize grew past 1 byte for a large body');
ok(bplist::same(bplist::read_bplist($f2, 'f2'), $big2tree), 'large-body round-trip');

# ---------- same() semantics ----------
{
  my $a = bplist::mkdict(k => bplist::mkstr('v'));
  ok(bplist::same($a, bplist::mkdict(k => bplist::mkstr('v'))), 'same(): equal dicts are equal (key strings are not nodes)');
  ok(!bplist::same($a, bplist::mkdict(k => bplist::mkstr('w'))), 'same(): different leaf differs');
  ok(!bplist::same(bplist::mkdict(k => bplist::mkstr('v')), bplist::mkdict(j => bplist::mkstr('v'))), 'same(): different key differs');
}

# ---------- set() idempotence + keys() ----------
{
  my $t2 = bplist::read_data($bytes, 'm1');
  my @keys = bplist::keys($t2);
  ok((grep { $_ eq 's' } @keys) && (grep { $_ eq 'a' } @keys) && !(grep { $_ eq 'ascii' } @keys), 'keys() returns only key names');
  ok(bplist::set($t2, 'NewKey' => bplist::mkstr('v')) == 1, 'set() inserts a new key');
  ok(bplist::set($t2, 'NewKey' => bplist::mkstr('v')) == 0, 'set() is idempotent');
  ok(bplist::same(bplist::read_bplist(bplist::write_bplist($t2->{root})), $t2->{root}), 'mutated tree still round-trips');
}

# ---------- malformed-input negatives ----------
dies_like(sub { bplist::read_bplist('not a plist you are looking for' . ('x' x 30)) },
          qr/truncated|bad bplist/, 'short junk is rejected');
dies_like(sub { bplist::read_xml('<plist version="1.0"><dict><string></plist>' . "\n") },
          qr/malformed|expected an element|must start with <key>/, 'unclosed <dict> is rejected');
dies_like(sub { bplist::read_xml('not xml at all') },
          qr/not a property list|missing <plist>/, 'non-xml payload is rejected');
dies_like(sub { bplist::write_xml(bplist::mkdict(k => ['uid', 3])) },
          qr/no XML plist representation/, 'write_xml refuses uid nodes with a clear message');

# determinism: same tree twice -> identical bytes
my %seen; ok(bplist::write_bplist($tree) eq $bytes, 'binary output is byte-deterministic');

if (@failures) {
  print "PLIST ROUND-TRIP TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "PLIST ROUND-TRIP TESTS PASSED ($pass checks)\n";
exit 0;
