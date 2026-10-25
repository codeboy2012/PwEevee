# XML and binary property-list read/write for the unified build.
#
#   PwEvevee/build-system/lib/bplist.pm
#
# The canonical input IPA's Info.plist is XML (stock Spotify 9.1.90), but other
# IPAs ship binary bplists. The alternate-icon registration step
# (package/patch-alternate-icon.pl) must mutate either format while keeping the
# rest of the file faithful, so both front-ends share one node representation
# and one query/set API. Output format matches the input format.
#
# Node representation (plain Perl tuples, insertion-ordered dicts):
#     ['dict',  [$k1,$v1,$k2,$v2,...]]   flat (key,value) pair list; keys are strings
#     ['array', [$v,$v,...]]
#     ['str',   "text"]
#     ['int',   42]                      may be negative
#     ['real',  0.5]
#     ['bool',  0|1]
#     ['data',  "raw bytes"]
#     ['date',  epoch_seconds]           seconds since 1970-01-01 UTC
#
# API:
#     bplist::read_file($path)             -> { fmt => 'bplist'|'xml', root => node }
#     bplist::read_data($bytes, $label)    -> same, from memory
#     bplist::read_bplist($bytes, $label)  -> node (binary only)
#     bplist::read_xml($bytes, $label)     -> node (XML only)
#     bplist::write_bplist($node)          -> canonical binary bytes
#     bplist::write_xml($node)             -> canonical XML bytes
#     bplist::serialize($tree)             -> bytes in the input's format
#     bplist::write_file($path, $tree)
#     bplist::get($tree, @keys)  get_if($tree, @keys)  has_key  keys  set  same
#     bplist::mkdict($k,$v,...)  mkarray(...)  mkstr  mkint  mkreal  mkbool  mkdata  mkdate
#
# Dependency policy matches the rest of lib/: core Perl only (plus the core
# MIME::Base64).
package bplist;
use strict;
use warnings;
use Exporter 'import';
use MIME::Base64 ();
use Scalar::Util qw(refaddr);
our @EXPORT_OK = qw(read_file read_data serialize write_file
                    read_bplist read_xml write_bplist write_xml
                    get get_if has_key keys set same mkdict mkarray mkstr mkint mkreal mkbool mkdata mkdate);
our @ISA = ('Exporter');

# ------------------------------------------------------------------ nodes

sub mkdict  { return ['dict',  [@_]] }          # flat (key,value) list
sub mkarray { return ['array', [@_]] }
sub mkstr   { my ($s) = @_; return ['str',  defined $s ? $s : ''] }
sub mkint   { my ($v) = @_; return ['int',  0 + $v] }
sub mkreal  { my ($v) = @_; return ['real', 0 + $v] }
sub mkbool  { my ($b) = @_; return ['bool', $b ? 1 : 0] }
sub mkdata  { my ($b) = @_; return ['data', defined $b ? $b : ''] }
sub mkdate  { my ($e) = @_; return ['date', 0 + $e] }

sub same {
  my ($a, $b) = @_;
  return 0 unless ref $a eq 'ARRAY' && ref $b eq 'ARRAY' && @$a == @$b && $a->[0] eq $b->[0];
  if ($a->[0] eq 'dict') {
    my ($pa, $pb) = ($a->[1], $b->[1]);
    return 0 unless @$pa == @$pb;
    for (my $i = 0; $i < @$pa; $i += 2) {
      return 0 unless $pa->[$i] eq $pb->[$i];    # keys are plain strings
      return 0 unless same($pa->[$i + 1], $pb->[$i + 1]);
    }
    return 1;
  }
  if ($a->[0] eq 'array') {
    my ($pa, $pb) = ($a->[1], $b->[1]);
    return 0 unless @$pa == @$pb;
    for my $i (0 .. $#$pa) { return 0 unless same($pa->[$i], $pb->[$i]) }
    return 1;
  }
  return 1 if $a->[0] eq 'bool';                 # normalized at construction
  return $a->[1] eq $b->[1];
}

# ------------------------------------------------------------------ queries

sub get_if {
  my ($tree, @path) = @_;
  my $node = $tree->{root} or return undef;
  for my $k (@path) {
    return undef unless $node->[0] eq 'dict';
    my $p = $node->[1];
    my $next;
    for (my $i = 0; $i < @$p; $i += 2) { if ($p->[$i] eq $k) { $next = $p->[$i + 1]; last } }
    return undef unless defined $next;
    $node = $next;
  }
  return $node;
}

sub get {
  my ($tree, @path) = @_;
  my $node = get_if($tree, @path);
  die "plist key not found: " . join('.', @path) . "\n" unless defined $node;
  return $node;
}

sub has_key { my ($tree, $key) = @_; return defined get_if($tree, $key) ? 1 : 0 }

sub keys {                                     # root-dict keys, insertion order
  my ($tree) = @_;
  die "keys() needs a dict root\n" unless $tree->{root}[0] eq 'dict';
  my $p = $tree->{root}[1];
  return map { $p->[$_] } grep { !($_ % 2) } 0 .. $#$p;
}

# set($tree, @keys, $value): create missing dict keys along the path as empty
# dicts, then insert or replace the leaf value. Returns 1 when the tree
# changed, 0 when the desired value was already in place (idempotence).
sub set {
  my $value = pop @_;
  my ($tree, @path) = @_;
  die "set() needs at least one key\n" unless @path;
  my $node = $tree->{root};
  for my $i (0 .. $#path) {
    my $k = $path[$i];
    die "attempt to descend into non-dict while setting key '$k'\n" unless $node->[0] eq 'dict';
    my $p = $node->[1];
    my $pos = -1; my $existing;
    for (my $j = 0; $j < @$p; $j += 2) { if ($p->[$j] eq $k) { $pos = $j; $existing = $p->[$j + 1]; last } }
    if ($i < $#path) {
      if (!defined $existing) { $existing = ['dict', []]; push @$p, $k, $existing }
      $node = $existing;
      next;
    }
    if (!defined $existing) { push @$p, $k, $value; return 1 }    # new leaf key
    return 0 if same($existing, $value);                         # already correct
    die "key '$k' exists with a non-" . $value->[0] . " value\n" unless $existing->[0] eq $value->[0];
    $p->[ $pos + 1 ] = $value;
    return 1;
  }
  die "unreachable";
}

# ------------------------------------------------------------------ format detection

sub read_file {
  my ($path) = @_;
  open(my $f, '<:raw', $path) or die "open $path: $!";
  local $/; my $d = <$f>; close $f;
  die "empty plist: $path\n" unless defined $d && length $d;
  return read_data($d, $path);
}

sub read_data {
  my ($d, $label) = @_;
  $label = defined $label ? " ($label)" : '';
  if (length($d) >= 6 && substr($d, 0, 6) eq 'bplist') { return { fmt => 'bplist', root => read_bplist($d, $label) } }
  if ($d =~ /<plist\s/) { return { fmt => 'xml', root => read_xml($d, $label) } }
  die "not a property list$label\n";
}

sub serialize { my ($tree) = @_; return $tree->{fmt} eq 'bplist' ? write_bplist($tree->{root}) : write_xml($tree->{root}) }

sub write_file {
  my ($path, $tree) = @_;
  my $bytes = serialize($tree);
  open(my $o, '>:raw', $path) or die "write $path: $!";
  print $o $bytes;
  close $o;
  return length $bytes;
}

# =================================================================== binary plist reader

sub _ube {
  my ($d, $o, $n) = @_;
  my $v = 0;
  for my $i (0 .. $n - 1) { $v = $v * 256 + unpack('C', substr($d, $o + $i, 1)) }
  return $v;
}

sub read_bplist {
  my ($d, $label) = @_;
  $label = defined $label ? " ($label)" : '';
  die "truncated bplist$label\n" if length($d) < 40;
  my $tr = substr($d, -32, 32);
  my $osize  = unpack('C', substr($tr, 6, 1));
  my $rsize  = unpack('C', substr($tr, 7, 1));
  my $numobj = _ube($tr,  8, 8);
  my $top    = _ube($tr, 16, 8);
  my $offtab = _ube($tr, 24, 8);
  die "bad bplist trailer$label\n"
    unless 1 <= $osize && $osize <= 8 && 1 <= $rsize && $rsize <= 8 && $offtab < length($d);
  die "bad bplist top-object index$label\n" if $top >= $numobj;

  my $objoff = sub {
    my ($i) = @_;
    die "object index $i out of range$label\n" if $i >= $numobj;
    my $off = _ube($d, $offtab + $osize * $i, $osize);
    die "object $i at offset $off beyond EOF$label\n" if $off >= length($d);
    return $off;
  };

  my $read;
  $read = sub {
    my ($idx) = @_;
    my $o  = $objoff->($idx);
    my $b0 = unpack('C', substr($d, $o, 1));
    my $t  = $b0 >> 4;
    my $n  = $b0 & 0x0F;

    my $hdr = 1;
    if ($n == 15) {
      die "extended-length marker missing at $o$label\n" if $o + 2 > length($d);
      my $m = unpack('C', substr($d, $o + 1, 1));
      die "bad extended-length marker at $o$label\n" unless ($m >> 4) == 1 && ($m & 0x0F) <= 3;
      $hdr = 2 + (1 << ($m & 0x0F));
    }
    my $count = sub {
      my ($o2, $n2) = @_;
      return $n2 unless $n2 == 15;
      my $m2 = unpack('C', substr($d, $o2 + 1, 1));
      die "bad extended-count marker at $o2$label\n" unless ($m2 >> 4) == 1 && ($m2 & 0x0F) <= 3;
      return _ube($d, $o2 + 2, 1 << ($m2 & 0x0F));
    };

    if ($t == 0x0) {
      return mkbool(1) if $n == 9;
      return mkbool(0) if $n == 8;
      die "unsupported simple object marker 0x0$n at $o$label\n";
    }
    if ($t == 0x1) {
      die "int size code $n unsupported at $o$label\n" if $n > 3;
      my $len = 1 << $n;
      die "truncated integer at $o$label\n" if $o + $hdr + $len > length($d);
      # 8-byte signed integers are read straight out of the bytes:
      # reconstructing them through _ube's float arithmetic would round
      # everything above 2**53 onto the same double (a stored -5 would come
      # back as 0).
      my $v = $len == 8 ? unpack('q>', substr($d, $o + $hdr, 8)) : _ube($d, $o + $hdr, $len);
      return mkint($v);
    }
    if ($t == 0x2) {
      die "real size code $n unsupported at $o$label\n" unless $n == 2 || $n == 3;
      my $v = $n == 2 ? unpack('f>', substr($d, $o + $hdr, 4)) : unpack('d>', substr($d, $o + $hdr, 8));
      return mkreal($v);
    }
    if ($t == 0x3) {
      die "truncated date at $o$label\n" if $o + $hdr + 8 > length($d);
      return mkdate(unpack('d>', substr($d, $o + $hdr, 8)) + 978307200);
    }
    if ($t == 0x4) { return mkdata(substr($d, $o + $hdr, $count->($o, $n))) }
    if ($t == 0x5) { return mkstr(substr($d, $o + $hdr, $count->($o, $n))) }
    if ($t == 0x6) {
      my $units = $count->($o, $n);
      die "truncated UTF-16 string at $o$label\n" if $o + $hdr + $units * 2 > length($d);
      my @u = unpack('n*', substr($d, $o + $hdr, $units * 2));
      my $s = '';
      while (@u) {
        my $c = shift @u;
        if ($c >= 0xD800 && $c <= 0xDBFF && @u && $u[0] >= 0xDC00 && $u[0] <= 0xDFFF) {
          my $c2 = shift @u;
          $s .= chr(0x10000 + (($c - 0xD800) << 10) + ($c2 - 0xDC00));
        } else { $s .= chr($c) }
      }
      return mkstr($s);
    }
    if ($t == 0x8) {
      die "uid size code $n unsupported at $o$label\n" if $n > 3;
      return ['uid', _ube($d, $o + $hdr, $n + 1)];
    }
    if ($t == 0xA || $t == 0xC) {   # array (0xC "set" is laid out identically)
      my $cnt = $count->($o, $n);
      die "truncated array refs at $o$label\n" if $o + $hdr + $cnt * $rsize > length($d);
      my @v;
      for my $i (0 .. $cnt - 1) { push @v, $read->(_ube($d, $o + $hdr + $i * $rsize, $rsize)) }
      return mkarray(@v);
    }
    if ($t == 0xD) {
      my $cnt = $count->($o, $n);
      die "dict with odd entry count$label\n" if $cnt % 2;
      die "truncated dict refs at $o$label\n" if $o + $hdr + $cnt * $rsize > length($d);
      my $npairs = $cnt / 2;
      my @pairs;
      for my $i (0 .. $npairs - 1) {
        my $k = $read->(_ube($d, $o + $hdr + $i * $rsize, $rsize));
        my $v = $read->(_ube($d, $o + $hdr + ($npairs + $i) * $rsize, $rsize));
        die "non-string dict key at $o$label\n" unless $k->[0] eq 'str';
        push @pairs, $k->[1], $v;
      }
      return mkdict(@pairs);
    }
    die sprintf("unsupported bplist marker 0x%02x at offset %d%s\n", $b0, $o, $label);
  };
  return $read->($top);
}

# =================================================================== binary plist writer
#
# Deterministic: objects serialized in first-visit post-order (root last),
# shared subnodes reused by refaddr, insertion order preserved. A first
# counting pass sizes the object-reference table (1, 2 or 4 bytes) before any
# reference is written, so trees of any practical size — not just 256 objects
# — serialize identically run over run.

sub _be {                                          # big-endian, n bytes
  my ($v, $n) = @_;
  my @b = (0) x $n;
  for my $i (0 .. $n - 1) { $b[$i] = $v % 256; $v = int($v / 256) }   # LSB first
  return pack('C*', reverse @b);                   # emit MSB first
}

sub _hdr {
  my ($tag, $len) = @_;
  return pack('C', ($tag << 4) | $len) if $len <= 0x0F;
  my $power = 16; my $enc = 0;
  while ($len > $power) { $power *= 256; $enc++; die "extended length too large\n" if $enc > 3 }
  return pack('C', ($tag << 4) | 0x0F) . pack('C', 0x10 | $enc) . _be($len, 1 << $enc);
}

sub _is_ascii { my ($s) = @_; return !utf8::is_utf8($s) && ($s !~ /[^\x20-\x7e]/) }

sub write_bplist {
  my ($root) = @_;

  # pass 1: count exactly the objects pass 2 will create — same first-visit
  # post-order, same shared-node dedupe, fresh mkstr() for every dict key —
  # so the object-ref size is known before the first reference is written.
  my $count = 0;
  my %cseen;
  my @keep;                     # every visited node stays alive: refaddr is
                                # only unique while the referent exists, and
                                # temp dict-key nodes would otherwise be freed
                                # and their addresses reused by the next one
  my $cnode;
  $cnode = sub {
    my ($nd) = @_;
    my $ra = refaddr($nd) or die "internal: non-ref node\n";
    return if $cseen{$ra}++;
    push @keep, $nd;
    $count++;
    if    ($nd->[0] eq 'array') { $cnode->($_) for @{ $nd->[1] } }
    elsif ($nd->[0] eq 'dict') {
      my $p = $nd->[1];
      die "dict payload must be (key,value) pairs\n" if @$p % 2;
      for (my $i = 0; $i < @$p; $i += 2) { $cnode->(mkstr($p->[$i])); $cnode->($p->[$i + 1]) }
    }
  };
  $cnode->($root);
  die "bplist writer: more than 2**32 objects\n" if $count > 4294967295;
  my $rsize = $count <= 0xFF ? 1 : $count <= 0xFFFF ? 2 : 4;

  # pass 2: emit the objects. Arrays and dicts reference previously emitted
  # objects with $rsize-byte big-endian indices.
  my @objs;
  my %idx_of;
  my $emit;   # @keep from pass 1 stays in scope and alive
  $emit = sub {
    my ($node) = @_;
    my $ra = refaddr($node) or die "internal: non-ref node\n";
    return $idx_of{$ra} if exists $idx_of{$ra};
    push @keep, $node;

    my $payload;
    my $t = $node->[0];
    if ($t eq 'bool') {
      $payload = pack('C', $node->[1] ? 0x09 : 0x08);
    }
    elsif ($t eq 'int') {
      my $v = $node->[1];
      # pack('q>') keeps the byte pattern exact for full-width values;
      # building the two's complement by adding 2**64 in float arithmetic
      # would round and corrupt anything above 2**53.
      if    ($v < 0)           { die "integer beyond signed 64-bit range: $v\n" if $v <= -(2**63);
                                 $payload = pack('C', 0x13) . pack('q>', $v) }
      elsif ($v < 0x100)       { $payload = pack('C', 0x10) . _be($v, 1) }
      elsif ($v < 0x10000)     { $payload = pack('C', 0x11) . _be($v, 2) }
      elsif ($v < 4294967296)  { $payload = pack('C', 0x12) . _be($v, 4) }
      else                     { $payload = pack('C', 0x13) . pack('q>', $v) }
    }
    elsif ($t eq 'real') { $payload = pack('C', 0x23) . pack('d>', $node->[1]) }
    elsif ($t eq 'date') { $payload = pack('C', 0x33) . pack('d>', $node->[1] - 978307200) }
    elsif ($t eq 'data') { $payload = _hdr(0x4, length($node->[1])) . $node->[1] }
    elsif ($t eq 'str') {
      my $s = $node->[1];
      if (_is_ascii($s)) { $payload = _hdr(0x5, length $s) . $s }
      else {
        utf8::decode($s) unless utf8::is_utf8($s);
        my @u;
        for my $cp (map { ord } split //, $s) {
          if ($cp < 0x10000) { push @u, $cp }
          else {
            my $r = $cp - 0x10000;
            push @u, 0xD800 + ($r >> 10), 0xDC00 + ($r & 0x3FF);
          }
        }
        $payload = _hdr(0x6, scalar @u) . pack('n*', @u);
      }
    }
    elsif ($t eq 'uid') {             # round-trip fidelity for keyed archives
      my $v = $node->[1];
      my $n = $v < 0x100 ? 0 : $v < 0x10000 ? 1 : $v < 4294967296 ? 3 : 7;
      $payload = pack('C', 0x80 | $n) . _be($v, $n + 1);
    }
    elsif ($t eq 'array') {
      my @refs = map { $emit->($_) } @{ $node->[1] };
      $payload = _hdr(0xA, scalar @refs) . join('', map { _be($_, $rsize) } @refs);
    }
    elsif ($t eq 'dict') {
      my $p = $node->[1];
      die "dict payload must be (key,value) pairs\n" if @$p % 2;
      my $npairs = @$p / 2;
      my (@krefs, @vrefs);
      for (my $i = 0; $i < @$p; $i += 2) {
        push @krefs, $emit->(mkstr($p->[$i]));
        push @vrefs, $emit->($p->[$i + 1]);
      }
      # the dict marker counts OBJECT REFERENCES, i.e. two per pair
      # (all key refs followed by all value refs) — one table.
      $payload = _hdr(0xD, 2 * $npairs)
               . join('', map { _be($_, $rsize) } @krefs)
               . join('', map { _be($_, $rsize) } @vrefs);
    }
    else { die "write_xml: node type '$t' has no XML plist representation\n" }

    push @objs, $payload;
    return $idx_of{$ra} = $#objs;
  };
  my $top = $emit->($root);
  die "internal: count pass saw $count objects, emit pass made " . scalar(@objs) . "\n"
    unless @objs == $count;

  # offset table: the cell size must be able to express the total end offset,
  # which includes the table itself, so pick the smallest cell size at the
  # fixpoint (body length is independent of the cell size).
  my $body = '';
  for my $o (@objs) { $body .= $o }
  my $bodylen = length $body;
  # bplist00 offsets are file-absolute (the 8-byte 'bplist00' header counts),
  # so the fixpoint includes both the header and the offset table itself.
  my $osize = 1;
  while (8 + $bodylen + $count * $osize > 0x100**$osize - 1) {
    $osize++;
    die "bplist writer: offset table exceeds 4-byte cells\n" if $osize > 4;
  }
  my @offs; my $fd = 8;
  for my $o (@objs) { push @offs, $fd; $fd += length $o }
  my $table = join '', map { _be($_, $osize) } @offs;
  # 32-byte trailer (cf. plistlib '>6xBBQQQ'): bytes 6/7 are the offset- and
  # object-ref sizes, then numObjects, topObject index and the offset-table
  # offset as 8-byte big-endian quads.
  my $trailer = "\0" x 6
              . pack('CC', $osize, $rsize)
              . _be(scalar @objs, 8)
              . _be($top, 8)
              . _be(8 + $bodylen, 8);   # offset table starts right after the body
  return 'bplist00' . $body . $table . $trailer;
}

# =================================================================== XML plist reader

sub read_xml {
  my ($d, $label) = @_;
  $label = defined $label ? " ($label)" : '';
  utf8::decode($d);   # XML payload is UTF-8; decode to wide chars
  my $s = $d;
  $s =~ s/<\?xml[^>]*\?>//;
  $s =~ s/<!DOCTYPE[^>]*>//;
  $s =~ s/<!--.*?-->//sg;
  $s =~ /\A([ \t\r\n]*)/; my $skip = length($1 || '');
  $s = substr($s, $skip);
  die "missing <plist> root element$label\n" unless $s =~ /^<plist\s+version="1\.0">/;
  my $pos = length($&);
  my ($root, $endpos) = _xml_node($s, $pos, $label);
  die "malformed plist XML$label: unparsed trailing content\n"
    unless substr($s, $endpos) =~ /^\s*<\/plist\s*>\s*\z/;
  return $root;
}

# _xml_node( $s, $pos, $label ) parses ONE element and returns ( node, next position ).
sub _xml_node {
  my ($s, $pos, $label) = @_;

  $pos += length($1) if substr($s, $pos) =~ /\A(\s+)/;
  die "malformed plist XML$label: expected an element near position $pos\n"
    unless substr($s, $pos) =~ /\A<([A-Za-z]+)(\s*\/?)\s*>/;
  my $tag = $1;
  my $whole = $&;                # captured BEFORE any later match clobbers $&
  my $selfclose = ($2 =~ m{/$}) ? 1 : 0;
  $pos += length($whole);   # NOTE: $+[0] would be relative to the substr() we matched against

  die "unknown plist element <$tag>$label\n"
    unless $tag eq 'dict' || $tag eq 'array' || $tag eq 'string' || $tag eq 'integer'
        || $tag eq 'real' || $tag eq 'true' || $tag eq 'false' || $tag eq 'date' || $tag eq 'data';

  # <true/> <false/>
  if ($tag eq 'true' || $tag eq 'false') {
    if ($selfclose) { return (mkbool($tag eq 'true' ? 1 : 0), $pos) }
    die "content inside <$tag>$label\n" unless substr($s, $pos) =~ /\A\s*<\/$tag\s*>/;
    $pos += length($&);
    return (mkbool($tag eq 'true' ? 1 : 0), $pos);
  }
  die "malformed plist XML$label: <$tag> must not be self-closing\n" if $selfclose;

  if ($tag eq 'dict') {
    my @pairs;
    while (1) {
      $pos += length($1) if substr($s, $pos) =~ /\A(\s+)/;
      if (substr($s, $pos) =~ /\A<\/dict\s*>/) { $pos += length($&); last }
      die "dict members must start with <key>$label near position $pos\n"
        unless substr($s, $pos) =~ /\A<key>([^<]*)<\/key\s*>/;
      my $keywhole = $&;
      my $key = _unescape($1);
      $pos += length($keywhole);
      my ($v, $next) = _xml_node($s, $pos, $label);
      push @pairs, $key, $v;
      $pos = $next;
    }
    return (mkdict(@pairs), $pos);
  }

  if ($tag eq 'array') {
    my @items;
    while (1) {
      $pos += length($1) if substr($s, $pos) =~ /\A(\s+)/;
      if (substr($s, $pos) =~ /\A<\/array\s*>/) { $pos += length($&); last }
      my ($v, $next) = _xml_node($s, $pos, $label);
      push @items, $v;
      $pos = $next;
    }
    return (mkarray(@items), $pos);
  }

  # scalar elements: everything up to the matching close tag is the payload
  my $close = index($s, "</$tag>", $pos);
  die "unclosed <$tag>$label\n" if $close < 0;
  my $payload = substr($s, $pos, $close - $pos);
  $pos = $close + length($tag) + 3;   # "</$tag>"
  if ($tag eq 'string') { return (mkstr(_unescape($payload)), $pos) }
  if ($tag eq 'integer') {
    $payload =~ /\A\s*([+-]?[0-9]+)\s*\z/ or die "malformed <integer>$label: '$payload'\n";
    die "<integer> beyond 64-bit range$label: '$payload'\n" if $1 > 9223372036854775807;
    return (mkint($1), $pos);
  }
  if ($tag eq 'real') {
    $payload =~ /\A\s*([+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)\s*\z/
      or die "malformed <real>$label: '$payload'\n";
    return (mkreal($1 + 0), $pos);
  }
  if ($tag eq 'date') {
    $payload =~ /\A\s*(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z\s*\z/
      or die "unsupported plist <date> format$label: '$payload'\n";
    return (mkdate(_timegm($1, $2 - 1, $3, $4, $5, $6)), $pos);
  }
  if ($tag eq 'data') {
    my $clean = $payload; $clean =~ s/\s+//g;
    return (mkdata(MIME::Base64::decode_base64($clean)), $pos);
  }
  die "internal: unreachable XML element '$tag'\n";
}

sub _unescape {
  my ($s) = @_;
  $s =~ s/&lt;/</g;
  $s =~ s/&gt;/>/g;
  $s =~ s/&quot;/"/g;
  $s =~ s/&apos;/'/g;
  $s =~ s/&\#x([0-9A-Fa-f]+);/chr(hex($1))/ge;
  $s =~ s/&\#([0-9]+);/chr($1)/ge;
  $s =~ s/&amp;/&/g;
  return $s;
}

# plain UTC arithmetic over the Gregorian calendar (no leap-second handling)
sub _timegm {
  my ($y, $mo, $d, $h, $mi, $se) = @_;
  my @days = (31,28,31,30,31,30,31,31,30,31,30,31);
  $days[1] = 29 if ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
  die "bad date month\n" if $mo < 0 || $mo > 11;
  die "bad date day $d\n" if $d < 1 || $d > $days[$mo];
  my $cum = 0; $cum += $days[$_] for 0 .. $mo - 1;
  my $leaps = 0;
  for (my $yy = 1970; $yy < $y; $yy++) { $leaps++ if $yy % 4 == 0 && ($yy % 100 != 0 || $yy % 400 == 0) }
  return (((($y - 1970) * 365 + $leaps + $cum + ($d - 1)) * 24 + $h) * 60 + $mi) * 60 + $se;
}

# =================================================================== XML plist writer (canonical, deterministic)

sub _xml_escape {
  my ($s) = @_;
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/>/&gt;/g;
  utf8::decode($s) unless utf8::is_utf8($s);
  $s =~ s/([^\x20-\x7e])/ sprintf("&\#x%04x;", ord($1)) /ge;
  return $s;
}

sub _fmt_real {
  my ($v) = @_;
  my $s = sprintf("%.17g", $v);
  $s = sprintf("%g", $v)   if $s !~ /\./ && abs($v) < 1e15;
  $s .= ".0"               if $s !~ /[\.eE]/;
  return $s;
}

sub _xml_date {
  my ($epoch) = @_;
  my $d = int($epoch / 86400); my $rem = $epoch - $d * 86400;
  my $h = int($rem / 3600); my $mi = int(($rem % 3600) / 60); my $sec = $rem % 60;
  my $y = 1970;
  while (1) {
    my $days = ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0)) ? 366 : 365;
    last if $d >= 0 && $d < $days;
    if ($d < 0) { $y--; $d += ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0)) ? 366 : 365 }
    else { $d -= $days; $y++ }
  }
  my @days = (31,28,31,30,31,30,31,31,30,31,30,31);
  $days[1] = 29 if ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
  my $mo = 0;
  while ($d >= $days[$mo]) { $d -= $days[$mo]; $mo++ }
  return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", $y, $mo + 1, $d + 1, $h, $mi, $sec);
}

sub write_xml {
  my ($root) = @_;
  my $out = '';
  _xml_ser(\$out, $root, 0);
  return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
       . "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
       . "<plist version=\"1.0\">\n" . $out . "</plist>\n";
}

sub _xml_ser {
  my ($outref, $node, $depth) = @_;
  my $ind = '  ' x ($depth + 1);
  my $t = $node->[0];
  if    ($t eq 'bool')  { $$outref .= $ind . ($node->[1] ? '<true/>' : '<false/>') . "\n" }
  elsif ($t eq 'str')   { $$outref .= $ind . '<string>' . _xml_escape($node->[1]) . "</string>\n" }
  elsif ($t eq 'int')   { $$outref .= $ind . '<integer>' . $node->[1] . "</integer>\n" }
  elsif ($t eq 'real')  { $$outref .= $ind . '<real>' . _fmt_real($node->[1]) . "</real>\n" }
  elsif ($t eq 'date')  { $$outref .= $ind . '<date>' . _xml_date($node->[1]) . "</date>\n" }
  elsif ($t eq 'data') {
    my $b64 = MIME::Base64::encode_base64($node->[1], '');
    my @lines = ($b64 =~ /(.{1,72})/g);
    $$outref .= $ind . "<data>\n";
    $$outref .= $ind . "  $_\n" for @lines;
    $$outref .= $ind . "</data>\n";
  }
  elsif ($t eq 'array') {
    $$outref .= $ind . "<array>\n";
    _xml_ser($outref, $_, $depth + 1) for @{ $node->[1] };
    $$outref .= $ind . "</array>\n";
  }
  elsif ($t eq 'dict') {
    my $p = $node->[1];
    die "dict payload must be (key,value) pairs\n" if @$p % 2;
    $$outref .= $ind . "<dict>\n";
    for (my $i = 0; $i < @$p; $i += 2) {
      die "dict member '$p->[$i]' has no value\n" unless defined $p->[$i + 1];
      $$outref .= $ind . '<key>' . _xml_escape($p->[$i]) . "</key>\n";
      _xml_ser($outref, $p->[$i + 1], $depth + 1);
    }
    $$outref .= $ind . "</dict>\n";
  }
  else { die "write_xml: node type '$t' has no XML plist representation\n" }
}

1;
