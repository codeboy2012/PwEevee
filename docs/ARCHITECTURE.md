# Architecture

The repository is organised around **components** and **one authoritative pipeline**, not
finished IPA blobs.

```
┌────────────────────────────────────────────────────────────────────┐
│ UPSTREAM (not part of this repo — credited, never claimed as ours) │
│   spoti.pw (skopevoj) · EeveeSpotify (Eevee / jaydenjcpy packaging)│
│   Spotify 9.1.84 decrypted IPA (the build's input artefact)        │
└────────────────────────────────────────────────────────────────────┘
                            │
   Evevee Spotify/         ▼            PwEvevee/build-system/
┌──────────────────────────────────┐   ┌──────────────────────────────┐
│ component/  eevee dylib + frames │   │ unified.sh  THE pipeline     │
│   bundle, 142 icons, MS pair,   │──▶│ prepare → merge → resolve →  │
│   spotipw tweak dylib + filter  │   │ inject → validate → package  │
│ shared: CydiaSubstrate + policy │   │ → manifest → tests           │
└──────────────────────────────────┘   └──────────────┬───────────────┘
                                       ┌──────────────▼───────────────┐
                                       │ dist/  build-manifest.json   │
                                       │ releases/ current · metadata │
                                       │ website/  static site        │
                                       └──────────────────────────────┘
```

## Directory map

| Path | What it is |
|---|---|
| `Spotipw/` | the upstream spoti.pw project kept intact under its own identity: `tweak/` (theos tweak source), `extension/`, `harness/`, `vendor/`, `scripts/`, `ipa/`, Makefile, LICENSE, upstream docs and release tooling |
| `taurus-rc/source/` | the migrated PwEevee product source that produced the shipped `spotifyglass.dylib`, Safari extension and Downloads engine: Theos tweak sources, extension, tools, tests and build configuration. Its public version is `public-version.txt`; the inherited upstream line is `version.txt`. |
| `Evevee Spotify/component/` | Eevee payload from the self-contained deb: `package/dynamic-libraries/EeveeSpotify.dylib` (+ plist filter), `frameworks/{Orion,EeveeSwiftProtobuf}.framework`, `bundles/EeveeSpotify.bundle`, `resources/` (142 icon PNGs), `manifest.json` with per-file SHA-256 |
| `Evevee Spotify/component/extract-components.pl` | rebuilds `Evevee Spotify/component/` and `PwEvevee/components/spotipw/` from `Evevee Spotify/source-artifacts/` |
| `Evevee Spotify/source-artifacts/` | audited binary inputs (debs/IPAs) + legacy Perl tools |
| `PwEvevee/components/spotipw/` | the spoti.pw tweak payload: `dylibs/spotifyglass.dylib`, MobileSubstrate filter in `package/dynamic-libraries/`, `manifest.json` with per-file SHA-256 and origin deb hash |
| `PwEvevee/shared-dependencies/cydiasubstrate/` | shared CydiaSubstrate.framework + provenance manifest |
| `PwEvevee/dependencies.json` | the single source of truth for shared deps, load commands and duplicate policy |
| `PwEvevee/build-system/unified.sh` | the one authoritative build command |
| `PwEvevee/build-system/inject/inject-dylib.pl` | LC_LOAD_DYLIB injector (mirrors the proven upstream logic) |
| `PwEvevee/build-system/lib/macho.pm`, `PwEvevee/build-system/lib/zip.pm` | Mach-O parser and deterministic store-only ZIP writer |
| `PwEvevee/build-system/package/make-ipa.pl` | deterministic IPA packager with self-check |
| `PwEvevee/build-system/package/make-deb.pl` | byte-exact .deb generator (ar + ustar + LZMA), no post-patching |
| `PwEvevee/build-system/package/resolve-deps.pl` | dependency resolver; duplicates fail the build |
| `PwEvevee/build-system/validate/validate-macho.pl`, `PwEvevee/build-system/validate/validate-ipa.pl` | binary and filesystem validation |
| `PwEvevee/build-system/tests/` | automated tests: `deb-format-test.pl` (30 checks), `build-tests.pl` (14 checks), `website-tests.pl` (4,396 checks) |
| `PwEvevee/build-system/release/make-release.pl` | release registration + 6-month retention sweep + index.json |
| `PwEvevee/build-system/release/update-releases.pl` | fetches the newest published GitHub release per project → `website/data/releases.json` |
| `PwEvevee/build-system/release/render-site.pl` | renders the whole website from `website-src/` + the generated data |
| `PwEvevee/build-system/release/make-social-card.pl` | regenerates the Open Graph image in pure Perl |
| `PwEvevee/build-system/release/lib/PwSite.pm` | shared helpers: JSON, escaping, formatting, release-note sanitiser |
| `scripts/` | shared tooling (`macho-dump.pl`, `deb-tree.pl`), `dev-server.pl` preview, `update-releases.sh` one-command site refresh |
| `website-src/` | website source: `layout.html` + `pages/*.html` (the site is generated from these) |
| `website/` | the generated website (see below) |
| `releases/` | `current/` (downloadable), `metadata/` (kept forever), `archive/` |
| `dist/` | build outputs + `build-manifest.json` |
| `docs/` | project documentation (architecture, build, troubleshooting, development) |
| `docs/spoti.pw-builds/` | *optional, not part of the repository* — a local pristine git clone of the upstream builds repo, useful as a reference when tracing payloads. The gitlink entry was dropped in `43a92ce`, so a fresh clone of this repository does not contain it. |

## The pipeline (PwEvevee/build-system/unified.sh)

1. **clean** — `PwEvevee/build-system/_work/` wiped; no stale output can leak into a build
2. **prepare** — input IPA unzipped; Spotify version read from Info.plist
3. **merge** — component payloads copied into `Payload/Spotify.app/`:
   `spotifyglass.dylib` + `EeveeSpotify.dylib` → `Frameworks/`, Orion +
   EeveeSwiftProtobuf + CydiaSubstrate frameworks, `EeveeSpotify.bundle/`, 142 icon
   PNGs at the app root
4. **resolve** — every shared dependency must exist exactly once; same-name different-bytes
   is a hard failure naming both suppliers (message template in `PwEvevee/dependencies.json`)
5. **inject** — five LC_LOAD_DYLIB commands written into the padding after the load
   commands of the main executable; idempotent; refuses non-zero padding
6. **validate Mach-O** — expected commands present exactly once, no duplicate commands,
   every `@executable_path` dependency exists in the staged app
7. **validate filesystem** — no nested .app, no Watch app, no dev junk, no duplicate
   dylibs/frameworks, critical files present
8. **package** — store-only ZIP, fixed timestamps, stable order → byte-reproducible
9. **manifest** — `dist/build-manifest.json` with versions, SHA-256, sizes, validation flags
10. **tests** — deb format + build tests run as part of every build

## Injection contract (byte-audited)

The injected executable must carry exactly these commands, matching the proven
`com.spotipw_0.22.0.ipa` binary (ncmds 153, sizeofcmds 16680):

```
@executable_path/Frameworks/spotifyglass.dylib
@executable_path/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf
@executable_path/Frameworks/Orion.framework/Orion
@executable_path/Frameworks/EeveeSpotify.dylib
@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
```

A clean 9.1.84 binary has ncmds 148; each injected command adds 1. Slack check: the
input binary has ~131 KB of zero padding after the load commands; each command needs
~72 bytes.

## Eevee resource model (why the icons now show)

From the audit (docs/UNIFICATION-AUDIT.md §3): Eevee's BundleHelper searches
1. `<home>/Library/Application Support/EeveeSpotify.bundle` (jailbreak layout), then
2. `Spotify.app/EeveeSpotify.bundle` (main-bundle fallback).

The working IPA proves fallback 2 is what ships. The earlier "icons missing" build was
missing the 142 icon PNGs at the app root and/or the bundle content — not a different
directory. The resolver now fails the build if either is absent, and supports the
Application Support copy as an optional flag for parity with the jailbreak layout.

## Website architecture

```
website/data/projects.json     hand-authored project facts + GitHub coordinates
        │                      (no versions, ever)
        ▼
update-releases.pl ──► GitHub REST API ──► website/data/releases.json
                                                    │
releases/index.json (make-release.pl) ──────────────┤
                                                    ▼
website-src/layout.html + pages/*.html ──► render-site.pl ──► website/**/index.html
```

- **Static, framework-free, zero dependencies.** Every page is fully rendered at publish
  time, so all release information is present with JavaScript disabled. Deployable to any
  static server; `website/nginx.conf.example` is the reference config.
- **Generated, not hand-written.** `website/` is output. Pages are edited in
  `website-src/`; `[[component:name]]` placeholders pull in generated content. Re-running
  the renderer is idempotent.
- **One source per fact.** Repositories, authors and licenses live once in
  `projects.json`; build versions and checksums come from `releases/index.json`; upstream
  versions, dates, assets and notes come from `releases.json`. No version number is typed
  into a page, and `website-tests.pl` fails the build if one is.
- **Routes** — `/`, `/downloads`, `/releases`, `/projects`, `/projects/{pweevee,spotipw,eeveespotify}`,
  `/credits`, `/development`, `/legal`, `/contact`, plus `404.html`. Canonical URL
  `https://pweevee.skytweak.dpdns.org/`; the alternate path `skytweak.dpdns.org/pweevee`
  must 301 to it (single indexed site).
- **Downloads** resolve to a published release asset and nothing else. The site hosts no
  IPA of its own: PwEevee's download is the release's canonical `PwEevee-X.Y.Z[-nightly|-alpha].ipa`
  asset (validated by name and channel in one shared module, `PwArtifact.pm`), and the
  EeveeSpotify IPA variants come from the SideloadLabs AltSource, labelled as such. A
  release that ships only the clean Spotify base has no PwEevee download, and the page
  says which artifact is missing instead of linking the wrong IPA. A button is only
  rendered when the asset exists in the generated data and its URL passes the safe-URL
  check; otherwise the page shows an explanatory state and a GitHub link, never a dead
  button.
- **No token in the browser.** The GitHub API is only ever called server-side by
  `update-releases.pl`. `assets/pweevee.js` reads the generated same-origin JSON and
  nothing else — it sends no credentials and contacts no third party.
- **Untrusted upstream content.** Release notes are HTML-escaped first and only then
  given a fixed, tiny set of block structures (`PwSite::notes_to_html`), so upstream text
  can never introduce markup. Asset URLs are validated to be https on a GitHub host.
- **Degradation** — if `releases.json` is missing the pages render an explanatory state;
  if GitHub was unreachable during the last update the previous known-good release is
  shown with a `stale` badge rather than being dropped.
- **One implementation.** `website-src/` is the only place templates, CSS and JS are
  edited: `layout.html`, `pages/*.html` and `assets/*`. `render-site.pl` renders the pages
  and copies the assets into `website/`, which is build output and is never hand-
  maintained. The only files that exist solely in `website/` are the ones the other build
  scripts generate there: `data/*.json`, `assets/brand/`, the derived icon sizes and the
  social card.
- **Design system** — one stylesheet (`website-src/assets/pweevee.css`): an editorial
  system of flat surfaces, hairline rules and one ink, with the blue sampled from the
  official logo artwork (`#2A3762`, lifted to `#90A0D5` on dark) as a small accent. No
  gradients, no backdrop blur, no glow. Some regions take the dark set whatever the theme
  is — the footer, and one band on the home page — and those are the only places the
  falling-star canvas appears. Motion is disabled wholesale under
  `prefers-reduced-motion`, where the star field is removed rather than slowed. No
  third-party CSS, fonts or scripts, which is why the nginx example can ship a strict
  Content-Security-Policy with no `unsafe-inline`.
- **Themes** — two intentional sets, not one inverted. **Dark is the default**: the bare
  `:root` block carries it, so it applies with no media query and no JavaScript.
  `prefers-color-scheme: light` switches to the light set, and `html[data-theme="light"|
  "dark"]` overrides both (an attribute selector outranks `:root`, so no `!important`).
  Components only ever read the semantic tokens — a test fails the build if one reaches
  into `--l-*` or `--d-*` directly.

  The visible control offers **System / Light / Dark**. An explicit choice is stored in
  `localStorage` and applied by `assets/theme.js`, a ~2KB blocking script in `<head>`,
  which is what prevents a flash of the other theme; choosing System clears the key and
  returns to the device preference. It is an external same-origin file rather than an
  inline snippet precisely so the strict CSP still holds. With JavaScript off the control
  is hidden and the theme still follows `prefers-color-scheme`.
- **Attribution boundary** — for each upstream project the data model separates the
  upstream authors from PwEevee's own work (`pweevee_work` in `projects.json`), and the
  EeveeSpotify page renders the two in separate sections. Upstream credit is never
  removed; PwEevee's integration, unified packaging, validation and distribution are
  never presented as upstream's.

## Import/reference policy

`docs/spoti.pw-builds/` is an optional local pristine clone (git metadata intact),
**not a tracked path**: it was added as a gitlink in `fa025a3` and removed in
`43a92ce`, so it is absent from a fresh clone. When a maintainer keeps one locally it is
never edited, never built from, and never pushed to; it exists so integrated payloads can
be traced back to the exact upstream tree they came from. Nothing in the build depends on
it — the pinned components and their per-file SHA-256 manifests are in `PwEvevee/`.
