# PwEevee v2.2.0-pre — Unified Build Validation Report

Date: 2026-10-23. Branch: `feat/premium-spoof-unified` (merged into `main` at the release commit).

## Artifacts

| Artifact | Path | Size | SHA-256 |
|---|---|---|---|
| Unified IPA | `PwEevee-0.22.0-alpha.2-unified-Spotify-9.1.90.ipa` | 300,634,848 B (287 MB) | `a76b469a8291d6650026ef1355b77ead37efcc9250517aaf057a6e6b1dab3996` |
| Unified deb (rootless jailbreak) | `PwEevee_0.22.0-alpha.2_iphoneos-arm.deb` | 611,900 B | `02448bf101b9ad887982e6c9c5620c811577287e5aa89ce476222854ccb5153c` |
| SpotifyGlass rebrand dylib (`spotifyglass.dylib`) | inside the deb/IPA | 1,816,144 B | `e633f9244c239f40598d0ae4bb4c35cab86fed40d77fa2168f7c489947759046` |

## Component versions and provenance

| Component | Version | Provenance |
|---|---|---|
| SpoTi.pw (spotifyglass) | 0.22.0-alpha.2 | **Rebuilt from source** — GitHub Actions CI run 39952230740 (macOS 15, Theos, iPhoneOS SDK) at commit `94962d9`, with the `SG_FLAG_LIST` secret. The dylib shipped here is exactly the one inside that CI deb. |
| EeveeSpotify | 6.6.8-selfcontained.1 | Upstream binary release (`EeveeSpotify-6.6.8-SelfContained-v2.deb`, sha256 `58efafad…cd6d2`), pinned in `Evevee Spotify/component/manifest.json`; verified byte-identical inside the IPA. |
| Orion | 1.0.2 | Pinned component framework, injected + validated by the pipeline. |
| EeveeSwiftProtobuf | (upstream) | Pinned component framework, verified in the IPA. |
| CydiaSubstrate | bundled | Pinned shared dependency, validated. |
| Spotify base (IPA route) | 9.1.90 (build 919002269), MinimumOS 16.1 | `Spotify-PwEevee-Corrected.ipa` input; `com.spotify.client` identifier unchanged. |
| Spotify host (deb route) | 9.1.76 only | per `DEBIAN/control` and the CI build report. |
| Bundle metadata | `CFBundleIcons` + `CFBundleIcons~ipad`, **42 alternate icons each** | Verified in both the input and the packaged IPA via plistlib; alternate-icon PNGs (142 resource files) shipped at app root. |

## Verified

Unified IPA probes (`work/probe-rebrand-ipa.py`, **33/33 OK**):

- archive is entry-ordered store-only; exactly one `spotifyglass.dylib`, byte-identical to the fresh CI rebrand dylib;
- `EeveeSpotify.dylib` byte-identical to the pinned component; Orion/EeveeSwiftProtobuf/CydiaSubstrate/EeveeSpotify.bundle all present;
- Spotify 9.1.90, `com.spotify.client`, 42 + 42 alternate icons in both icon dictionaries;
- all 5 declared load commands present in the main executable (`spotifyglass`, EeveeSwiftProtobuf, Orion, EeveeSpotify, CydiaSubstrate);
- dylib string probes: no `discord.gg` / "Join the Discord" / "Ask on Discord" / `SGDiscordURL`; the repo URL is `github.com/codeboy2012/PwEevee`; no upstream user-facing repo URL; site URL `pweevee.skytweak.dpdns.org`; "Support PwEevee"; premium exclusivity gray-out suffix; both premium labels; `EeveeSelectedAppIconName`; legacy `spoti.pw/AdBlock` path kept; "PwEevee" branding present.

Pipeline (`PwEevee/build-system/unified.sh`) self-verification on the release build:

- Mach-O validation PASSED (15 checks); structure validation PASSED (3 dylibs, 5 frameworks, no nesting, no junk); packaging self-check OK (1176 entries).

Test suite battery (all exit 0, final run at the release state):

| Suite | Result |
|---|---|
| `build-tests.pl` | 7 / 7 PASS |
| `deb-format-test.pl` | 30 / 30 PASS |
| `pweevee-premium-exclusivity-tests.pl` | 47 / 47 PASS |
| `eevee-settings-tests.pl` | 67 / 67 PASS |
| `pweevee-rebrand-tests.pl` | 30 / 30 PASS |
| `pweevee-deb-tests.pl` | 6 / 6 PASS |
| `readme-updater-tests.pl` | 29 / 29 PASS |

CI: deb workflow run 39952230740 succeeded at `94962d9`; the repo's pinned component dylib was then refreshed to that build (commit `db3ccd6`).

## Known limitations

- **No device or simulator launch was available.** Settings UI (gray-out behavior, instant re-enabling), icon previews on a real screen, banner removal and app launch are verified by test suites and static binary/resource checks, not by an on-device click-through.
- The deb route assumes host Spotify **9.1.76**; the IPA route ships the **9.1.90** base. Other Spotify versions are not guaranteed.
- `build-manifest.json` records the Spotify version only on macOS (`plutil`); on Windows, unsupported local entries fall back to `"_"`. The version was verified independently with plistlib (9.1.90) and is stated above.
- Upstream Chroma/spoti.pw Plus-gated features remain subject to upstream verification (`plusLocked`); nothing was bypassed.
