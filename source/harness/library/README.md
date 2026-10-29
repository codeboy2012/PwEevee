# Library harness

Spotify's Your Library page mocked under its own class names and accessibility identifiers (from
`trees/clean/library/03.txt`, recorded 2026-09-16), so `Redesigned/Library/LibraryHeader.x` can be laid out
and looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/LibraryHarness.app
    xcrun simctl launch <udid> com.vojta.libraryharness            # first look
    xcrun simctl launch <udid> com.vojta.libraryharness back       # then the pass the page gets coming back from a playlist
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `LibraryHeader.x` from the checkout it sits in and
links it with the real `Core/` and `Redesigned/Kit/` sources; `SRC=<other tweak/Sources> ./build.sh` builds
an older tree instead, to compare. `stubs.m` stands in for the hook files the harness does not compile.

Each report asserts that the Library title is visible and does not overlap any visible header control,
and that the filter chips and list inset stay intact. The harness uses the scene lifecycle on newer iOS.

It plays issue #21. The page comes up with the header's control row holding Search alone. At 0.8 s the
header's model lands: Recents and Create show, and the page lays out in the same turn. The mock of
`AutoLayoutStackView` (the real one's ivars are `observationsDictionary` and `needsCoalescedLayoutUpdate`)
places what changed on the next turn of the main queue, in a pass of its own container that reaches
neither the header nor the page. So at the page's pass a button just shown still stands at the row's
origin, where 03.txt has the hidden Recents. Before the fix the moves worked out on that pass stayed:
Search ends up next to the title, left of Recents, and Create goes off the screen. A page pass later (`back`)
put Search on top of Recents, which the old code never placed. After the fix the row's own pass places
everything again.

Launch words: `back` adds the page pass at 2.4 s. `steady` builds the header with the model already in it.
`nocreate` leaves Create out of the model, and `norecents` leaves Recents out (the account the tree was
recorded on). Each moment is logged with where every control landed in the header:

`plain-avatar` uses a profile button outside `AdaptiveFaceContainer`, leaving it at Spotify's leading
edge. It catches a title drawn over the button that opens the side drawer when its container changes.

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "redesign library"'

What it does not cover: the real stack's constraints and when its coalesced update actually runs, the
element framework behind the avatar, the list's rows (`LibraryRows.x`) and the folder page.
