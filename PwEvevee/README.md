# PwEvevee/ — the unified integration/build system

This folder is PwEevee's own code: everything responsible for combining spoti.pw and
EeveeSpotify into one IPA — component payloads, dependency resolution, Mach-O
injection, IPA/DEB packaging, validation, tests and release orchestration.

## What's here

| Path | What it is |
|---|---|
| `build-system/unified.sh` | **the one authoritative build command** |
| `build-system/inject/` | LC_LOAD_DYLIB injector (byte-audited against the proven binary) |
| `build-system/lib/` | Mach-O parser, deterministic ZIP writer, plist reader |
| `build-system/package/` | `make-ipa.pl`, byte-exact `make-deb.pl`, `resolve-deps.pl` |
| `build-system/validate/` | Mach-O + filesystem validation |
| `build-system/tests/` | `deb-format-test.pl`, `build-tests.pl`, `component-manifest-test.pl`, `alternate-icon-tests.pl` and the remaining build/package suites |
| `build-system/release/` | `make-release.pl` + local-archive retention, `update-releases.pl` (GitHub release data), `update-altsource.pl` (AltSource variant data), `render-site.pl` (static site generator), `make-social-card.pl`, `lib/PwSite.pm`, `lib/PwHttp.pm` |
| `build-system/_work/` | build scratch space (gitignored) |
| `components/spotipw/` | the spoti.pw payload: `dylibs/spotifyglass.dylib`, MobileSubstrate filter, `manifest.json` with per-file SHA-256 |
| `shared-dependencies/cydiasubstrate/` | CydiaSubstrate.framework + provenance |
| `dependencies.json` | **single source of truth**: shared dependencies, the five load commands, duplicate policy |

## Why the spotipw payload lives here

`components/spotipw/` is a *build input* consumed by `unified.sh`, extracted from the
upstream deb by `Evevee Spotify/component/extract-components.pl` (the extractor writes
both components, but the spotipw one is consumed by the build layer, so it lives here).
The upstream *source* stays in `Spotipw/` untouched.

## Usage

```bash
bash PwEvevee/build-system/unified.sh <decrypted Spotify 9.1.84 .ipa> -o dist/out.ipa
perl PwEvevee/build-system/tests/deb-format-test.pl
perl PwEvevee/build-system/tests/build-tests.pl
```

Documentation and the public website are being rebuilt for v4; the root README carries the current release and download links.
