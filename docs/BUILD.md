# Build

Everything needed to reproduce a unified PwEevee IPA from a decrypted Spotify IPA.

## Requirements

| Tool | Used for | Notes |
|---|---|---|
| bash | `PwEvevee/build-system/unified.sh` | Git Bash on Windows works |
| perl 5.26+ | all tooling | core modules only + `JSON::PP`, `Digest::SHA`, `Compress::Zlib` (all core) |
| xz | LZMA member of the deb generator | `apt install xz` / `brew install xz` / MSYS2 ships it |
| unzip | input IPA extraction | |
| (optional) git | commit hash in the manifest | |

No Theos, no Xcode, no macOS, no cyan, no dpkg-deb, no Python. Everything runs on the
audited component payloads committed under `PwEvevee/components/` and
`Evevee Spotify/component/`.

One-time, if `components/` is missing or `--force` is wanted:

```bash
perl "Evevee Spotify/component/extract-components.pl" --force
```

This rebuilds both components from `Evevee Spotify/source-artifacts/` and writes their manifests. It is
deterministic; re-running changes nothing.

## The build

```bash
bash PwEvevee/build-system/unified.sh <decrypted Spotify 9.1.84 .ipa> [-o dist/<name>.ipa]
```

The pipeline: clean → prepare → merge components → resolve dependencies → inject 5 load
commands → validate Mach-O → validate filesystem → package deterministic IPA → write
`dist/build-manifest.json` → run tests. Any failure stops the build with a named error
(e.g. `DUPLICATE DEPENDENCY: CydiaSubstrate.framework supplied by X and Y`).

The verified test build in this repository was produced with:

```bash
bash PwEvevee/build-system/unified.sh "Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa" -o dist/pweevee-test.ipa
```

Input used: a decrypted Spotify **9.1.84** IPA with the Watch app already removed and no
modifications (ncmds 148, no existing injection). The input IPA itself is **not** committed
(`.gitignore` excludes `*.ipa`); any equivalent decrypted 9.1.84 IPA works.

## Tests

```bash
perl PwEvevee/build-system/tests/deb-format-test.pl   # 30 checks: ar magic/names/order/offsets/sizes/modes/terminators/tar/lzma
perl PwEvevee/build-system/tests/build-tests.pl       # 14 checks: zip determinism + roundtrip + unzip compat, injector idempotence, plist reader
```

Both run automatically at the end of every `unified.sh` run. Tests are never weakened to
make a build pass; failures are diagnosed and fixed.

## Verifying a build by hand

```bash
# load commands of the packaged executable (expect ncmds 153 and the 5 commands)
unzip -p dist/pweevee-test.ipa Payload/Spotify.app/Spotify > /tmp/exe
perl scripts/macho-dump.pl /tmp/exe | grep -E 'spotifyglass|Eevee|Orion|Substrate'

# Eevee resources present
unzip -l dist/pweevee-test.ipa | grep -c 'EeveeSpotify.bundle'   # 58 entries
unzip -l dist/pweevee-test.ipa | grep -cE 'Payload/Spotify.app/[^/]+\.png'

# determinism: rebuild and compare
bash PwEvevee/build-system/unified.sh <input.ipa> -o dist/rebuild.ipa
sha256sum dist/pweevee-test.ipa dist/rebuild.ipa   # identical except manifest timestamps inside
```

The deb generator is byte-exact against the upstream reference:

```bash
perl PwEvevee/build-system/tests/deb-format-test.pl    # includes roundtrip through xz + the legacy deb_tree.pl reader
```

## Reproducibility

- the ZIP writer uses store-only entries with fixed 1980 timestamps and caller-supplied order
- the deb writer uses a fixed mtime (`DEB_MTIME`, default 1750000000) and fixed-width ustar fields
- component extraction is deterministic and verified by per-file SHA-256 in each manifest
- the only nondeterministic bytes in an IPA are the ones you put in (the input IPA and,
  if enabled later, signing — which always happens after the build)

## Signing

The build output is unsigned. Sign with your own certificate (SideStore, Feather,
AltStore, Sideloadly…). Keep Spotify's bundle id unless your signer handles the
application-identifier entitlement correctly — see the upstream spoti.pw README's
signing notes, which apply here too.

## Publishing (manual, never automatic)

```bash
perl PwEvevee/build-system/release/make-release.pl dist/<name>.ipa dist/build-manifest.json \
     --githash "$(git rev-parse --short HEAD)"
scripts/update-releases.sh          # GitHub release data + render + checks
```

`make-release.pl` copies the IPA into `releases/current/`, writes a release card into
`releases/metadata/`, sweeps releases older than `WEBSITE_IPA_RETENTION_MONTHS` (6),
and regenerates `releases/index.json`.

`scripts/update-releases.sh` then runs the four website steps in order:

1. `release/update-releases.pl` — queries the GitHub API for the newest **published**
   release of every project declared in `website/data/projects.json` and writes
   `website/data/releases.json`. Drafts are never used; PwEevee's stable channel is strict
   (a prerelease never becomes "latest"), while an upstream project with no stable release
   may still show its newest prerelease. A PwEevee download must be the release's own
   canonical `PwEevee-X.Y.Z.ipa` (or `-nightly` / `-alpha`) asset — never the first `.ipa`
   and never the clean Spotify base that ships beside it. A release without that asset is
   recorded as `artifact_missing` and no download is offered. If GitHub cannot be reached,
   the previous known-good entry is kept and flagged `stale` rather than being replaced
   with nothing.
2. `release/update-altsource.pl` — reads every AltStore-format source declared under a
   project's `altsource` key and writes `website/data/altsource.json`. Currently that is
   the SideloadLabs source, which publishes the installable EeveeSpotify IPA variants.
   Each app is parsed into a variant — family, Standard/Patched, Spotify version,
   EeveeSpotify version, size, date, download URL — rather than dumped through verbatim.
3. `release/render-site.pl` — renders every page of `website/` from `website-src/` using
   those two data files. **It hosts nothing:** a download button is rendered only when a
   real release asset or variant URL exists, and otherwise the page shows
   "Download currently unavailable" plus a link to the release on GitHub.
4. `tests/website-tests.pl` — checks the result: data shape, no secrets, every route,
   every internal link, every download target, project-name casing, the release filter,
   the absence of any locally hosted build, accessibility basics and the pre-redesign
   URLs.

GitHub and the AltSource are kept conceptually separate all the way through: separate
generators, separate data files, separate components, and labelled separately on the
page. Neither is ever presented as the other.

Run the data steps on their own with `--no-render --no-test`, skip the AltSource with
`--no-altsource`, or re-render from existing data without touching the network with
`--offline`.

Set `GITHUB_TOKEN` to raise the API rate limit. It is handed to curl through a 0600
config file, is never written into the generated data, and never reaches the browser.

Nothing is uploaded anywhere by these commands; hosting is a separate manual step.

## Website source layout

The site is generated, so pages are edited in `website-src/`, never in `website/`:

| Path | Purpose |
|---|---|
| `website-src/layout.html` | the page shell: head, metadata, nav, footer, icon sprite |
| `website-src/pages/*.html` | page content; a `<!--PwEevee … -->` block gives route, title and description, and `[[component:name]]` placeholders pull in generated content |
| `website/data/projects.json` | project facts, GitHub coordinates and AltSource declarations — **no versions** |
| `website/data/releases.json` | generated GitHub release data (all three projects) |
| `website/data/altsource.json` | generated AltSource variant data (EeveeSpotify) |
| `website-src/assets/pweevee.css` | the whole design system, both themes, one request |
| `website-src/assets/theme.js` | applies a stored theme override before the first paint; blocking, in `<head>` |
| `website-src/assets/pweevee.js` | progressive enhancement only; every page works without it |
| `website-src/assets/favicon.svg` | the fallback mark, used only if the derived icon sizes are missing |

`theme.js` must stay blocking and must stay ahead of the stylesheet in `<head>`. Deferring
it, or folding it into `pweevee.js`, reintroduces a flash of the wrong theme for anyone
whose stored choice disagrees with their device. `website-tests.pl` fails on both mistakes.

`render-site.pl` copies `website-src/assets/*` into `website/assets/` on every run, so the
served stylesheet and script are build output. Editing `website/assets/pweevee.css`
directly is always wrong: the next render overwrites it.

`release/make-social-card.pl` regenerates `website/assets/social-card.png` (the Open
Graph image) in pure Perl if the artwork ever needs to change. It composites the logo into
the same framed composition the hero uses, so a link preview matches the page.

## Brand artwork

The hero presents the artwork as what it is — an app icon in a square frame. Drop the
artwork in as a **square image**; a transparent background is fine, and so is artwork that
carries its own background, as the official logo does:

```
website/assets/brand/pweevee-logo.png        # the official logo — hero, cards, icons
website/assets/brand/spotipw-logo.png        # optional, used on the spoti.pw card + page
website/assets/brand/eeveespotify-logo.png   # optional, same for EeveeSpotify
```

`<slug>-logo.<ext>` is the canonical name; a bare `<slug>.<ext>` is still accepted as a
fallback. Candidates are checked in that order, by exact name — the folder is never
globbed, so a stray file cannot be picked up as brand artwork.

After adding or replacing the logo, derive the icon sizes and rebuild:

```bash
perl PwEvevee/build-system/release/make-brand-assets.pl   # icon-32/180/512
perl PwEvevee/build-system/release/make-social-card.pl    # Open Graph image
perl PwEvevee/build-system/release/render-site.pl
```

`make-brand-assets.pl` **downscales only** — it never recolours, crops or redraws the
artwork. Alpha is premultiplied during the box-average so the rounded corners stay clean.
The small sizes exist because a favicon slot needs a small raster; everywhere size does
not matter (hero, project cards, project pages) the site references the original file.

`render-site.pl` warns if the logo is newer than the derived icons, and
`website-tests.pl` fails if any surface regresses to a placeholder glyph or the
superseded SVG mark.

`.png`, `.webp`, `.svg` and `.jpg` are all accepted; the first match wins. Then re-run
`render-site.pl`.

The renderer only ever *places* artwork — it never recolours, crops or stretches it
(`object-fit: contain` inside a square box). All the CSS adds is the frame: a square box,
a hairline border and a caption. There is no bloom, plinth, floor ring, mirrored
reflection or speck layer, so what you see is the file you supplied.

With no artwork present the hero falls back to an original stand-in mark and the site
still renders completely; `website-tests.pl` prints which mode is in use.

If the logo is present, `make-social-card.pl` composites it into the Open Graph image as
well, using the shared PNG reader in `release/lib/PwPng.pm` (8-bit RGB/RGBA,
non-interlaced). Otherwise it draws the original sphere-and-chevron mark that matches
`website/assets/favicon.svg`, which is also the renderer's icon fallback when the derived
sizes are missing.

`release/make-app-icon.pl` predates the official logo and generates its own icon into
`website/assets/brand/`. It is no longer the source of brand artwork: `pweevee-logo.png`
takes precedence over anything it writes.
