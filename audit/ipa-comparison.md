# IPA Comparison — PwEevee v3.1.0 forensic audit

Evidence base: extraction + dumps in `audit/ipas/` (archives validated, binaries never
executed). Machine-readable numbers live in `audit/ipas/evidence/{stock,pweevee,taurus,chroma}/`.
All hashes are SHA-256 (truncated to 16 hex chars in tables here unless noted).

## 0. The four artifacts

| IPA | Size (B) | SHA-256 (full) |
|---|---|---|
| com.spotify.client_9.1.90_und3fined.ipa (stock) | 153,481,523 | `409601a58953818eea17edb92963d10256ae6fcf00c69954105e5becc08ec296` |
| PwEevee-0.22.0-alpha.2-unified-Spotify-9.1.90.ipa | 300,634,848 | `a76b469a8291d6650026ef1355b77ead37efcc9250517aaf057a6e6b1dab3996` |
| Taurus-0.60.4.ipa | 137,901,231 | `6e1e367b7710822207a3f36d30c35790075af1c8c541a18ef4af04ec900e03f1` |
| chroma-1.0.0-beta.3.ipa | 155,786,119 | `8e051f44d4d55eaa377d62d518f1c2222a0bf43f47a1e40c2e12ad2144c84ddc` |

ZIP central-directory walk succeeded on all four (per-IPA `*.ziptest.txt`). PwEevee's IPA is
far larger because it ships 8 lproj sets re-added plus both tweak stacks (see §2).

## 1. Info.plist metadata matrix

| Field | stock | PwEevee α.2 | Taurus 0.60.4 | chroma β.3 |
|---|---|---|---|---|
| CFBundleIdentifier | com.spotify.client | com.spotify.client | com.spotify.client | com.spotify.client |
| CFBundleShortVersionString | (packed only) | 9.1.90 | 9.1.90 | (packed only) |
| CFBundleVersion | 919002269 | 919002269 | 919002269 | 919002269 |
| SpotifyVersionPacked | 919002269 | — | — | 919002269 |
| MinimumOSVersion | 16.1 | 16.1 | 16.1 | 16.1 |
| DTPlatformVersion / DTSDKBuild | 27.0 / 24A430 | 27.0 / 24A430 | 27.0 / 24A430 | 27.0 / 24A430 |
| CFBundleExecutable | Spotify | Spotify | Spotify | Spotify |
| CFBundleIconName | AppIcon | AppIcon | AppIcon | **SGPrimaryIcon** |
| Watch/WatchApp.app | present | **removed** | removed | removed |
| PlugIns | 4 (Intents, NotifService, NotifContent, Widget) | 4 + **SpotifyGlassLiveActivity.appex** | 5 (+ **TaurusOpenSpotify.appex**) | 4 + SpotifyGlassLiveActivity.appex |
| SpotifyBuildTimestamp | 1791216420 | (stripped) | (stripped) | 1791216420 |

Verified source: `audit/ipas/evidence/*/info.flat.txt`.

Interpretation (not binary-verified): chroma keeps the original Spotify build
timestamp and icon tree intact and repoints `CFBundleIconName` to its own
`SGPrimaryIcon` alternate-icon set — consistent with chroma handling icons through
the app-icon API rather than asset replacement. PwEevee and Taurus strip the Watch
app and the Spotify build metadata; both bundle a LiveActivity extension.

## 2. Main Mach-O (Payload/Spotify.app/Spotify)

| | stock | PwEevee α.2 | Taurus 0.60.4 | chroma β.3 |
|---|---|---|---|---|
| Size (B) | 236,908,560 | 232,829,312 | 232,829,312 | 236,908,560 |
| SHA-256 (16) | `57bd5a9bc60bf430` | `e5d0a729c9e8c068` | `ad1704ad613b27c1` | `c02b2eab8f11fdfa` |
| filetype / cputype | MH_EXECUTE arm64 | same | same | same |
| ncmds / sizeofcmds | 146 / 16,280 | 153 / 16,824 | 149 / 16,456 | 148 / 16,400 |
| LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB | 95 / 29 | 100 / 31 | 95 / 32 | 95 / 31 |

### Load commands added vs stock (sorted-diff of `main-lcs-full.txt`)

- **PwEevee α.2** (+7): weak `@rpath/SpotifyGlassAppGroups.dylib` (cmd 145), weak
  `@rpath/spotifyglass.dylib` (146), then five strong loads at 148–152:
  `@executable_path/Frameworks/spotifyglass.dylib`,
  `.../EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf`,
  `.../Orion.framework/Orion`, `.../EeveeSpotify.dylib`,
  `.../CydiaSubstrate.framework/CydiaSubstrate`. Command 147 is a non-dylib
  command (present in the dump; its name is not decoded by the tooling used — treat
  the exact type as unverified). The five strong entries match
  `PwEvevee/dependencies.json` `expected_load_commands` **exactly**; the two weak
  `@rpath` entries are NOT declared anywhere in the repo.
- **Taurus 0.60.4** (+3): weak `@rpath/SpotifyAudioProbe.dylib`,
  `@rpath/SpotifyGlassAppGroups.dylib`, `@rpath/spotifyglass.dylib`.
- **chroma β.3** (+2): weak `@rpath/SpotifyGlassAppGroups.dylib`,
  `@rpath/spotifyglass.dylib`.

Notes on parsed plausibility: stock's own 29 weak system-framework loads are normal
Xcode behavior; the pattern "weak @rpath duplicates + strong @executable_path load of
the same dylib" in PwEevee/Taurus/chroma is the typical footprint of an
insert-dylib-style injector left on the base binary. Absence of `LC_ UMBRELLA`
(equivalent `createSandboxBinaries` text) is not observable here; no such claim is
made. The weak duplicates mean dyld may resolve `spotifyglass` **twice** (weak @rpath
first if an rpath matches, then the strong @executable_path load fails silently —
the strong path always wins). No runtime crash behavior can be inferred from this
evidence alone (unverified hypothesis, see findings.json U-1).

`@rpath` values in all four: `@executable_path/Frameworks` plus stale Xcode paths —
Sideloadly-style repack tools strip/rewrite these at install time.

## 3. Frameworks / dylibs shipped in `Spotify.app/Frameworks/`

| Component | stock | PwEevee α.2 | Taurus 0.60.4 | chroma β.3 |
|---|---|---|---|---|
| CydiaSubstrate.framework binary | — | **748d129f68a3a262 377,952** | **748d129f68a3a262 377,952** | — |
| spotifyglass.dylib | — | e633f9244c239f40 1,816,144 | 5e4f5c89213f0c1e 3,277,376 | 5f640a584e1159e2 8,569,056 |
| SpotifyAudioProbe.dylib | — | — | fcbf71878993797c 536,352 | — |
| SpotifyGlassAppGroups.dylib | — | 64f238e1f88b4a15 86,592 | 64f238e1f88b4a15 86,592 | 3c5a5109b29e8892 67,936 |
| EeveeSpotify.dylib | — | 631d4f17cb5e6d3c 2,563,648 | — | — |
| Orion.framework | — | 290889165a4d156a 215,232 | — | — |
| EeveeSwiftProtobuf.framework | — | ab0ce0f4192ffa0b 5,842,992 | — | — |
| Stock Spotify frameworks (SpotifyShared, MetaSmartGlassesKit, …) | yes | yes (unchanged file sizes) | yes | yes |

Highlights:

- The **shipped CydiaSubstrate inside PwEevee α.2 is byte-identical to Taurus
  0.60.4's** (`748d129f…`, 377,952 B), and **differs from the repo's pin**
  (`3c691ec7…`, 403,200 B, checked against the HEAD git blob). The shipped package
  was therefore assembled from the Taurus stack, not from the repo's
  `shared-dependencies/cydiasubstrate` directory as-is. Filed as finding D-3.
- The shipped `spotifyglass.dylib` (`e633f924…`) **does** match the repo's refreshed
  pin (HEAD blob identical byte-for-byte). Repo is authoritative for this component.
- chroma's substrate-free stack and much larger `spotifyglass.dylib` (8.6 MB) mark it
  as the most self-contained of the three forks; it also is the one that reuses the
  stock main binary at stock size, with only +2 weak loads.
- No framework bundle in any IPA carries a top-level signature for the *main app*
  usable for install; nested `.framework` trees retain their embedded
  `_CodeSignature`, and `.appex` extensions retain theirs. No
  provisioning-profile file exists in any of the four (expected for decrypted
  redistributions; noted, not "fixed").

## 4. Bundle-table deltas (verified vs interpretation)

Verified (files present/absent, sizes):

| Delta | Verified fact |
|---|---|
| PwEevee vs stock | −`Watch/` tree, −`CFBundleIcons` alternate-icon table differences, +`Frameworks/{ spotifyglass, EeveeSpotify, Orion, EeveeSwiftProtobuf, CydiaSubstrate }`, +`PlugIns/SpotifyGlassLiveActivity.appex`, main binary +7 cmds |
| PwEevee vs Taurus | same substrate bytes, different spotifyglass build (1.77→3.28 MB), no SpotifyAudioProbe, no TaurusOpenSpotify.appex, +Eevee-spottify stack (EeveeSpotify.dylib + 2 frameworks), +7 vs +3 main-binary cmds |
| PwEevee vs chroma | chroma keeps stock main-binary size, ships only weak-loaded content, has no substrate/Eevee stack; chroma repoints app icon to SGPrimaryIcon |
| Taurus vs chroma | Taurus = substrate + strong injection model; chroma = weak-load model, no substrate |

Interpretations requiring runtime evidence (NOT verified here):

- "PwEevee has feature X because `EeveeSpotify.dylib` is present" — presence is
  verified; behavior is **not** (no binaries were executed).
- "chroma's icon change works because the plist is intact" — plausible, not proven.
- Byte-evolvability checks: archive ordering, store-only compression, fixed DOS
  timestamps — all four are store-only ZIP archives. Since each fork ships a
  different repackager's output, whole-IPA hash equality is meaningless and
  per-component hashes are used throughout instead.

## 5. Signatures / provisioning

- Main Spotify binary in all four: LC_CODE_SIGNATURE is present but with an absurd
  offset/size (e.g. off=3240283899 size=222174078 in the dumps - the classic footprint
  of an injector that cleared but did not rebuild the code-signature blob), so every
  usable install route re-signs the app (Sideloadly/TrollStore/side store). Normal
  for decrypted redistributions and applies to Taurus/chroma equally.
- No `embedded.mobileprovision` in any of the four bundles.
- `SC_Info` trees survive in stock + all three forks (fairplay remnants; unused for
  unsigned installs).
