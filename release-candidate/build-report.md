# PwEevee v3.1.0 RC — build report

**A release-candidate IPA exists and passed every validator the repository owns.**
Built locally on the Windows machine with the repository's own documented
pipeline; the Mac stayed unreachable (no SSH key installed — see blockers).

## Environment

| Tool | Version | Notes |
|---|---|---|
| bash | 5.3.15(2)-release (x86_64-pc-cygwin) | Git-bash/MSYS2 runtime |
| perl | 5.42.3 (v5.42.3, x86_64-cygwin-thread-multi) | the pipeline's primary tool |
| xz | 5.8.4 | required by unified.sh |
| unzip | 6.00 (Info-ZIP) | required by unified.sh |
| python | 3.13.8, **contained in `release-candidate/tools/python/`** | added this session only for the Watch plist fix (see below); NOT installed system-wide; zip fetched from python.org/ftp/python/3.13.8/python-3.13.8-embed-amd64.zip |

- Source commit: `43a92ce` on `feat/v3.1.0-integration` (recorded in build-manifest.json as `spotipw_commit`).
- Base (decrypted) Spotify IPA: `C:\Users\sleepy\Downloads\com.spotify.client_9.1.90_und3fined.ipa`
  - sha256 `409601a58953818eea17edb92963d10256ae6fcf00c69954105e5becc08ec296`, 153,481,523 bytes
  - This is the same decrypted 9.1.90 base documented for the previous 0.22.0-alpha.2 unified build — the documented source base, used **read-only**; original IPAs were never written to.
- Prebuilt pinned components used by merges (hash-verified in-suite, cross-checked on the packaged artifact): `spotifyglass.dylib` (`e633f924…`), `EeveeSpotify.dylib` 7.0.0 (`8997e5c9…`), `pweevee-icon.png` (`2fb04e22…`) plus Orion/EeveeSwiftProtobuf/CydiaSubstrate framework pins (component-manifest-test: 389 checks, exit 0).
- Xcode / macOS / signing credentials: **none used — none required** by this pipeline (no compilation; all tweak binaries are pinned prebuilt files). Signing and provisioning: the packaged IPA is a store-only, **unsigned** archive like its 0.22.0-alpha.2 predecessor; final signing happens on sideload. What could not be verified: codesign identities, provisioning profiles, entitlements enforcement — **NOT TESTED (no signing credentials/no macOS).**

## Prerequisite fix during the build (honest, contained)

First build attempt (exit 1, full log kept): `watchfix-stage` failed with
`WARN: binary plist … but no plutil/plistlib — cannot edit CFBundleIdentifier
safely`. Cause: this machine has **no real Python** (only the Microsoft-Store
stub executable). Fix was contained to the RC workspace: the Python 3.13.8
embeddable distribution was downloaded into
`release-candidate/tools/python/` and put on PATH for the build + watchfix
tests only. No system settings, PATH, or registry values were changed; nothing
outside `release-candidate/` was installed.

## Exact build command (reproducible)

```
cd C:/Users/sleepy/Documents/PwEevee
PATH="$PWD/release-candidate/tools/python:$PATH" \
  bash PwEvevee/build-system/unified.sh \
  /c/Users/sleepy/Downloads/com.spotify.client_9.1.90_und3fined.ipa \
  -o release-candidate/PwEevee-0.22.0-rc1-unified-Spotify-9.1.90.ipa \
  --watch
```

Exit code **0**; full log: [build.log](build.log) (every pipeline step
`prepare → merge → resolve → inject(5 load commands) → validate Mach-O(15/15) →
watchfix(self-check OK) → alternate-icon registration("mirrored into
CFBundleIcons~ipad (host declares it)") → structure validation(2 dylibs, 5
frameworks, watch kept) → deterministic store-only package → manifest → packaging
tests OK`).

## Artifact

| Field | Value |
|---|---|
| Path | `release-candidate/PwEevee-0.22.0-rc1-unified-Spotify-9.1.90.ipa` |
| Size | 338,031,911 bytes |
| SHA-256 | `9845b1c325ac0b042e129bb892103975daed80becea0122c4977ce743ed55415` |
| Guides | `release-candidate/build-manifest.json` (travel-safe, colocated) |
| Log | `release-candidate/build.log` |

Manifest records: spotify 9.1.90, spotipw 0.22.0 @ `43a92ce`, eevee 7.0.0,
load commands 5, eevee resource icons 142, `brand_icon: pweevee-icon.png …`.

## Post-build verification of the packaged artifact

- Both validators re-run **against the unpacked RC artifact** (not just staged tree):
  `validate-macho.pl` → `MACH-O VALIDATION PASSED (15 checks)`, all 5 declared
  load commands present, rpaths intact; `validate-ipa.pl` → `STRUCTURE VALIDATION
  PASSED (2 dylibs, 5 frameworks, no nesting, no junk, watch kept)`.
- `CFBundleShortVersionString` = 9.1.90; `CFBundleAlternateIcons` and the `PwEevee`
  entry with `pweevee-icon` references verified present in the packaged
  `Info.plist` (grep on the extracted app).
- Byte-for-byte pin cross-check: `spotifyglass.dylib` and `EeveeSpotify.dylib`
  hashes in the IPA equal the component-tree files; `pweevee-icon.png` in the IPA
  equals the committed hash-pinned asset.
- Integrations in the packaged tree checked by listing: `EeveeSpotify.bundle` present, 142 Eevee icon resource files staged during merge (`eevee_icons: 142` in manifest).

## Determinism statement

The pipeline is internally deterministic (ZIP-store writer verified by
build-tests' real two-write comparison; suite exit 0). A **claim of
"reproducible build" is NOT made** for this RC: reproducibility would require
two independent full builds compared byte-for-byte, and the shared build
manifest embeds timestamps. The suite-level determinism gates are the ones the
repository owns; `docs/comparison/roadmap.md` keeps the independent-verification
requirement.

## What this build does NOT prove

- No launch / runtime testing (no device, no simulator, no Mac).
- No re-compilation of any tweak (unified.sh stages pinned binaries).
- **Unsigned** output — signing/provisioning not verified without credentials.
