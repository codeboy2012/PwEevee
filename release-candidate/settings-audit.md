# PwEevee v3.1.0 RC — settings audit

## Method and honesty statement

Everything below comes from **static inspection of the actual sources** plus the
test suites that ran this session. **No runtime behavior was observed on a device**
(no authorized iPhone/simulator was reachable), so every observation of the form
"applies at once / persists across restart" is what the source and tests assert,
marked accordingly. "Observed result" = `test-suite check passed at exit-code
level`, never a device run.

- Generator: [settings-inventory.pl](settings-inventory.pl) (this workspace) ran
  against `Spotipw/tweak/Sources` (exit 0). Full row-by-row output:
  [settings-inventory.tsv](settings-inventory.tsv) (247 row call-sites + 78 registry keys).
- Nothing in this audit invents a setting that is not present in the sources.

## 1. Persistence mechanism (single, central)

`Spotipw/tweak/Sources/Core/SGPrefs.m` owns all persistence:

| Function | Purpose | Storage |
|---|---|---|
| `SGFlag(key, fallback)` + `SGEnabled` / `SGHidden` | read of the three switch row kinds | `NSUserDefaults.standardUserDefaults.boolForKey` — the app's own defaults, so values persist in the Spotify bundle domain across restarts |
| `SGSetEnabled(key, on)` | `setBool:forKey:` switch writes | same |
| `SGInt` / `SGSetInt` | slider / choice indices | `integerForKey` |
| `SGFlagOverride` / `SGSetFlagOverride` | `spotifyglass.flag.<name>` prefixed overrides of Spotify remote-config flags | `objectForKey` |
| `SGMigrateKey(from,to)` | copies old key values across, removes the old key, *skips if the target already exists* | migration-safe |
| `SGRestartSpotify` | `synchronize` + `exit(0)` after 0.3 s | the only restart path |
| `SGKeyStock` (`spotifyglass.stock`) | global fallback kill switch (`SGFlag` consults `![store boolForKey:SGKeyStock]`) | master off |

Key strings are the `SGKey*` registry: **78 defines across 23 headers** (generated;
see TSV `KEY` rows). Defaults follow the row constructors in
`Spotipw/tweak/Sources/Settings/SGModPage.m`:
`SGSwitchRow` default **on**, `SGHideRow` / `SGOptionRow` **off** (added features
start off — the mod never silently turns something on), `SGUnstableRow` off with a
confirmation dialog, `SGFlagRow` **force-on**, `SGKillRow` **force-off** of a flag
Spotify ships enabled.

## 2. Inventory counts (generated, exit 0)

```
TOTAL  rows=247
  SGActionRow=11   SGChoiceRow=7   SGFlagRow=55   SGHideRow=70   SGKillRow=14
  SGLinkRow=7      SGOptionRow=27  SGPageRow=23   SGSliderRow=5  SGStatActionRow=7
  SGStatRow=6      SGSwitchRow=10  SGUnstableRow=2  SGWarningRow=3
```

Per-file distribution (top): `Native/Player/PlayerSettings.m` 29,
`Native/Artist/ArtistSettings.m` 23, `Native/Home/HomeSettings.m` 22,
`Settings/SGModPage.m` 21, `Shared/Flags/FlagPages.m` 19,
`App/Eevee/SGEevee.x` 19, `Shared/Privacy/PrivacySettings.m` 17,
`Native/Playlist/PlaylistSettings.m` 12, `Native/Album/AlbumSettings.m` 10,
`App/About/AboutSettings.m` 10 … full table in the TSV.

## 3. Navigation and entry points

`App/Pages.m` composes the page tree: Appearance (with the **iOS-26 gated
Redesign row** — below iOS 26 the row degrades to a status row with an honest
"Needs iOS 26" explanation, verified in source `Pages.m:47-64`), Navbar (which
swaps its page from `SGRedesignedUIStored()`), Lyrics (with display-section rows
enabled only in the redesign), Player (page rows for Blocked artists, Gestures,
Lyrics, Now playing bar/Queue & devices, Lock screen widget), plus per-module
pages. Restart notes (`SGRestartNote = "Changes apply after you restart
Spotify."`) are applied to the pages whose hooks read at launch; the Redesign
switch shows its own restart dialog via `offerRestart` (`Pages.m:15-24`).

## 4. Feature gating and exclusives

- The `enabled` block on `SGModRow` (declared in `SGModPage.h`) greys a dependent
  row out until its blocker row is turned off — the mechanism tested by
  `pweevee-premium-exclusivity-tests.pl` (**47 checks passed this session**),
  which asserts the mutual exclusivity of the Premium-spoof rows (e.g.
  `SGKeyFakePremium`/`spotifyglass.adblock.premium` vs the others).
- `visible` blocks fade out context-dependent rows; `choiceNotes` / `choiceFooter`
  explain choices; every 7 `SGChoiceRow` callsite was read; fallbacks are either
  `0` (Translation language) or dedicated `SG…Default` constants (Home) / enum
  defaults (Haptics `SGMusicFollowsEverything`, LiveActivity
  `SGLiveActivityLyrics`, Meanings `SGLyricsMeaningsOff`). No out-of-range
  fallback was found statically; runtime fallback-out-of-range behavior is
  **unverified (needs device)**.
- Sliders store through `set` as the thumb moves ("applying as it changes"), range
  and step declared per row (4 declared +1 header-defined slider row).

## 5. Update checker (About → Updates)

Static reading of `App/About/Update.m` + `UpdatePage.m`:

- Endpoint: `https://api.github.com/repos/codeboy2012/PwEevee/releases?per_page=20`
  (`Update.m:13`) — the official PwEevee repo, pinned by test
  (`pweevee-rebrand-tests.pl` includes the endpoint-pinning checks; **30 checks passed**).
- Failure handling: 10-second request and 10-second resource timeouts
  (`Update.m:184-187`); HTTP 403/429 → cached message "asked too often";
  other errors → "check failed" (`Update.m:212-219`); the last successful check is
  stored and re-drawn, and the page re-checks only if the six-hour window
  (`Update.m` header comment) has elapsed — so offline use shows the cached page.
- Version comparison and changelog rendering live in Update.m/UpdatePage.m; their
  runtime correctness on device is **NOT TESTED (no device)**.

## 6. Alternate app icons

- The build pipeline (`build-system/package/patch-alternate-icon.pl`) registers
  `CFBundleIcons.CFBundleAlternateIcons["PwEevee"]` with
  `CFBundleIconFiles=["pweevee-icon"]`, `UIPrerenderedIcon`, and mirrors into
  `CFBundleIcons~ipad` **only when the host declares that key** (verified in the
  RC build log: "mirrored into CFBundleIcons~ipad (host declares it)").
- The in-app icon picker reads the payload's declared alternates
  (`eevee-settings-tests.pl` check manifest, 70 checks passed this session).
- 28 alternate-icon suite checks passed (idempotent double-patch, negatives,
  validators); the RC IPA's own `Info.plist` contains the registration (grep
  verified during Phase 2).
- Runtime icon swap (`setAlternateIconName:` on a device) — **NOT TESTED (no device)**.

## 7. Eevee integration settings

`App/Eevee/SGEevee.x` (19 row sites, read): the payload's standalone row and gear
button are hidden/re-filtered rather than deleted; its keys are left alone where
the payload drives them; its lyric rewriter is stood down in favour of the shared
lyrics chain. **70/70 `eevee-settings-tests.pl` checks passed.** The resource
bundle (`EeveeSpotify.bundle`, incl. 26 `.lproj` Localizable.strings files from
upstream) is staged and pinned by hash (component-manifest-test 389 checks).

## 8. Localization

- PwEevee's own settings UI ships **English-only strings hard-coded in the
  sources**; no `.lproj` exists under `Spotipw/` (checked with find). This is a
  documented gap, not a defect.
- Upstream Eevee bundle localizations are untouched as staged.

## 9. Accessibility

Static evidence (not run on a device): `SGGlowSwitch` sets
`isAccessibilityElement = YES` (`SGGlowSwitch.m:57`), the page gives each switch
`accessibilityLabel = row.title` (`SGModPage.m:604`), sliders label
(`SGModPage.m:368`), the ⓘ info button labels "About this switch"
(`SGModPage.m:655`), and pure-decoration text opts out
(`_title/_subtitle/_value.isAccessibilityElement = NO`, `SGModPage.m:336-343`).

## 10. Error handling and recovery

`SGWarningRow` (3 sites) renders red rows that explain recovery actions on tap;
`SGStatRow` reads live status. In the build system side, every packaging failure
is a hard, named failure (validator suite evidence). Runtime recovery from a
failed settings write is the OS's `NSUserDefaults` contract — untested here.

## 11. Defects found

**None new and confirmed in this audit.** The three known items remain tracked in
`docs/comparison/roadmap.md`: LiveContainer icon crash (upstream), iOS-18
downloads (platform limitation), CydiaSubstrate pin reconciliation (release
decision). Because no new defect was confirmed, no new regression test was added
this phase; the existing 250+ settings-relevant checks all passed.

## 12. Runtime caveats (explicit)

Items 5–10 describe what the sources assert. Actual on-device behavior of the
update check, icon swap, exclusivity greying, slider persistence and restart flow
is **NOT TESTED — DEVICE UNAVAILABLE**, and the `device-compatibility.md`
report carries the formal matrix.
