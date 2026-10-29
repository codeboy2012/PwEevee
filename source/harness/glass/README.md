# Glass harness

Spotify's round header button mocked as what the trees show it to be -- a 48x48 control whose glyph is a
subview of its own (`trees/clean/player/01.txt:103`) -- with the real `SGRGlassInside` behind it, over a
colour field, so what the glass does to the glyph can be looked at on the Mac.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/GlassHarness.app
    xcrun simctl launch booted com.vojta.glassharness
    xcrun simctl io booted screenshot shot.png

Four glyphs in three rows, the same button and the same shape each time, differing only in how the shape is
put behind the button:

| row | how |
|---|---|
| `as shipped` | first in the button's subviews, what `SGRGlassInside` does now |
| `by depth` | added last and pushed back with `zPosition = -1`, what it did before issue #39 |
| `outside` | a sibling of the button, behind it in its superview |

**What it does not cover: the bug it was written for.** Issue #39 is a glyph that comes out as a soft ghost
seen through the glass with nothing crisp over it, which is glass taking the glyph into its backdrop. The
simulator's glass does not refract, so all three rows look right here and only a phone tells them apart. The
harness is worth keeping for what it does prove: that the shape still lands centred and behind the glyph, in
each arrangement, so a change to the ordering can be seen not to have moved anything.
