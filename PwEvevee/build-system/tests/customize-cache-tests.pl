#!/usr/bin/env perl
# Cold-cache customize tests: the config re-fetch may only be answered from a body the mod has
# already rewritten. With a cold cache there is nothing to replay, and both the old task cancel and
# the zero-byte 200 left Spotify without a config, so the fetch has to go out and be rewritten on
# arrival. A zero-length cache counts as cold: it is a failed rewrite, not a config.
#
# These are source-wiring checks against the tree the shipped spotifyglass.dylib is built from
# (PwEvevee/components/spotipw/manifest.json -> source_tree), not Spotipw/ which is the older
# working tree. Runtime behaviour needs the network-tasks harness on a Mac.
#
#   perl PwEvevee/build-system/tests/customize-cache-tests.pl
use strict;
use warnings;
use File::Basename qw(dirname);

my $ROOT = dirname($0) . '/../../..';
my $ADNET    = "$ROOT/source/tweak/Sources/Shared/AdBlock/AdNetwork.x";
my $HARNESS  = "$ROOT/source/harness/network-tasks/main.m";
my $MANIFEST = "$ROOT/PwEvevee/components/spotipw/manifest.json";

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }
sub slurp { local $/; open my $f, '<', $_[0] or return undef; return <$f>; }

# A failed match in list context yields the empty list, which would shift the message into the
# condition and make the check pass. Evaluate every pattern in scalar context, explicitly.
sub matches { my ($text, $re) = @_; return (defined $text && $text =~ $re) ? 1 : 0; }
sub lacks   { my ($text, $re) = @_; return (defined $text && $text !~ $re) ? 1 : 0; }

my ($adnet, $harness, $manifest) = (slurp($ADNET), slurp($HARNESS), slurp($MANIFEST));
ok(defined $adnet && defined $harness, "the canonical AdNetwork source and its harness are readable");
ok(defined $manifest, "the component manifest is readable");
if (!defined $adnet || !defined $harness) {
    printf STDERR "customize-cache-tests: 0 passed, %d FAILED\n", scalar @failures;
    printf STDERR "  - %s\n", $_ for @failures;
    exit 1;
}

# ---------- 0. the fix lands in the tree the shipped dylib is built from ----------
ok(matches($manifest, qr/"source_tree"\s*:\s*"source\b/),
   "the component manifest names source/ as the spotifyglass source tree");

# ---------- 1. customize is out of the unconditional refetch list ----------
my ($isrefetch) = $adnet =~ /static BOOL isRefetch\(NSString \*path\) \{(.*?)\n\}/s;
ok(defined $isrefetch, "isRefetch is found");
ok(matches($isrefetch, qr/signup\/public/) && matches($isrefetch, qr/pses\/screenconfig/),
   "isRefetch still carries the endpoints it was written for");
ok(lacks($isrefetch, qr/isCustomize/),
   "isRefetch no longer folds customize in, so a cold cache is not blocked there");

# ---------- 2. the replay gate ----------
ok(matches($adnet, qr/static BOOL canReplayCustomize\(NSString \*path\)/),
   "the customize replay gate exists");
ok(matches($adnet, qr/if \(!isCustomize\(path\)\) return NO;/),
   "the gate never answers a non-customize request");
ok(matches($adnet, qr/static NSData \*replayable\(void\)/),
   "one accessor decides what body may be replayed");
my ($replayable) = $adnet =~ /static NSData \*replayable\(void\) \{(.*?)\n\}/s;
ok(defined $replayable, "the replay accessor is found");
ok(matches($replayable, qr/cachedCustomize\.length > 0 \? cachedCustomize : nil/),
   "replayable returns a body only when it is non-empty, so a failed rewrite is not replayed");
ok(matches($adnet, qr/return replayable\(\) != nil;/),
   "the gate is that accessor and nothing else");

# ---------- 3. classification ----------
my ($classify) = $adnet =~ /static SGNet classify\(NSURL \*url\) \{(.*?)\n\}/s;
ok(defined $classify, "classify is found");
ok(matches($classify, qr/elapsed\(\) > 30 && canReplayCustomize\(path\)\) return SGNetBlock;/),
   "classify blocks a customize only when a body can actually be replayed");
ok(matches($classify, qr/\(isBootstrap\(path\) \|\| isCustomize\(path\)\)\) return SGNetPatch;/),
   "classify still rewrites customize on arrival");
ok(matches($classify, qr/isRefetch\(path\)\) return SGNetBlock;\s*if \(premium && elapsed\(\) > 30 && canReplayCustomize/),
   "the gated customize rule sits after the ordinary refetch rule, so only customize is relaxed");

# ---------- 4. the task-level cancel uses the same gate ----------
my ($resume) = $adnet =~ /%hook NSURLSessionTask\s*- \(void\)resume \{(.*?)%end/s;
ok(defined $resume, "the NSURLSessionTask resume hook is found");
ok(matches($resume, qr/canReplayCustomize\(path\)/),
   "the task-level cancel asks the same replay gate before cancelling a customize");
ok(lacks($resume, qr/isCustomize\(path\)/),
   "the task-level cancel no longer kills every customize after the login window");
ok(matches($resume, qr/has\(path, \@"deletetoken"\)/),
   "the logout endpoints are still cancelled at the task");

# ---------- 5. the blocked reply still serves the rewritten body ----------
my ($blocked) = $adnet =~ /static NSData \*blockedReply\(NSString \*path\) \{(.*?)\n\}/s;
ok(defined $blocked, "blockedReply is found");
ok(matches($blocked, qr/if \(isCustomize\(path\)\) \{\s*NSData \*replay = replayable\(\);/),
   "a blocked customize is still answered with the rewritten body");
ok(matches($blocked, qr/if \(replay\) return replay;/),
   "the blocked reply reuses exactly the body the accessor validated");
ok(lacks($blocked, qr/isCustomize\(path\)[^;]*\n\s*return \[NSData data\]/),
   "blockedReply has no customize path that falls straight through to an empty body");

# ---------- 6. the 304 replay validates the body it delivers ----------
my ($replayfor) = $adnet =~ /static NSHTTPURLResponse \*replayFor\(NSURLSessionTask \*task, NSURLResponse \*response, NSData \*\*body\) \{(.*?)\n\}/s;
ok(defined $replayfor, "replayFor is found");
ok(matches($replayfor, qr/NSData \*replay = replayable\(\);/),
   "the 304 path asks the accessor rather than nil-checking the cache");
ok(lacks($replayfor, qr/!cached\(\)/),
   "the 304 path no longer treats an empty cached body as a replay candidate");
ok(matches($replayfor, qr/if \(body\) \*body = replay;/),
   "replayFor hands the validated body to the caller, so the hook cannot deliver another one");
ok(lacks($adnet, qr/cached\(\)/),
   "no bare cache getter survives to hand back an empty body");
ok(matches($adnet, qr/\(isCustomize\(path\) \? replayable\(\) : nil\) \?: \[NSData data\]/),
   "the bodiless-completion fallback prefers a real config over an empty body");

# ---------- 6b. a 304 with nothing to replay completes untouched ----------
ok(matches($adnet, qr/kNotModifiedKey/),
   "a per-task mark records a customize 304 that had nothing to replay");
ok(matches($replayfor, qr/if \(!replay\) \{\s*objc_setAssociatedObject\(task, &kNotModifiedKey, \@YES/),
   "replayFor marks that task instead of answering it");
ok(matches($adnet, qr/if \(isCustomize\(path\) && objc_getAssociatedObject\(task, &kNotModifiedKey\)\) \{\s*finish\(error\);\s*return;\s*\}/),
   "complete finishes a marked 304 without inventing a body for the delegate");
ok(matches($adnet, qr/SGLog\(\@"replayed %@, %lu bytes (?:over 304|from cache)"/),
   "both replay paths log the body they actually delivered");

# ---------- 7. the EeveeSpotify layer closes the same hole ----------
my $EeVEE_PATCH = "$ROOT/PwEvevee/components/eveespotify-patches/cold-cache-gate.patch";
my $eevee = slurp($EeVEE_PATCH);
ok(defined $eevee, "the EeveeSpotify patch is readable");
if (defined $eevee) {
    ok(matches($eevee, qr/static var replayableCustomizeData: Data\?/),
       "EeveeSpotify has one accessor for the body a replay may deliver");
    ok(matches($eevee, qr/static var hasReplayableCustomize: Bool \{ replayableCustomizeData != nil \}/),
       "its gate is that accessor");
    ok(matches($eevee, qr/if shouldHandleCustomize\(url\), let cached = replayableCustomizeData/),
       "its blocked reply reads the same two layers the gate accepted");
    my $replays = () = $eevee =~ /if let cached = SpotifyResponsePatcher\.replayableCustomizeData,/g;
    ok($replays == 2,
       "both of its 304 handlers replay only a non-empty body (found $replays)");
    ok(lacks($eevee, qr/cachedCustomizeData\s*\?\?\s*UserDefaults/),
       "no EeveeSpotify path falls back to an unchecked persisted copy");
    ok(matches($eevee, qr/&& SpotifyResponsePatcher\.hasReplayableCustomize/),
       "its session-protection cancel still asks the gate");
    ok(matches($eevee, qr/static func forwardsUntouched\(statusCode: Int, replay: Data\?\) -> Bool/),
       "the policy decides when a bodiless 304 must reach Spotify untouched");
    ok(matches($eevee, qr/_customizePassThroughTasks/),
       "it tracks the customize tasks whose 304 it left alone");
    my $consumes = () = $eevee =~ /consumeCustomizePassThrough\(task\.taskIdentifier\)/g;
    ok($consumes == 2,
       "both delegate hooks forward a passed-through 304's completion instead of a body (found $consumes)");
    my $marks = () = $eevee =~ /markCustomizePassedThrough\(task\.taskIdentifier\)/g;
    ok($marks == 2, "both 304 handlers mark the task when there is nothing to replay (found $marks)");
    ok(matches($eevee, qr/Customize 304 passed through untouched/),
       "the pass-through is visible in the device log");
    ok(matches($eevee, qr/\QReplayed customize over 304 (\(cached.count) bytes)\E/),
       "a warm replay logs the body it delivered");
}

# ---------- 8. the macOS harness covers the new behaviour ----------
ok(matches($harness, qr/A cold-cache customize still goes out/),
   "the harness asserts a cold-cache customize is not cancelled");
ok(matches($harness, qr/Premium refetch protection still cancels once a body can be replayed/),
   "the harness keeps asserting the warm-cache cancel");
ok(lacks($harness, qr/Premium refetch protection still cancels after login/),
   "the harness no longer asserts the unconditional cold-cache cancel");
ok(matches($harness, qr/Cold-cache config is rewritten on arrival, not answered empty/),
   "the harness asserts the cold-cache body is rewritten rather than answered empty");
ok(matches($harness, qr/A failed cold-cache customize keeps its error/),
   "the harness asserts a genuine failure is not turned into a reply");
ok(matches($harness, qr/An unrewritable config passes through rather than empty/),
   "the harness asserts an unrewritable body passes through intact");
ok(matches($harness, qr/A 304 with no replay completes untouched rather than with an empty body/),
   "the harness asserts a bodiless 304 is not completed with an invented body");
ok(matches($harness, qr/A passed-through 304 keeps its own error/),
   "the harness asserts a passed-through 304 still propagates its error");

if (@failures) {
    printf STDERR "customize-cache-tests: %d passed, %d FAILED\n", $pass, scalar(@failures);
    printf STDERR "  - %s\n", $_ for @failures;
    exit 1;
}
printf "customize-cache-tests: %d passed, 0 failed\n", $pass;
exit 0;
