#!/usr/bin/env perl
# Extract the "body" field from a GitHub issue JSON file, unescaping \n, \r, \" .
use strict; use warnings;
binmode STDOUT;
local $/; my $d = <>;
if ($d =~ /"body"\s*:\s*(?:"((?:\\.|[^"\\])*)"|"body"\s*:\s*null)/s) {
    my $b = defined $1 ? $1 : '';
    my $out = '';
    while (length $b) {
        if (substr($b, 0, 1) eq '\\') {
            my $c = substr($b, 1, 1);
            if    ($c eq 'n') { $out .= "\n" }
            elsif ($c eq 't') { $out .= "\t" }
            elsif ($c eq '\\') { $out .= '\\' }
            elsif ($c eq '"') { $out .= '"' }
            elsif ($c eq 'u') { my $h = hex(substr($b, 2, 4)); $out .= ($h < 0x80) ? chr($h) : '?'; $b = substr($b, 2); }
            else { $out .= $c }
            $b = substr($b, 2);
        } else {
            $out .= substr($b, 0, 1);
            $b = substr($b, 1);
        }
    }
    print "BEGIN\n$out\nEND\n";
} else {
    print "NO BODY FOUND (len=" . length($d) . ")\n";
}
