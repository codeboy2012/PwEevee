# Artist harness

Spotify's artist page mocked under its own class names and accessibility identifiers (from
`trees/clean/artist/01.txt` and `05.txt`, recorded 2026-09-16), so `Redesigned/Artist/` can be laid out and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/ArtistHarness.app
    xcrun simctl launch booted com.vojta.artistharness            # at rest
    xcrun simctl launch booted com.vojta.artistharness collapsed  # the header scrolled into its 100pt bar

The Music list is a real self-sizing collection view holding the sections in the order the tree has them,
the two video sections included, so `ArtistSections.x` drops them the way it does on the phone: the shelf
first, then its heading and spacer once the list lays out again. At 2 s the log lists every cell's height.

What it does not cover: the repaint hook (so the mock's cells are left unpainted), the real z-order of the
pinned header bar against the list, and the element framework's own sizing.
