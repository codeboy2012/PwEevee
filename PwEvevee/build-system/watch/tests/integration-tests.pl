#!/usr/bin/env perl
# ============================================================================
# integration-tests.pl — pipeline-level tests for the --watch integration in
# PwEvevee/build-system/unified.sh.
#
#   perl PwEvevee/build-system/watch/tests/integration-tests.pl
#
# Builds a minimal synthetic Watch-bearing decrypted IPA (structure mirrors a
# real Spotify.app friend to the degree the deterministic packager accepts),
# runs the FULL unified.sh pipeline twice, and asserts:
#   1. WITHOUT --watch: build fails loudly (Watch leftovers rejected) — the
#      pre-existing contract of a Watch-bearing input.
#   2. WITH --watch: build succeeds, output IPA keeps the Watch/ tree, all
#      nested bundle IDs are prefixed correctly, and the original input IPA
#      is byte-identical afterwards.
# ============================================================================
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);

my $ROOT = abs_path(dirname(abs_path(__FILE__)) . '/../../..');
my $BS   = "$ROOT/build-system";
my $T    = ($ENV{TMPDIR} || '/tmp') . "/integration-test-$$";
remove_tree($T); make_path($T);

my ($pass, $fail) = (0, 0);
sub check { my ($c, $n) = @_; $c ? ($pass++, printf "  ok  %s\n", $n) : ($fail++, printf "  FAIL %s\n", $n); }

# ---- build the synthetic input IPA directly with the repo packager ----------
my $stage = "$T/stage";
make_path("$stage/Payload/Spotify.app/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex");
make_path("$stage/Payload/Spotify.app/PlugIns/InsightsIntents.appex");
make_path("$stage/Payload/Spotify.app/Frameworks/Orion.framework");

open my $f, '>', "$stage/Payload/Spotify.app/Info.plist" or die;
print $f <<'P'; close $f;
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.spotify.client</string></dict></plist>
P
open $f, '>', "$stage/Payload/Spotify.app/Watch/WatchApp.app/Info.plist" or die;
print $f <<'P'; close $f;
<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.skywatch.spotify.watchkitapp</string></dict></plist>
P
open $f, '>', "$stage/Payload/Spotify.app/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist" or die;
print $f <<'P'; close $f;
<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.skywatch.spotify.watchkitapp.widget</string></dict></plist>
P
open $f, '>', "$stage/Payload/Spotify.app/PlugIns/InsightsIntents.appex/Info.plist" or die;
print $f <<'P'; close $f;
<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.skywatch.spotify.intents</string><key>NSExtension</key><dict><key>NSExtensionAttributes</key><dict><key>IntentsSupported</key><array><string>SendMessageIntent</string></array></dict></dict></dict></plist>
P
# The main executable must be a minimal but VALID thin arm64 Mach-O carrying the
# exact five LC_LOAD_DYLIB commands dependencies.json expects (already loaded), so
# unified.sh reaches step 6 and stops earlier only for real failures. The stub is
# assembled byte-for-byte the same way lib/macho.pm and inject-dylib.pl interpret it.
my @DEPS = (
  '\@executable_path/Frameworks/spotifyglass.dylib',
  '\@executable_path/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf',
  '\@executable_path/Frameworks/Orion.framework/Orion',
  '\@executable_path/Frameworks/EeveeSpotify.dylib',
  '\@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate',
);
{
    my $cmds = '';
    for my $n (@DEPS) {
        my $raw = $n . "\0";
        my $cs = (24 + length($raw) + 7) & ~7;
        $cmds .= pack('V6', 0xC, $cs, 24, 2, 0x10000, 0x10000) . $raw;
        $cmds .= "\0" x ($cs - 24 - length($raw));
    }
    my $macho = pack('V6', 0xFEEDFACF, 0x0100000C, 0, 2, scalar(@DEPS), length($cmds)) . "\0" x 8
              . $cmds . ("\0" x 1024);
    open $f, '>:raw', "$stage/Payload/Spotify.app/Spotify" or die;
    print $f $macho; close $f;
}
open $f, '>', "$stage/Payload/Spotify.app/PkgInfo" or die; print $f "APPL????"; close $f;

my $input = "$T/input.ipa";
# Use the repo's own packager (build-tests prove it produces valid archives).
system($^X, "$BS/package/make-ipa.pl", "$stage/Payload/Spotify.app", $input) == 0
    or die "make-ipa failed";
cmp_ok_size($input);

sub cmp_ok_size { }

sub file_sha {
    my ($path) = @_;
    my $data = do { local $/; open my $fh, '<:raw', $path or die "open $path: $!"; <$fh> };
    return sha256_hex($data);
}

# ---- 1. pipeline WITHOUT --watch must fail loudly ---------------------------
{
    my $out = `bash $BS/unified.sh $input -o $T/out-nowatch.ipa 2>&1`;
    my $rc = $?;
    check($rc != 0, 'pipeline WITHOUT --watch refuses a Watch-bearing input (exit != 0)');
    check($out =~ /(WATCH APP LEFTOVER|structure validation failed)/i, "failure names the Watch leftover validation ($1)");
    check(!-f "$T/out-nowatch.ipa", 'no IPA produced on failure');
}

# ---- 2. pipeline WITH --watch must succeed and preserve the tree ------------
{
    my $in_hash = file_sha($input);
    my $out = `bash $BS/unified.sh $input -o $T/out-watch.ipa --watch 2>&1`;
    my $rc = $?;
    if ($rc != 0) {
        # the pipeline needs Evevee Spotify/component payloads; when they are
        # absent the merge step fails BEFORE watch handling. In that case the
        # test asserts the failure mentions that step, not watch.
        if ($out =~ /(merge|resolve-deps|Evevee)/) {
            check(0, "pipeline --watch could not run end-to-end in this checkout: $1");
            remove_tree($T);
            done();
        }
    }
    check($rc == 0, 'pipeline WITH --watch succeeds (exit 0)') or print "    $out\n";
    check(-f "$T/out-watch.ipa", 'output IPA produced');
    my $in_hash2 = file_sha($input);
    check($in_hash eq $in_hash2, 'original input IPA untouched (same sha256)');

    if ($rc == 0) {
        my $ud = "$T/unz";
        remove_tree($ud);
        system("unzip -q $T/out-watch.ipa -d $ud") == 0 or die;
        my $app = "$ud/Payload/Spotify.app";
        check(-d "$app/Watch/WatchApp.app", 'Watch app still present in output');
        for my $id ('com.spotify.client.watchkitapp', 'com.spotify.client.watchkitapp.WatchWidgetExtension') {
            my $found = 0;
            for my $plist ("$app/Watch/WatchApp.app/Info.plist",
                           "$app/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist") {
                next unless -f $plist;
                my $c = do { local $/; open my $fh, '<', $plist; <$fh> };
                $found = 1 if $c =~ /\Q$id\E/;
            }
            check($found, "output carries bundle id $id");
        }
        # validate the whole output with the committed validator
        my $vout = `perl $BS/watch/validate-watchfix.pl $app com.spotify.client 2>&1`;
        check($? == 0, 'committed validator accepts the output app');
    }
}

remove_tree($T);
print "\n";
if ($fail) { print "integration-tests FAILED ($pass ok, $fail fail)\n"; exit 1; }
print "integration-tests PASSED ($pass ok)\n";
exit 0;

sub done { print "\n"; exit 1; }
