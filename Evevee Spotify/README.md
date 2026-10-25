# Evevee Spotify/ — EeveeSpotify payloads and source artifacts

Everything specific to **EeveeSpotify**: the extracted payload used by the unified
build, the upstream packages it was extracted from, and the legacy tools used to audit
them. The known-good file hashes recorded during the audit are preserved byte-for-byte
(re-verified after the reorganisation).

## What's here

| Path | What it is |
|---|---|
| `component/` | the extracted Eevee payload: `package/dynamic-libraries/EeveeSpotify.dylib` (+ plist filter), `frameworks/{Orion,EeveeSwiftProtobuf}.framework`, `bundles/EeveeSpotify.bundle`, `resources/` (142 icon PNGs), `manifest.json` with per-file SHA-256 and origin deb hash |
| `component/extract-components.pl` | rebuilds `component/` **and** `PwEvevee/components/spotipw/` from the source artifacts; deterministic, `--force` re-extracts |
| `source-artifacts/` | the audited upstream packages: `com.eevee.spotify_7.0.0_iphoneos-arm64.deb` (current payload origin, jb-style, + its `v7.0.0-release-notes.txt`), `EeveeSpotify-6.6.8-SelfContained-v2.deb` (historical origin), `com.spotipw_0.22.0_iphoneos-arm.deb`, the decrypted Spotify input IPA (`Sptoify-No_Watch_App.ipa`, gitignored), and the legacy Perl audit tools |

## Key hashes (audit-verified, maintained by `component/extract-components.pl`)

| File | SHA-256 (prefix) |
|---|---|
| `component/package/dynamic-libraries/EeveeSpotify.dylib` | `8997e5c946d702b062b4b2482e37e9675ef013e8fae951b8b0871f55a856cdb4` (upstream v7.0.0 refresh) |
| `component/package/dynamic-libraries/KaraokeBackgroundShader.metallib` | `95ee5f0c0bcbad1ff2f5a0e4aea1d3c21035fa77b7653d74a671aacc3a0cb1b6` |
| `com.eevee.spotify_7.0.0_iphoneos-arm64.deb` (payload origin) | `513a50b197aa558c34b02b87bff9f46e6cad3b2e462ee8622fc72fd939e83a9b` |
| previous v6.6.8 dylib (inside the historical deb only) | `631d4f17cb5e6d3cd90e67f3043f723e1cb28e11dfca475d67f63657c979de70` |
| bundle `Localizable.strings`, 142 icons, frameworks | verified per-file in `component/manifest.json` |

## Rules

- **Never hand-edit anything under `component/`.** If payloads need refreshing, run
  `perl component/extract-components.pl --force` and check the per-file hashes.
- **`component/` output is wiped on `--force`** — never re-run it without confirming
  the manifests exist afterwards.
- The decrypted Spotify app the build takes as input lives in `source-artifacts/` and is
  gitignored (`*.ipa`); the debs are committed provenance.
- EeveeSpotify is upstream software: Eevee is its author, and the upstream self-contained
  deb integrated here is maintained by jaydenjcpy. This folder only extracts what upstream
  ships; it does not modify it. The integration and the unified package built around it are
  PwEevee's own work.
