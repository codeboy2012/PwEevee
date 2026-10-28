# Network task regression harness

Runs the production AdNetwork hooks and safe request accessors in the iOS simulator.
The transport and Premium/feed body transforms are fixtures; no network requests are made.

    THEOS=/path/to/theos sh harness/network-tasks/build.sh

Checks AVFoundation aggregate and single-asset tasks whose request getters throw, custom
unsupported task subclasses, original-request fallback, media resume, the login grace period,
Premium refetch cancellation, blocked ad replies, buffered config transforms and cached 304 replay.
AVFoundation tasks must pass through without invoking either unsupported request getter.

Set `ADNETWORK_SOURCE=/path/to/AdNetwork.x` to compare an earlier version of the hooks.
