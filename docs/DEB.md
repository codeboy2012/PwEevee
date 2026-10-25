# PwEevee `.deb` — the unified tweak package

**PwEevee v0.22.0-alpha.2** · **Spotify 9.1.76 only** · SpoTi.pw v0.22.0 · EeveeSpotify v6.6.8

This is an **alpha** for the decrypted **Spotify 9.1.76** IPA. Nothing here claims 9.1.84 or any other
Spotify version.

## What the model is

    decrypted Spotify 9.1.76 IPA   (the host; yours)
    +  PwEevee_0.22.0-alpha.2_iphoneos-arm.deb   (the modification; this package)
    ↓  customization/injection (cyan, as in scripts/pipeline.sh)
    PwEevee IPA

The deb never contains the Spotify IPA. The host app stays where it belongs; the package carries the
tweak, its filter and Eevee's runtime resources.

## What the package contains

| Path in the package | What it is |
|---|---|
| `var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib` | the unified tweak: SpoTi.pw v0.22.0 plus the PwEevee settings integration (EeveeSpotify page inside Mod Settings) |
| `var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist` | MobileSubstrate filter, `Bundles = com.spotify.client` |
| `var/jb/Library/Application Support/EeveeSpotify.bundle/` | EeveeSpotify's localized strings + `resolveconfiguration.bnk` (its `BundleHelper` searches this path first) |
| `DEBIAN/control` | generated from `Spotipw/tweak/pweevee-control` |

The 142 app-icon PNGs are **not** in the deb. Eevee's icon picker (and PwEevee's `SGEeveeIconsPage`)
reads `CFBundleAlternateIcons` from the app's Info.plist and applies icons via `setAlternateIconName`;
iOS loads the PNGs from the app root of the installed app — there is no code path that reads them from
`var/jb` (the Eevee dylib contains no `share/` or `.png` path string at all). The host IPA already
carries all 142 PNGs at `Spotify.app/*.png`; an earlier `var/jb/share/pweevee/icons/` location was
dead weight and was removed after this audit.

## Runtime dependencies: what ships, what is expected

**Ships in the deb:** the unified dylib, its filter, and Eevee's strings bundle. (The icon PNGs ship
only via the host IPA — see above.)

**Provided by the host IPA (customization workflow places them; the audited components under
`PwEvevee/components/` and `Evevee Spotify/component/` are the source):**

- `EeveeSpotify.dylib` — EeveeSpotify v7.0.0, SHA-256 `8997e5c9…cdb4`, extracted from upstream `com.eevee.spotify_7.0.0` by `Evevee Spotify/component/extract-components.pl` and hash-pinned in `Evevee Spotify/component/manifest.json`
- `Orion.framework`, `EeveeSwiftProtobuf.framework` — Eevee's Swift runtime
- `CydiaSubstrate.framework` — shared
- `EeveeSpotify.bundle` + 142 icon PNGs **inside the app** (the IPA route's locations; the deb's
  bundle copy under `var/jb` is the jailbreak route's, and both being present is harmless — the
  dylib searches both)
- the five `LC_LOAD_DYLIB` load commands on the main executable (`PwEvevee/dependencies.json` is the
  authority)
- `CFBundleAlternateIcons` in Info.plist (the host IPA already carries it with all 142 icon names)

**Provided by the jailbreak/rootless environment (declared, not embedded):**
`mobilesubstrate` (Substrate/Substitute/ElleKit — whichever the environment ships) and `firmware >= 15.0`,
both in `Depends`. The iOS system frameworks the dylib links (UIKit, Foundation, Accelerate, CoreHaptics,
AVFoundation, …) are the device's own; shipping them would be both wrong and enormous.

## Building it

The deb is written by pure-perl tooling (`PwEvevee/build-system/package/make-deb.pl`), but the tweak
inside is Theos + iPhoneOS SDK — **a Mac (or macOS CI) is required for that step**, exactly as for every
other PwEevee build. On Debian/Linux the packaging steps run, but Theos cannot produce the arm64 dylib
without an iPhoneOS SDK/toolchain; don't fake it there.

```bash
cd Spotipw

# one-time: the flag table is read out of Spotify's binary and is not committed
./scripts/extract-flags.py /path/to/decrypted-Spotify-9.1.76.ipa

./scripts/build-deb.sh
# → dist/PwEevee_0.22.0-alpha.2_iphoneos-arm.deb
#   dist/PwEevee_0.22.0-alpha.2_iphoneos-arm.build-report.txt   (size, sha256, timestamp)
```

In CI, `.github/workflows/pweevee-deb.yml` does the same on `macos-15` (needs the `SG_FLAG_LIST`
secret, as `release.yml` does).

The script: builds the tweak (`gmake -C tweak clean package FINALPACKAGE=1`), asserts the built dylib
carries the PwEevee integration symbols (`SGEeveeSpotifyPage`, `SGEeveeRemoveStandaloneRow`,
`SGEeveeRestoreLyricsReplacement`), gathers Eevee's resources, generates `control`, writes the deb
deterministically, and runs `PwEvevee/build-system/tests/pweevee-deb-tests.pl` against the result.

## Inspecting it

```bash
dpkg-deb --info  Spotipw/dist/PwEevee_0.22.0-alpha.2_iphoneos-arm.deb
dpkg-deb --contents Spotipw/dist/PwEevee_0.22.0-alpha.2_iphoneos-arm.deb
perl PwEvevee/build-system/tests/pweevee-deb-tests.pl Spotipw/dist/PwEevee_*.deb
```

## Using it with the IPA customization workflow

1. Build/obtain the deb (above).
2. Follow `PwEvevee/build-system/unified.sh`'s merge + inject steps for the host IPA (the audited
   components supply the Eevee dylib, the two frameworks, Substrate, the in-app bundle and icons, and
   the five load commands).
3. The deb's contents are the **jailbreak-route layout** of the same payload: on a jailbroken device
   the deb installs alone and MobileSubstrate loads `spotifyglass.dylib` into Spotify via its filter.
   **Note (alpha):** for the deb *alone* to work that way, `EeveeSpotify.dylib`, `Orion.framework`,
   `EeveeSwiftProtobuf.framework` and the in-app `CFBundleAlternateIcons` must also come from
   somewhere — the upstream Eevee self-contained deb provides them by writing into `Spotify.app/`,
   which this deb deliberately does not do (see the dependency audit in `docs/DEB-AUDIT.md`).
   The supported pairing is deb + customized host IPA; a deb-only jailbreak install is a future
   decision, not something alpha.2 provides. For sideloaded distribution, use the IPA route.

## Known issues

- Alpha: **Spotify 9.1.76 only**. 9.1.84 is *not* supported by this package and has not been tested.
- The Live Activity appex (Spoti.pw's lock-screen widget) is built by the IPA pipeline; this deb ships
  the tweak only. A jailbreak install gets everything except the widget extension.
- The deb alone does not carry Eevee's payload dylib/frameworks — it pairs with the customized host
  IPA (previous section). A self-contained jailbreak deb would have to write into `Spotify.app/`,
  which alpha.2 intentionally avoids.
- Device testing has not been done for this alpha; the automated tests cover structure, contents and
  integration symbols, not runtime behavior. No compatibility claim is made until a device test
  passes.
