# Network task regression harness

Runs the production AdNetwork hooks and safe request accessors in the iOS simulator.
The transport and Premium/feed body transforms are fixtures; no network requests are made.

    THEOS=/path/to/theos sh harness/network-tasks/build.sh          # build + run on the booted device
    sh harness/network-tasks/sim-app.sh <simulator-udid>             # build, install as an app, launch

`build.sh --no-run` stops after compiling. `sim-app.sh` wraps the same binary in a minimal
`NetworkTasks.app` (`com.pweevee.networktasks`), installs it on a chosen simulator and
launches it with its console attached, so a run can be shown to come from an installed
bundle rather than a bare `simctl spawn` process. It is an arm64-simulator binary built
from the production hooks; the device IPA's arm64 dylibs are not simulator code and are
never installed here.

Checks AVFoundation aggregate and single-asset tasks whose request getters throw, custom
unsupported task subclasses, original-request fallback, media resume, the login grace period,
Premium refetch cancellation once a body is cached, cold-cache config passthrough and rewrite on arrival, blocked ad replies, buffered config transforms and 304 replay. A 304 is answered with a 200 only when a non-empty
rewritten body exists. Over an empty or absent cache it passes through untouched, and its
*completion* is forwarded without a synthetic body too — the harness counts the delegate's
`didReceiveData` calls, so completing with `Data()` (the old behaviour) fails even though
zero bytes were "delivered". A genuine transport error on that path keeps its error. Two customize tasks held at the
same time keep separate per-task buffers: completing the first delivers only its own bytes,
and the second still has its own body (the fixture makes the first unrewritable so the two
are distinguishable).
AVFoundation tasks must pass through without invoking either unsupported request getter.

Set `ADNETWORK_SOURCE=/path/to/AdNetwork.x` to compare an earlier version of the hooks.
