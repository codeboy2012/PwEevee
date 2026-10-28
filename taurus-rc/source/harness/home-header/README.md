# Home header harness

Exercises the real HomeHeader.x hooks with a header that receives its size after its controller laid out.
It asserts that the title recovers from zero width, makes room for a late avatar, follows a width change,
and stays visible with Appearance → Home page off. With Home page on, it checks the scroll fade and return.
The fixture supplies the Home style preference and unrelated Home/Navbar functions.

    THEOS=/path/to/theos sh harness/home-header/build.sh
    xcrun simctl install booted harness/home-header/build/HomeHeaderHarness.app
    xcrun simctl launch --terminate-running-process booted com.pweevee.homeheaderharness home-off
    xcrun simctl launch --terminate-running-process booted com.pweevee.homeheaderharness

Wait for the `[header-test] PASS` log after each launch. `HEADER_SOURCE=/path/to/HomeHeader.x` and
`OUT=/temporary/build` let the same scenario exercise an older hook without changing the checkout.
This mocks Spotify's layout sequence; it does not run Spotify's actual element framework.
