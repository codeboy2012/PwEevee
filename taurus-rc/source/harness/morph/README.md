# Morph harness

`PlayerMorph.x` run for real against a mock of Spotify's `SPTBarOverlayPresentationTransition`: the
mock sets the player's frame, its alpha and the bar stand-in from `-setProgress:` the way 9.1.78 does
(0x109815464), driven by a display link on a spring, and makes the bar's stand-in the way Spotify
does (a snapshot view opening, a `renderInContext:` image closing). The bar, the player and the cover
are plain views standing in for Spotify's; the morph's inputs from `NowPlayingBar.x` and
`PlayerArtwork.x` are stubbed in `main.m`.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/MorphHarness.app
    xcrun simctl launch booted com.vojta.morphharness          # opens, closes, repeats

Held at one progress, for a screenshot (the positions are logged as `MORPH` lines):

    SIMCTL_CHILD_MORPH_T=0.3 xcrun simctl launch --console-pty booted com.vojta.morphharness
    xcrun simctl io booted screenshot shot.png

A recording shows the move: `xcrun simctl io booted recordVideo -f run.mp4`, then
`ffmpeg -ss T -t 0.5 -i run.mp4 -vf "fps=24,scale=160:-1,tile=8x1" -frames:v 1 strip.png`.

What it does not cover: Spotify's real player and list, the tab bar's stand-in, the bar's glass on the
closing stand-in (`BarTransition.x`), a drag, and the field's colour (the sheet is black here).
