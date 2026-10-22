# PwEevee deb — final dependency/runtime audit (pre-Theos-build)

Date: 2026-09-27 · Scope: `PwEevee_0.22.0-alpha.2_iphoneos-arm.deb` · Host: **Spotify 9.1.76 only**

Every claim below is evidence-backed from the artifacts in this repo (`Evevee Spotify/component/`,
`Evevee Spotify/source-artifacts/`, the decrypted 9.1.76 host IPA) and from the load-command dumps in
`docs/UNIFICATION-AUDIT.md`. No device was tested; no runtime behavior is claimed.

## Verdict

The architecture is **correct as designed**; no dependency changes are required. Three audit findings
were applied (one dead path removed, one doc correction, one CI bug), and one open architecture
question is documented for a future release (see §8).

## 1. Runtime dependency graph of the final integrated `spotifyglass.dylib`

Load commands (from `macho-dump.pl`, cross-checked against `docs/UNIFICATION-AUDIT.md`):

| Load command | Resolved from | Class |
|---|---|---|
| `LC_LOAD_WEAK_DYLIB /Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib` | itself (self-referential weak; Theos default) | self |
| UIKit, Foundation, CoreFoundation, QuartzCore, UniformTypeIdentifiers, MediaPlayer, CoreImage, AudioToolbox, AVFoundation, CoreHaptics, Accelerate, CoreGraphics, CoreMedia, AVFAudio, AppIntents | iOS system frameworks | system |
| libobjc, libSystem | iOS system libraries | system |
| libswiftCore, libswift_Concurrency, libswiftos (+ rpaths `/usr/lib/swift`, `/usr/lib/libswift/stable`) | iOS Swift runtime | system |
| **CydiaSubstrate: NOT linked** | — | n/a |
| **EeveeSpotify / Orion / EeveeSwiftProtobuf: NOT linked** | — | n/a |

The tweak uses Logos' `internal` generator (runtime swizzling; `LOGOS_DEFAULT_GENERATOR := internal`
in `Spotipw/tweak/Makefile`), so it needs no Substrate symbols — MobileSubstrate's role is only to
**load** the dylib per the filter plist.

`EeveeSpotify.dylib` (the payload, NOT in the deb) needs: system frameworks + SwiftUI + libc++ +
`@rpath/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf` + `@rpath/Orion.framework/Orion` +
`LC_LOAD_WEAK_DYLIB @rpath/EeveeSpotify.dylib` (self), with rpaths `/var/jb/Library/Frameworks`,
`/var/jb/usr/lib`, `@loader_path/.jbroot/Library/Frameworks`, `@loader_path/.jbroot/usr/lib` — all
satisfied inside the host IPA (`Spotify.app/Frameworks/…`, per `PwEvevee/dependencies.json`).

## 2. `Depends:` verdict — **keep `firmware (>= 15.0), mobilesubstrate`**

- **mobilesubstrate is correct for the deb's distribution form**: the deb installs the dylib under
  `var/jb/Library/MobileSubstrate/DynamicLibraries/`, which is loaded by MobileSubstrate or its
  rootless equivalents (ElleKit/TweakInject provide the MobileSubstrate compatibility layer on
  modern rootless jailbreaks; the package name `mobilesubstrate` is the metapackage every provider
  satisfies). The dylib has no Substrate *symbol* dependency, but the *loader* is still a runtime
  requirement of this layout. Upstream Eevee's deb omits it only because its data lives inside
  `Spotify.app/` and is injected by load commands instead.
- **firmware (>= 15.0)**: the unified tweak's deployment target is iOS 16.0
  (`TARGET := iphone:clang:latest:16.0`), so ≥ 15.0 is conservative but correct as a floor; no change.
- `Architecture: iphoneos-arm`: Theos on the current scheme (no `THEOS_PACKAGE_SCHEME=rootless`
  set in the Makefile) emits `iphoneos-arm` for rootless-compatible packages, and the deb's own
  paths (`var/jb/…`) are the rootless convention. The upstream Eevee deb says `iphoneos-arm64` while
  carrying the same `var/jb` layout, so the arch field varies by builder convention; `iphoneos-arm`
  matches what Theos produces for this tweak and is kept. If a future rootless-strict build sets
  `THEOS_PACKAGE_SCHEME=rootless`, this stays correct.

## 3. Component classification

| Component | Class | Where it must be |
|---|---|---|
| iOS system frameworks/libs (UIKit, SwiftUI, Foundation, Accelerate, CoreHaptics, AVFoundation, swift runtime, …) | system | device — never packaged |
| MobileSubstrate / ElleKit / TweakInject loader | jailbreak environment | declared in `Depends`, not embedded |
| `spotifyglass.dylib` (unified: SpoTi.pw 0.22.0 + PwEevee integration) | **in the deb** | `var/jb/Library/MobileSubstrate/DynamicLibraries/` |
| `spotifyglass.plist` filter (`Bundles = com.spotify.client`) | **in the deb** | beside the dylib |
| `EeveeSpotify.bundle` (localized strings + `resolveconfiguration.bnk`) | **in the deb** (jailbreak route) **and** in the host IPA (IPA route) | `var/jb/Library/Application Support/EeveeSpotify.bundle/` — BundleHelper's first search path (verified from dylib strings: `/Library/Application Support/`, "Loaded bundle from filesystem", "Loaded bundle from main bundle", "Could not find EeveeSpotify.bundle!") |
| `EeveeSpotify.dylib` | IPA customization workflow only | `Spotify.app/Frameworks/` + LC_LOAD_DYLIB on the main executable |
| `Orion.framework`, `EeveeSwiftProtobuf.framework` | IPA customization workflow only | `Spotify.app/Frameworks/` (+ LC_LOAD_DYLIBs) |
| `CydiaSubstrate.framework` | IPA customization workflow only | `Spotify.app/Frameworks/` (+ LC_LOAD_DYLIB) |
| 142 icon PNGs | IPA customization workflow only | `Spotify.app/*.png` (app root) — see §5 |
| `CFBundleAlternateIcons` in Info.plist | IPA customization workflow only | host IPA's Info.plist (already present with all 142 names) |
| Theos, iPhoneOS SDK, gmake, ldid, xz, perl, SGFlagList.m | build-time only | build machine / CI (`SG_FLAG_LIST` secret) |
| Theos' own Theos.deb plumbing, `vendor/audio` static lib | build-time only | linked in (`libsgaudio.a`) / discarded |

## 4. Exact files packaged

```
DEBIAN/control                                     (from tweak/pweevee-control + Installed-Size)
var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib   (~1.7 MB, ldid -S'd)
var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist   (filter: com.spotify.client)
var/jb/Library/Application Support/EeveeSpotify.bundle/              (~0.5 MB: Info.plist, github.png,
    resolveconfiguration.bnk, 28× <lang>.lproj/Localizable.strings)   — Eevee's own UI asset github.png
                                                                      belongs to the bundle
```

## 5. Exact files intentionally excluded, and why

| Excluded | Reason (evidence) |
|---|---|
| 142 icon PNGs (`var/jb/share/pweevee/icons/` removed this audit) | **Dead path.** Eevee's picker (`EeveeAppIconPickerView`/`AppIconEntry` in the dylib) reads `CFBundleAlternateIcons`/`CFBundleIconFiles` from `infoDictionary` and applies via `setAlternateIconName:completionHandler:`; iOS loads the PNGs from the installed app root. The Eevee dylib contains **no** `share/` string, no `.png` path string, and no icon-directory reader. `SGEeveeIconsPage` (PwEevee) reads the same Info.plist keys. Icons ride the host IPA. |
| `EeveeSpotify.dylib`, `Orion.framework`, `EeveeSwiftProtobuf.framework`, `CydiaSubstrate.framework` | Payload components of the IPA customization workflow; `spotifyglass.dylib` does not link them. See §8 for the standalone-jailbreak consequence. |
| Spotify app binary / payload | The deb is the modification, not the host; distributing it would be redistribution. |
| Any second `EeveeSpotify.dylib` / framework copy | Duplicate-dependency guard (test-pinned): a second copy in `var/jb` would not resolve for dyld inside the app sandbox anyway. |
| Live Activity appex, AppGroups shim | Built by the IPA pipeline (`extension/`), not part of the tweak package. |
| Sources, IPAs, keys, SGFlagList.m, build dirs | Never shipped (negative test-pinned). |

## 6. MobileSubstrate filter and install paths (rootless)

- Filter: `{ Filter = { Bundles = ( "com.spotify.client" ); }; }` — byte-verified in the package.
- Paths: `var/jb/Library/MobileSubstrate/DynamicLibraries/{dylib,plist}` — the rootless convention
  (`/var/jb` is the jbroot prefix; the payload dylib's own rpaths `/var/jb/…` and
  `@loader_path/.jbroot/…` confirm the ecosystem expects exactly this).
- Bundle search order verified from `EeveeSpotify.dylib` strings (`_TtC12EeveeSpotify12BundleHelper`):
  1. `<home>/Library/Application Support/EeveeSpotify.bundle` → the deb's `var/jb/Library/Application Support/EeveeSpotify.bundle` ✔
  2. main bundle (`Spotify.app/EeveeSpotify.bundle`) → the IPA route's copy ✔ (fallback)

## 7. Size — the ~19 MB estimate was wrong; corrected numbers

| Item | Measured |
|---|---|
| `spotifyglass.dylib` (unified, pre-integration trial build) | 1,747,536 B (integrated build ≈ same +~50 KB) |
| `EeveeSpotify.bundle` | ~500 KB |
| icons | **0 in the deb** (2.0 MB rides the host IPA) |
| **.deb compressed (trial, pre-integration dylib)** | **4.5 MB** (`/tmp/debtest/test-full.deb`, 4,526,868 B); re-run without icons: **0.59 MB** stage-equivalent → the integrated deb should land ≈ **0.6–0.7 MB** (dylib dominates, ~1.7 MB → ~0.55 MB lzma) |
| Installed-Size (control) | ~2.2 MB (was 6.4 MB with icons in the trial) |

## 8. Open architecture question (flagged, not changed)

The deb alone does **not** provide Eevee functionality on a fresh jailbroken device: it pairs with the
customized host IPA, which supplies `EeveeSpotify.dylib`, `Orion.framework`, `EeveeSwiftProtobuf.framework`,
`CydiaSubstrate.framework`, the in-app bundle, the icons and `CFBundleAlternateIcons`. A *self-contained*
jailbreak deb would have to write into `Spotify.app/` (as upstream Eevee's deb does — verified in its
data tree). Alpha.2 deliberately does not do that; revisit if deb-only distribution is ever wanted.

## 9. Changes applied by this audit

1. **Removed the dead `var/jb/share/pweevee/icons/` path** from `Spotipw/scripts/build-deb.sh`
   (header comment, mkdir, copy, build report), `PwEvevee/build-system/tests/pweevee-deb-tests.pl`
   (now asserts no icons ship and no `var/jb/share` paths exist), and `docs/DEB.md`.
2. **Documented** the deb/IPA component split precisely in `docs/DEB.md` (CFBundleAlternateIcons,
   bundle fallback, alpha boundaries) and added the standalone-jailbreak caveat + no-device-test note.
3. **Fixed CI**: `.github/workflows/pweevee-deb.yml` restored `SGFlagList.m` to `tweak/…` but the
   build runs from `Spotipw/` — path corrected to `Spotipw/tweak/Sources/Shared/Flags/SGFlagList.m`.

## 10. Checklist items verified

- Integration-symbol hard failure **kept**: `build-deb.sh` refuses to package unless the built dylib
  contains `SGEeveeSpotifyPage`, `SGEeveeRemoveStandaloneRow`, `SGEeveeRestoreLyricsReplacement`
  (verified live: the stale pre-integration trial dylib is rejected — 3 expected failures).
- **Spotify 9.1.76 is the only claimed target** (control Description, build report, docs, tests
  asserting no 9.1.84 claim). Hook classes for 9.1.76 were verified present earlier this audit
  (`_TtC21Settings_PlatformImpl26SettingsListViewController` present; `ProfileSettingsSection` /
  `RootSettingsViewController` absent — matching both mods' hooks).
- **No device-compatibility claim**: docs/DEB.md and this audit state device testing has not been
  performed; runtime behavior is untested until a real device run.

## 11. Changes required before the first real Theos build

1. Nothing blocking in packaging — `bash -n` clean; full pipeline dry-run re-verified post-fix
   (38/41 checks on the trial deb; the 3 failures are the symbol gate correctly rejecting the stale
   dylib; structural-only run: 6/6).
2. The Theos build must run where Theos + iPhoneOS 26 SDK exist (macOS local or
   `.github/workflows/pweevee-deb.yml` on macos-15 with the `SG_FLAG_LIST` secret; the secret
   convention is `gzip -9c …SGFlagList.m | base64`).
3. On the build machine, `tweak/Sources/Shared/Flags/SGFlagList.m` must exist
   (`scripts/extract-flags.py` from the decrypted 9.1.76 IPA) or the script exits before packaging.
4. First real build should be followed by: run `pweevee-deb-tests.pl` on the artifact (build-deb.sh
   does this automatically), then a device install before any compatibility claim.
