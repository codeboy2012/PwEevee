# PwEevee 1.1.0-beta — Unified Package Report (Spotify 9.1.78)

**Deliverable:** `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb`
**Baseline:** SpoTi.pw/Chroma **0.50.0** + EeveeSpotify **7.0.0**, target **Spotify 9.1.78 (CFBundleVersion 917802214)** — no older baselines used anywhere in this build.

| Field | Value |
|---|---|
| Package | `com.pweevee.unified` |
| Version | 1.1.0-beta |
| Architecture | iphoneos-arm64 |
| Size | 4,071,520 bytes compressed / 31,408,606 bytes staged payload |
| SHA-256 | `67a803300906ee7dee6e205581f2472fb380cb49e631f801534e9e2b5e495550` |
| Depends | `firmware (>= 16.1), mobilesubstrate` |
| Conflicts/Replaces | `com.eevee.spotify`, `com.spotipw`, `dev.theos.orion` |
| Provides | `com.eevee.spotify (= 7.0.0)`, `com.spotipw (= 0.50.0)`, `dev.theos.orion (= 1.0.2)` |

## Contents (single copy of each — no duplicates)

```
var/jb/Library/MobileSubstrate/DynamicLibraries/
    spotifyglass.dylib        Chroma/SpoTi.pw 0.50.0, byte-identical to upstream deb
    spotifyglass.plist        filter: com.spotify.client only
    EeveeSpotify.dylib        EeveeSpotify 7.0.0, byte-identical to upstream deb
    EeveeSpotify.plist        filter: com.spotify.client only (identical filter;
                              harmless duplicate targeting, no double-injection)
    KaraokeBackgroundShader.metallib   Eevee 7.0.0 word-sync Karaoke shader
var/jb/Library/Frameworks/
    Orion.framework/          Orion **1.0.2** (arm64, MinOS 12.2) — BUNDLED.
                              Byte-identical binary to the audited Eevee 6.x component
                              AND to EeveeSpotify-6.6.8-SelfContained-v2.deb.
                              Lands exactly on EeveeSpotify.dylib's LC_RPATH
                              /var/jb/Library/Frameworks.
    EeveeSwiftProtobuf.framework/   verbatim from the Eevee 7.0.0 deb (same sha256
                              as the 6.6.8 copy)
var/jb/Library/Application Support/
    EeveeSpotify.bundle/      localized strings, EeveeLogo/github png,
                              resolveconfiguration.bnk + resolveconfiguration_9_1_76.bnk
```

Deliberately not shipped: CydiaSubstrate (Chroma swizzles at runtime, no Substrate
dependency; Eevee gets it via MobileSubstrate/ElleKit), icon PNGs (Eevee icons apply
via `CFBundleAlternateIcons` from the app root — dead path removed in the 0.22 audit),
IPA contents, any source/headers/credentials.

## EeveeSpotify 7.0.0 standalone launch crash — diagnosis

No `.ips` crash report was found anywhere on disk (searched Downloads/Documents/
Desktop, last-3-days). The diagnosis below is **static-analysis-based**; the user's
system log was never uploaded, so this remains a hypothesis with strong mechanical
evidence, not a confirmed crash-log match. Items below are what the evidence shows.

**Mechanism (evidence-backed):**

1. `EeveeSpotify.dylib` 7.0.0 carries `LC_LOAD_DYLIB @rpath/Orion.framework/Orion`
   — **non-weak**. If it cannot resolve, dyld aborts the process before
   `/usr/lib/mobilesubstrate` even finishes loading tweaks.
2. The 7.0.0 deb does **not** ship Orion (declares `Depends: dev.theos.orion`).
3. Crucially, **6.6.8 is identical in every relevant respect**: same non-weak Orion
   load command, same rpath list, byte-identical `EeveeSwiftProtobuf` (sha256
   `ab0ce0f4…d69`), same `Depends: dev.theos.orion`. Orion is therefore *not* a new
   7.0.0 regression — any working 6.6.8 setup must have had Orion present.
4. The user's injection attempt (`…9.1.78_und3fined Modified.ipa`) placed
   `EeveeSpotify.dylib`, `EeveeSwiftProtobuf.framework` and `CydiaSubstrate` inside
   `Spotify.app/` — but **no Orion.framework anywhere in the IPA**, and the modified
   main binary's `LC_RPATH` list is only `/usr/lib/swift` (4 entries) +
   `@executable_path/Frameworks` + three host-IPA developer-dir paths. None of those
   resolves a framework that was never placed. `mobilesubstrate`/ElleKit loading the
   dylib dyld-fails → launch "crash" of the whole app.

**Conclusion:** the standalone failure is a **dependency-resolution failure at dyld
load time** (missing `@rpath/Orion.framework/Orion` in the user's standalone/IPA
route), not a Spotify 9.1.78 hooking incompatibility. Fix applied in the unified
package: Orion 1.0.2 bundled at `var/jb/Library/Frameworks/Orion.framework`, which is
covered by EeveeSpotify.dylib's own `LC_RPATH /var/jb/Library/Frameworks`
(= jbroot-resolved on rootless) and by the deb's `Provides: dev.theos.orion`.
The deb-only route is self-sufficient; the deb repo no longer needs an Orion package.

**To fully confirm on device (read `var/mobile/Library/Logs/CrashReporter/…Spotify…`
or Threshold):** the abort will appear as `_dyld_start`/dlopen termination, reason
`Library not loaded: @rpath/Orion.framework/Orion` (or `(escaped) …` in
`Termination Details` under `DYLD(1)` / `amfi`). If the observed crash shows
something else (e.g. a Swift `fatalError` inside Eevee code, exception in
`EeveeSpotify` post-load), send that log — the diagnosis above would be replaced
by the real chain.

## Cross-compatibility with 9.1.78 (verified against the actual 9.1.78 binary)

- **Filters:** both plists are byte-identical binary plists targeting exactly
  `com.spotify.client` — no other process gets either dylib.
- **Chroma ↔ Eevee:** Chroma 0.50.0 ships an explicit coexistence path in-binary:
  `"Chroma isn't made to run alongside EeveeSpotify…"` +
  `spotifyglass.eevee.warned` + detection of `_TtC12EeveeSpotify27EeveeSettingsViewController`.
  It also ships dedicated lyrics-sharing: when Eevee replaces lyrics, Chroma's
  extra sources disable themselves with
  `"EeveeSpotify is replacing lyrics, so these sources stay off…"`. **Lyrics
  ownership therefore defaults to Eevee 7.0.0, with Chroma self-deferring — this is
  upstream-designed, and the unified package preserved it as-is (no source-level
  ownership patch needed).**
- **Chroma version gate:** on-disk Chroma binary contains exactly one Spotify
  version string, `9.1.78`, alongside `Chroma is made for Spotify %@ only…` — the
  binary was authored for (or validated against) 9.1.78. Target matches the
  supplied IPA (`com.spotify.client`, 9.1.78, 917802214, MinOS 16.1, arm64,
  Intents/NotificationContent/NotificationService/Widget extensions,
  MetaSmartGlassesKit + SpotifyShared frameworks, no pre-existing tweak payload).
- **Eevee:** no Spotify version string in-binary asserts incompatibility; its init
  strings log `Detected Spotify version: ` and previously logged an
  `Initialization complete for 9.1.x` path. Local hook targets exist: the 9.1.78
  main binary contains `_TtC21Settings_PlatformImpl26SettingsListViewController`
  (Eevee's settings hook target). EeveeSwiftProtobuf is verified arm64-compatible;
  Orion is verified arm64/MinOS 12.2, well below the deb's own `firmware >= 16.1`.
- **Liquid Glass overlap:** both tweaks hook player/tab-bar/now-playing surface
  classes (NowPlayingBar*, TabBar*), but Chroma claims the visual layer and has an
  explicit Eevee coexistence flow; Eevee concentrates on lyrics/CD/apps. Actual UI
  conflicts between the two binaries, if they surface at runtime, are now
  Chroma's responsibility through its own `spotifyglass.eevee.*` layer — but
  **real-device verification is required and must happen by the user** (see below).
- Known on-disk Chroma copy still targets 9.1.78; it warns-and-continues rather
  than aborting, and `spotifyglass.eevee.warned` shows the Eevee path is a
  condition, not a hard exclusion: the two can coexist by runtime design in 0.50.0.

## Runtime dependency classification

| Dependency | Dependency Classification | Why it's needed |
|---|---|---|
| iOS system frameworks (UIKit, QuartzCore, Metal, MetalKit, CoreGraphics, MediaPlayer, NaturalLanguage, Combine, SwiftUI, Security, QuartzCore, CoreFoundation, Foundation, libc++, libobjc, libSystem) | iOS/system-provided | both dylibs link them; on-device |
| Swift runtime (`libswift*` at `/usr/lib/swift`, `/usr/lib/libswift/stable`) | iOS/system-provided (rootless jailbreaks install Swift runtime) | both dylibs; rpaths contain both paths |
| `libsqlite3` | iOS/system-provided | spotiglass dylib's storage |
| `mobilesubstrate` (`/usr/lib/mobilesubstrate`, ElleKit/Substrate) | jailbreak-provided | tweak loader + hooking engine + filter dispatch |
| Orion 1.0.2 | **package-provided** (bundled at `var/jb/Library/Frameworks/Orion.framework`) | Eevee 7.0.0 non-weak `@rpath/Orion.framework/Orion` load |
| EeveeSwiftProtobuf | package-provided (bundled at `var/jb/Library/Frameworks/`) | Eevee 7.0.0 non-weak protobuf load |
| EeveeSpotify.bundle resources | package-provided | Eevee's settings/lyrics strings, and Bonk audio bank |
| KaraokeBackgroundShader.metallib | package-provided | Eevee's word-sync Karaoke |
| Chroma/SpoTi.pw runtime resources | none — it is a single dylib with no payload beyond its filter | — |
| `dev.theos.orion` deb | **not required** — provided by this package; declared via `Provides:` | — |
| decrypted Spotify 9.1.78 IPA | IPA-provided | host app the tweaks target |
| Theos, clang, ldid, SGFlagList.m, vendor/audio | build-time-only — none shipped | — |

## Validation performed (all exit-status-checked)

- ar structure: 3 members, correct order, `gzip` control member, LZMA-alone data member.
- Payload has 49 files; every required file present; exactly one copy of each
  conflicting candidate (1× each dylib, 1× Orion binary, 1× Protobuf binary, 1×
  EeveeSpotify.bundle) — **no duplicate dylibs/frameworks/bundles**.
- No CydiaSubstrate, no IPA/Payload leftovers, no build workspace, no signing
  credentials, no dead `var/jb/share/pweevee/icons` path (0.22-audit regression check).
- Filter plists each target only `com.spotify.client`; no out-of-scope bundle entries.
- Binaries are thin arm64 Mach-O (`cf fa ed fe`, cputype 0x0100000C), except
  EeveeSwiftProtobuf, which is a fat Mach-O (`ca fe ba be`) exactly as upstream
  ships it (arm64 + arm64e slices — accepted; verified present in both 6.6.8 and
  7.0.0 upstream debs in that form).
- Both tweak dylibs are byte-identical (`cmp`) to their upstream deb payloads.
- Orion binary is byte-identical to both the audited 6.x component and the
  SelfContained-v2 precedent.

## Test suite results (actually executed — bash `exit=$?` confirmed 0)

| Suite | Result | Gate |
|---|---|---|
| `PwEvevee/build-system/tests/pweevee-1.1.0-beta-tests.pl` (new, 51 checks) | **51/51 PASS** | structural deb validation for this build |
| `PwEvevee/build-system/tests/pweevee-deb-tests.pl` | **6/6 PASS** | unified deb structural |
| `PwEvevee/build-system/tests/eevee-settings-tests.pl` | **53/53 PASS** | Eevee settings wiring |
| `PwEvevee/build-system/tests/deb-format-test.pl` | **30/30 PASS** | deb container format |

### Honest limitations in this build

- **No local Theos toolchain on this Windows/MINGW64 machine**, so the deb contains
  the **upstream binaries byte-identical** — there is no PwEevee-integration source
  build inside this package. Chroma 0.50.0's own `spotifyglass.eevee.*` coexistence
  + `_TtC12EeveeSpotify27EeveeSettingsViewController` handoff is the unified binding
  layer this build ships. A source-level SGEevee/SGEeveeSpotifyPage unified settings
  page (from the 0.22 work in Spotipw/tweak) would require a Theos build against the
  0.50.0 sources and should be added later — it is not in 1.1.0-beta.
- **No device crash log was provided**, so the Orion dependency-resolution failure
  is a static-analysis diagnosis (mechanism verified in both binaries; pending
  `.ips` confirmation on-device).
- **Device testing was NOT performed from this environment** — the 10-area on-device
  checklist in the task description must be run by the user against real hardware;
  do not treat this package as device-validated.

## Installation / injection instructions

### Route A — jailbroken device (rootless, e.g. Dopamine/roothide; recommended)

1. Have the decrypted Spotify 9.1.78 IPA installed (`com.spotify.client`, 9.1.78, build 917802214). Do not use 9.1.76/9.1.84.
2. Remove any standalone `EeveeSpotify` / `SpoTi.pw`/`Chroma` / `dev.theos.orion` package first — the deb declares Conflicts, so the package manager will prompt.
3. `dpkg -i PwEevee_1.1.0-beta_iphoneos-arm64.deb` (or filza open, or repo install).
4. `uicache -a && killall SpringBoard` or `ldrestart` once, then launch Spotify 9.1.78.
5. First-launch checklist: no dyld abort, Chroma settings header appears, Eevee's gear page appears, lyrics work, Karaoke works.

### Route B — side-load IPA injection (non-jailbroken / sideloaded IPA)

Not recommended. The route that produced the user's Modified.ipa is missing
Orion; if you must use this route, copy `Orion.framework` (from this deb's
`var/jb/Library/Frameworks/`) into `Spotify.app/Frameworks/` of the *modified*
IPA — in the exact placement the failed Modified.ipa neglected — plus
`EeveeSwiftProtobuf.framework` and `EeveeSpotify.dylib` (already in yours), and
also `EeveeSpotify.bundle` at the app root. Verify with `otool -L` equivalent
(that the load chain resolves). Jailbreak Route A remains supported; Route B is
not re-validated as part of this task.

### Rollback

`dpkg -r com.pweevee.unified` restores clean Spotify; `v1.0.2` is unaffected by
this build and remains not overwritten.

## Known issues / next steps

1. Crash-diagnosis completion needs the device `.ips` crash report from the
   EeveeSpotify-7.0.0-standalone test (user-provided; not obtainable from here).
2. No `SGEeveeSpotifyPage` source-level unified settings integration in this build
   (requires a Theos rebuild against Chroma 0.50.0 sources on a Mac/Linux CI).
3. Liquid Glass cross-tweak conflicts must be checked on device:
   tab bar, now-playing bar, player, lyrics, navigation, menus, headers,
   album/playlist/artist pages, settings UI, backgrounds, artwork, glassness.
   Chroma ships a runtime coexistence branch (`spotifyglass.eevee.warned` +
   `EeveeSpotify isn't supported` handlers); if a real UI conflict appears,
   file it under a new issue with the device log.
4. `extract-flags.pl` walker bug (returns 0 typed flags; stub-resolution TODO)
   is still open in `Spotipw/scripts/extract-flags.pl`; only relevant if the
   SGFlagList.m must be regenerated for 9.1.78 (CI gate).

## Changed files

- `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb` (new deliverable)
- `docs/PWEEVEE-1.1.0-BETA.md` (this report)
- `PwEvevee/build-system/tests/pweevee-1.1.0-beta-tests.pl` (new test suite)
