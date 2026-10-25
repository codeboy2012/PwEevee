# PwEevee integration architecture

## One diagram, three layers

```
            ┌───────────────────────── Spotify iOS app (side-loaded IPA) ─────────────────────┐
            │                                                                                │
            │   spotifyglass.dylib  ── the Chroma/SpoTi.pw-derived tweak (SG* world)          │
            │     ├── Core/       logging, rebind hooking (imports), flag forces, UI mode    │
            │     ├── Headers/    reverse-engineered Spotify class headers, only used sel.   │
            │     ├── Settings/   SGPage/SGModPage framework (switches, choices, sliders)    │
            │     ├── Shared/     flags, privacy, lyrics engine+sources, audio effects,      │
            │     │               haptics, Live Activity state, gestures, artist block,      │
            │     │               AdBlock, premium-spoof exclusivity                         │
            │     ├── Native/     Spotify's own screens (iOS <26 active look)                │
            │     ├── Redesigned/ Liquid Glass redesign (iOS 26+, `UIGlassEffect`)           │
            │     └── App/        Mod Settings root, Eevee page, backup, signing, tour       │
            │                                                                                │
            │   EeveeSpotify.dylib  ── upstream EeveeSpotify (6.6.8 / 7.0.0, unmodified)      │
            │     └── Orion.framework + EeveeSwiftProtobuf.framework (its dependencies)      │
            │                                                                                │
            │   SpotifyGlassAppGroups.dylib ── moves App Groups so the home-screen widget     │
            │                                  works on a re-signed IPA                      │
            │   SpotifyGlassLiveActivity.appex ── the Live Activity widget extension         │
            │                                                                                │
            │   CydiaSubstrate.framework ── present historically; Chroma-derived tweak        │
            │                                swizzles at runtime (see provenance doc)        │
            └────────────────────────────────────────────────────────────────────────────────┘

  Layer import rule (enforced by scripts/check-layers.sh before every build):
      Core ← Settings ← Shared ← Native | Redesigned ← App      (one-way only)
```

Key property: **the two looks never run together.** `Native/` and `Redesigned/`
each hook the same Spotify classes under their own names; what both need passes
through Core registries (`SGFlagForce`, `SGOpenModSettings`). The redesign is
gated behind `SGRedesignAvailable()` (iOS 26+), so an older phone keeps the native
look automatically and the stored key survives an OS update.

## Eevee integration (no fork of the fork)

PwEevee does **not** rewrite EeveeSpotify. The Eevee page
(`Spotipw/tweak/Sources/App/Eevee/SGEevee.x`) hosts upstream rows verbatim:

- reads Eevee's own stored settings (`UserDefaults+Extension` upstream model),
- takes the standalone Eevee row the payload injects above Spotify's settings list
  **out** and re-homes it inside Mod Settings, so there is exactly one settings
  surface and one injection domain,
- keeps Eevee's premium-spoof row mutually exclusive with the SpoTi.pw spoof row —
  both-on resolves deterministically (`SGPremiumResolveConflict`; 47-check suite).

Duplicated-target check: in the deb both `spotifyglass.plist` and
`EeveeSpotify.plist` filter `com.spotify.client`; that is two *of* the same dylibs
tweaking one process by design, not a double-injection of one dylib. The binary
plists/manifests are hash-pinned so drift fails the manifest test.

## Packaging flow (deterministic, hash-pinned)

```
source-artifact deb/IPA copies  ── extract-components.pl ──►  components/* + manifests (sha256+size pins)
        │
stats:  dependencies.json (one provider per component; duplicate policy:
        identical = collapse+log, different = hard fail)
        │
unified.sh  (the one build entrypoint)
  ├─ component manifest verify (component-manifest-test.pl walking every pin)   [hard]
  ├─ stage Payload/Spotify.app
  ├─ patch-alternate-icon.pl   [hard step, idempotent]
  │     verify brand-icons/manifest.json sha256+size → stage pweevee-icon.png
  │     register CFBundleIcons.CFBundleAlternateIcons["PwEevee"]
  │     mirror into CFBundleIcons~ipad only when the host declares that dict
  ├─ validate-macho.pl         (load commands: expected strong set, duplicates, every
  │                             @executable_path reference exists)
  ├─ validate-ipa.pl           (no nested .app, no watch leftovers unless --watch, no
  │                             dev junk, no duplicate dylib/framework names, missing
  │                             critical files, referenced alternate icons exist)  [hard]
  ├─ inject-dylib.pl           (zero-padding in-place; refuses non-64-bit and non-zero slack)
  └─ make-ipa.pl / make-deb.pl (store-only ZIP, fixed DOS timestamps, canonical
                                bplist writer → byte-deterministic output)
```

Error posture: every hard step **dies before writing anything** when its input is
wrong — the icon patcher verifies the manifest hash *before* staging the file, and
`validate-ipa.pl` fails the run with a named, per-icon file error
(`ALTERNATE ICON MISSING: <provider>/<file>`) rather than letting a referenced
asset silently fall back to the primary icon.

The 1.1.0-beta unified deb deliberately does **not** ship CydiaSubstrate (Chroma-
derived code swizzles at runtime; Eevee gets Substrate via MobileSubstrate/ElleKit
at runtime) — see `licensing-and-provenance.md` for the artifact-vs-pin status.

## Update checker design (`Spotipw/tweak/Sources/App/About/Update.m`)

```
   app start / About page ──► POST pweevee.skytweak.dpdns.org/api/update   (project-owned,
                              usage body only when the user opted in)
          ├─ 200 + releases ► parse, filter drafts/pre-releases for "countable" state
          └─ any failure    ▼
                              GET https://api.github.com/repos/codeboy2012/PwEevee/releases?per_page=20
                              (official PwEevee repo; 20 releases in one request)
                                     └─ cache + rate-limit handling; last-told state in defaults
```

Guarantees enforced by `pweevee-rebrand-tests.pl` (passing, 30 checks):
- the GitHub fallback endpoint is the PwEevee repo, and
- **no upstream project's release endpoint** appears in the code (PwEevee's update
  delivery is independent of Chroma's, Taurus's and Eevee's checkers),
- changelog lines keep link text and strip upstream markdown to a commit link,
- drafts/pre-releases never count as "newest" for the user.

## Test architecture

13 suites, pure Perl, exit-code honest (see `test-report.md`):

| Verifying | Suites |
|---|---|
| plist correctness | plist-roundtrip, (build-tests plist section) |
| icon pipeline | alternate-icon, brand-asset |
| artifact pins | component-manifest |
| packaging | deb-format, pweevee-deb, build-tests (ZIP determinism) |
| product behavior (static) | premium-exclusivity, eevee-settings |
| web + docs + rebrand | website-tests, readme-updater, pweevee-rebrand |
| built-artifact gate | pweevee-1.1.0-beta (environmental skip: needs `dist/…deb`) |
