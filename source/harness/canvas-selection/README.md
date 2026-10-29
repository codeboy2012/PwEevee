# Canvas selection regression harness

Runs the actual lock-screen style model, artwork source walker, motion follower and player-state
publisher in the iOS simulator. The network is replaced with an NSURLProtocol fixture; no real
Spotify requests or account credentials are used.

    THEOS=/path/to/theos sh harness/canvas-selection/build.sh

The first executable checks the ordered Canvas fallback, its track-local lifetime, Canvas retries on
the next track, every single-view choice, explicit star cycling, disabled views and Lyrics fallback.
It also runs queued defaults observers with star cycling off, counts actual defaults setter calls,
and verifies that refreshes settle without rewriting preferences or clearing the track's fallback.
Repeated Lyrics selections must keep artist-name lyrics suppressed without restoring and suppressing
them again; leaving Lyrics or turning exclusivity off must restore them.
The second checks late
request headers, request sharing, timeout recovery, same-track source changes, background defaults
writes, Canvas metadata arriving after a skip, updated Canvas URLs and stale results after rapid skips.
Position-only state updates must still avoid notifying observers.

`PLAYER_STATE_SOURCE=/path/to/PlayerState.x` runs the same scenarios with a different publisher.
`LOCK_SCREEN_STYLE_SOURCE=/path/to/LockScreenStyle.m` substitutes the style model for regression comparisons.
The pre-fix publisher fails when Canvas metadata arrives after a skip. Two earlier reproductions also
showed the old star-view migration adding disabled styles and a missed lookup persisting Off.

This tests selection and callback ordering. Real lock-screen video presentation still needs an iOS 26+
phone with tracks that have Canvas available.

The lock-screen lyrics switch is checked independently: disabled Lyrics is skipped during star
cycling, direct selection and Canvas fallback, all artwork styles remain available, artist-name
lyrics can still run, and the original hierarchy is retained when Lyrics is enabled again.
