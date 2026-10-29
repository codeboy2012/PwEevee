# Home shelf headings harness

Runs the real HomeHeadings.x hook on the recorded SectionHeadingHome button structure. It checks
recently played and Jump back in headings, localized names, reuse, accessibility and the button action.
It also exercises HomeTopPicks.x's frame calculation with Top picks enabled to check that Home page
off retains Spotify's shelf heading and order, while Home page on keeps the promoted shelf layout.
Home style and settings-row functions are fixtures; the card feed and Spotify's element framework are mocked.

    THEOS=/path/to/theos sh harness/home-headings/build.sh
    xcrun simctl install booted harness/home-headings/build/HomeHeadingsHarness.app
    xcrun simctl launch --terminate-running-process booted com.pweevee.homeheadingsharness home-off
    xcrun simctl launch --terminate-running-process booted com.pweevee.homeheadingsharness

Wait for both `[headings-test] PASS` lines after each launch. `top-only` tests the frame calculation alone.
Add `top-off` to either launch to also check the original first-shelf card size with Top picks disabled.
