# PwEevee 3.1.0 — Pre-Publication Cleanup & Release Audit

Date: 2026-10-27
Scope: repository cleanup, branding, obsolete-IPA removal from active distribution paths,
artifact catalogue review, regression testing, and verification of the release candidate.
Nothing was published, pushed, tagged or committed.

---

## 1. Conclusion

The repository is ready for a manual 3.1.0 publication. Active user-facing surfaces now
carry consistent **PwEevee** branding, and the project front page (README) names the 3.1.0
release candidate as the artifact to publish, with no live download URL pretending it
already exists.

One deliberate limitation: the **generated website** still advertises the newest
*already-published* release (`v2.2.0-pre`), because the site is built from GitHub's release
API and a 3.1.0 asset URL can only exist after the user publishes. Faking that link would
ship a broken download, so it is left data-driven and documented instead (§5.1).

Every older IPA the repository still contains is either a declared historical release
asset that the project's own tooling treats as history, or a regression-test fixture, and
none of them is reachable from an active install path.

Two items are deliberately left in place because removing them would be wrong or unsafe:

1. **The tracked `Spotipw/` tree is the old-lineage source tree.** It still contains the
   `pweevee.skytweak.dpdns.org` update endpoint and the `spoti.pw` package identity. It is
   *not* the tree the shipped dylib is built from — it is retained as history and the
   project's own dylib guard fails any build made from it. See §7.1.
2. **The published 2.x releases and their assets** still exist on GitHub and are named by
   the generated release history. They are history, not active downloads. See §4.3.

The verified candidate is unchanged: 147,039,801 bytes,
`fd3f41e21b93a1585492c2a45112715dd9183c1f7b7370074e91866210f87dc2`.

---

## 2. Baseline established before any change

| Item | Value |
|---|---|
| Repository root | `/c/Users/sleepy/Documents/PwEevee` (Windows checkout; build host is the Mac) |
| Branch / remote | `master` → `github.com/codeboy2012/PwEevee` |
| Source tree of the shipped component | `taurus-rc/source` (migrated PwEevee product source), public version `taurus-rc/source/public-version.txt` = `3.1.0` |
| Non-build-lineage trees present | `Spotipw/` (tracked old-lineage source), `taurus-rc/*` (work/reports), `audit/`, `parallel-tmp/` |
| Build manifest | `release-candidate/build-manifest.json` |
| Candidate | `C:\Users\sleepy\Downloads\PwEevee-3.1.0.ipa` |

All work below was additive or in-place editing only. No `git reset --hard`, no
`git clean`, no mass deletion, no history rewrite, and the candidate IPA was only ever
read.

---

## 3. Old branding: what was found and how each active occurrence was handled

The legacy names are the product identifiers of the pre-migration lineage: **`spoti.pw` /
`SpoTi.pw` / `spotipw`** (product name), **`taurus` / `Taurus*`** (one earlier internal
line, still present as the `taurus-rc` working directory and in comparison documents), and
the **`pweevee.skytweak.dpdns.org`** legacy update endpoint.

| Location | Kind | Action |
|---|---|---|
| `README.md` — issue-report section | Active, user-facing | Replaced the obsolete product/build references with the current name and the current build-facts rule (counts unchanged; the page is generated from the current catalogue). |
| `README.md` — generated release block | Active, user-facing | Left data-driven (its generator already refuses to print a prerelease as stable). A note above it now states plainly that it names the last *published* generation until 3.1.0 is published (see §5.1). |
| `website-src/pages/compatibility.html` | Active, user-facing | Legacy-name paragraph removed. Pages forbid hard-coded version literals by design (enforced by `website-tests.pl`), so the notice was rewritten version-free and the exact build is named in the release notes instead. |
| `docs/installer/compatibility-matrix.md` | Active documentation | Same correction, consistent wording with the site. |
| `docs/TROUBLESHOOTING.md` | Active documentation | Corrected the issue path from the legacy internal build to the current component manifest. |
| `Spotipw/tweak/control`, `Spotipw/version.txt`, `Spotipw/tweak/Makefile` | Technical identity of a tracked historical tree | **Preserved.** `Package: com.spotipw` is the stable deb identity; renaming it would break upgrade paths and misrepresent a historical artifact. |
| `taurus-rc/**` (reports, work dirs, `v3.1.0-authoritative-build-report.md`, `v5/brand-remove/*`) | Historical build records, captured evidence | **Preserved verbatim.** These are the audit trail for the migration; editing them would falsify history. |
| `docs/comparison/*.md`, `docs/tweaks.md` | Comparison/audit documentation | **Preserved.** They name other projects (EeveeSpotify, Taurus) as comparison subjects — that is attribution, not PwEevee branding. |
| Upstream attribution (EeveeSpotify, Orion, CydiaSubstrate, Spotify assets), licences, copyright notices | Legally required | **Untouched.** |

Nothing was changed in `taurus-rc/source/**` (the build tree) as part of this cleanup, so
the shipped component's bytes and provenance are unaffected by the branding work.

---

## 4. Obsolete IPA artifacts and references

### 4.1 Inventory (as found)

| Artifact | Location | Class | Handling |
|---|---|---|---|
| `PwEevee-3.1.0.ipa` (candidate) | `C:\Users\sleepy\Downloads\` | The release candidate | Verified, never modified |
| `PwEevee-3.1.0.ipa` | `dist/PwEevee-3.1.0.ipa` (untracked, git-ignored via `dist/`) | Local copy of the candidate | **Byte-identical** to the delivered file (same SHA-256); **preserved** |
| `PwEevee-3.1.0.ipa` | `parallel-tmp/candidate/PwEevee-3.1.0.ipa` (untracked, git-ignored via `*.ipa`) | Working copy of the candidate | **Byte-identical**; **preserved** |
| `dist/pweevee-3.1.0-unified-Spotify-9.1.90-migrated.ipa` | local `dist/` (untracked build output) | Repackaging base for the candidate | **Preserved** — the candidate is derived from it |
| `dist/pweevee-3.1.0-unified-Spotify-9.1.90-crashfix.ipa` | local `dist/` | Superseded output (unsigned-dylib crash-fix build) | **Preserved**; the manifest now records why it was superseded |
| `audit/ipas/*.ipa` (0.22.0-alpha.2 etc.) | `audit/` scratch | Regression/forensic fixtures for the brand sweep and older-lineage comparison | **Preserved** as explicit test fixtures; documented in `audit/ipas/collect.sh` |
| `docs/spoti.pw-builds/` pristine upstream clone | tracked | Reference clone of the upstream builds repo | **Preserved** (reference only, never built from) |
| GitHub releases 2.x / 0.x and their assets | github.com | Published history | **Preserved** — deliberately not deleted |
| `website/data/releases.json` | generated | Full release catalogue (8 entries incl. 2.x) | **Preserved** — it is the history record used by the release explorer |

**No tracked `*.ipa` exists in the repository** (`git ls-files '*.ipa'` is empty) and no IPA is
staged for distribution, so nothing can be shipped as a release asset accidentally. The two
repository copies of the candidate are untracked, git-ignored local build/working files, and both
hash equal to the delivered artifact — verified, not assumed.

### 4.2 Active download references audited

| Surface | Finding | Action |
|---|---|---|
| Website hero / download button | Points at the newest **published** release (currently `v2.2.0-pre`) | No change needed; regenerating after publication moves it to 3.1.0, and the generator already labels that block's release and refuses to print a prerelease as stable (§5.1) |
| Website releases page | Renders the full history from `releases.json` | History display is intended; no obsolete primary target |
| `website/pweevee/apps.json` (AltStore/SideStore source) | Advertises `v2.2.0-pre` and one experimental entry | Tracked, regenerated by `.github/workflows/appsource-update.yml`, which fires on `release: published`. It will name 3.1.0 as soon as the user publishes. No fabricated URL added. |
| `dist/build-manifest.json` | Recorded `dist/PwEevee-3.1.0.ipa` as if it were the delivered artifact | **Corrected** — now records the delivered path and explicitly marks the release as pending manual publication |
| README install instructions | Reference the website + signing tools, not a pinned IPA filename | No change needed |
| CI workflows | Build/website/app-source jobs only; no workflow publishes an older IPA as current | No change needed |
| README front page (generated block + release section) | Presented the `v2.2.0-pre` notes and its live download links as the project's current release | **Corrected** (§5.1) |

### 4.3 Deliberately preserved history

- All GitHub releases and assets, including 2.x-era IPAs and the experimental watchfix build.
- `releases/metadata/` entries and `website/data/releases.json` (8 entries).
- Older-lineage comparison fixtures under `audit/`.
- The tracked `Spotipw/` source tree and every `taurus-rc/` report.

---

## 5. Making 3.1.0 the only active download target

Changes made:

1. **README release section replaced.** It previously reproduced the `v2.2.0-pre` release
   notes verbatim as the project's front page — including its 287 MB / `a76b469a…` unified
   IPA and three `releases/download/v2.2.0-pre/…` links. It now describes the 3.1.0 release
   candidate: status *built, packaged, validated offline, publication pending*, the real
   size and SHA-256, and an explicit statement that no release asset URL exists until the
   maintainer publishes. The previous generation is kept below it as history under its own
   heading, so nothing is promoted from it.
   The generated block above was left to its generator, which **already refuses to print a
   prerelease as the stable release** (`update-readme.pl`: prereleases are skipped and it
   dies rather than write one as stable). A note was added so nobody misreads that block
   as still describing the candidate.
2. **Retired repository slug removed from the site generator.** `render-site.pl`'s
   `own_repo_url` fell back to `codeboy2012/spoti.pw-builds` — GitHub redirects that slug,
   so the links worked and the stale name went unnoticed. It now falls back to the
   canonical `codeboy2012/PwEevee`. Every remaining `spoti.pw-builds` in the tree is a
   recorded historical document (`docs/BRANCH-AUDIT.md`, `docs/UNIFICATION-AUDIT.md`) or
   the optional local reference-clone path (`docs/spoti.pw-builds/`); the new suite
   enforces exactly that exemption list so it cannot silently grow.
3. **Compatibility documentation** states the limitation without pinning a version literal,
   so it cannot go stale on the next release.
4. **Build manifest** now declares `3.1.0` as pending publication and points at the
   delivered candidate, instead of implying a live downloadable artifact.

Consistent conventions confirmed: the release tag `v3.1.0`, the artifact filename
`PwEevee-3.1.0.ipa`, the manifest `spotipw_version`/`public_version` fields and the
source tree's `public-version.txt` all agree on `3.1.0`.

**Nothing was fabricated:** no GitHub release URL, asset URL or tag was created, and no
page claims 3.1.0 is downloadable today. The download surfaces move to 3.1.0 through the
existing publication workflow (`release: published`).

---

## 6. Catalogue / database finding

**There is no application-managed SQLite database or server-side artifact catalogue in
this project.** The task brief anticipated one; the actual architecture is
file-based:

| Catalogue | Managed by | Nature | Action |
|---|---|---|---|
| `website/data/releases.json` | `PwEvevee/build-system/release/update-releases.pl` | Generated from the GitHub releases API | Left to the generator; nothing hand-edited |
| `website/data/projects.json` | hand-maintained | Project metadata (name, tagline, upstream credit) | Audited: current branding, upstream credit preserved |
| `website/pweevee/apps.json` | `PwEvevee/build-system/release/update-appsource.pl` + workflow | AltStore source | Left to the workflow; verified it fires on publication |
| `dist/build-manifest.json` | build pipeline | Local build record | Corrected (see §5) |

So the "old IPA entries in a catalogue" risk reduces to generated files that are
regenerated from the published releases. The only stale-serving path found was the README
front page (which promoted the `v2.2.0-pre` build and its live links as current); the site
pages themselves faithfully describe whatever the release API returns. No database backup
was needed because no database exists — recorded here explicitly rather than assumed.

---

## 7. Files changed in this pass

| File | Reason |
|---|---|
| `README.md` | Release section replaced (2.2.0-pre notes + its live downloads → 3.1.0 candidate with pending-publication status); obsolete product/build reference in the issue section |
| `PwEvevee/build-system/release/render-site.pl` | `own_repo_url` retired-slug fallback → canonical `codeboy2012/PwEevee` |
| `website-src/pages/*.html`, `website-src/layout.html`, `website-src/assets/*` | Branding/notice pass (same session, earlier): legacy-name paragraph removed, notices made version-free, pages regenerated-ready |
| `website/**` | Regenerated site output of the above |
| `docs/TROUBLESHOOTING.md`, `docs/installer/compatibility-matrix.md`, `docs/DEVELOPMENT.md`, `docs/tweaks.md` | Obsolete product/build references corrected; component counts and wording brought current |
| `docs/ARCHITECTURE.md` | Stale test count corrected (`website-tests.pl` "469 checks" → the actual 4,396) |
| `PwEvevee/build-system/tests/prepublication-tests.pl` | **New**: regression coverage for stale branding/slug, candidate-hash agreement, no promoted superseded build, and app-source asset existence |
| `release-candidate/build-manifest.json` | Delivery path + explicit pending-publication status for 3.1.0 |
| `release-candidate/prepublication-audit-3.1.0.md` | This report |
| `release-candidate/progress-log-3.1.0.md` | Appended this pass (earlier entries untouched) |

Not touched by this cleanup pass: `PwEevee/components/**` (the dylib pin and manifest from the
build phase), `PwEevee/build-system/unified.sh`, `watch/watchfix.sh`, `lib/macho.pm`, and the
tracked `Spotipw/` tree — all pre-existing working-tree state, preserved as found.

New regression coverage (`prepublication-tests.pl`, 27 checks): no retired repository slug
in active surfaces (with a named, enforced exemption list); the README's candidate hash
equals the build manifest's; no superseded 2.x build is promoted above the
"previous generation" record; and every `Info.plist` fact in
`website/data/appsource-plists.json` still corresponds to an asset that exists. The suite's
own behaviour was validated with three negative controls (deliberately break each
condition → suite fails → restore byte-exact), scripted in
`parallel-tmp/prepub-negative-controls.py`.

---

## 8. Verification of the release candidate

| Check | Result |
|---|---|
| File exists at `C:\Users\sleepy\Downloads\PwEevee-3.1.0.ipa` | **yes** |
| Size | **147,039,801 bytes** |
| SHA-256 | `fd3f41e21b93a1585492c2a45112715dd9183c1f7b7370074e91866210f87dc2` |
| Matches the expected hash | **yes, byte for byte** |
| Embedded dylib vs the manifest pin | equal to `45242a9fffaf81f0da5b11883fd029a713ab1d980ac89c7ba8267ce5b54ceb24` |
| Rootless dependency edge | `@rpath/CydiaSubstrate.framework/CydiaSubstrate` (no absolute `/Library` path) |
| Component manifest vs embedded component | consistent (size, hash, guard markers, signature state) |
| Repository copies byte-identical to the delivered file | **yes** — `dist/PwEevee-3.1.0.ipa` and `parallel-tmp/candidate/PwEevee-3.1.0.ipa` both `fd3f41e2…f87dc2` (both untracked and git-ignored) |
| Candidate modified by this pass | **no** |

The candidate itself was not rebuilt, re-signed, repacked or substituted.

---

## 9. Tests run and outcomes

Full suite executed after the cleanup: **all 18 suites in `PwEvevee/build-system/tests/` exit 0**, with
no failures and four self-declared, environment-conditioned skips (detail below).

| Suite | Outcome |
|---|---|
| `embedded-artifact-test.pl` **run against the delivered candidate** (`PWEEVEE_IPA=…PwEevee-3.1.0.ipa PWEEVEE_IPA_HOST=1`) | **pass — 26 checks**, host binary inflated and checked |
| `component-manifest-test.pl`, `dylib-guard-test.pl` | pass (guard: 9 required markers present, 2 forbidden absent) |
| `website-tests.pl` (**4,396 checks**), `appsource-tests.pl` (118 checks), `brand-asset-tests.pl` | pass |
| `readme-updater-tests.pl` (29 checks) | pass |
| `plist-roundtrip-tests.pl`, `deb-format-test.pl`, `pweevee-deb-tests.pl` | pass |
| `alternate-icon-tests.pl`, `eevee-settings-tests.pl`, `pweevee-premium-exclusivity-tests.pl`, `pweevee-rebrand-tests.pl`, `readme-updater-tests.pl` | pass |
| `prepublication-tests.pl` (**new**, 27 checks) | pass |
| `build-tests.pl` | exit 0 — the Mach-O injector and plist-reader sections **skip**: they need the build *input* IPA `Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa`, which is not in the tree (large third-party binary, not kept) |
| `bundle-deps-tests.pl` | exit 0 — the `@rpath` resolution edge on the input IPA **skips** for the same reason |
| `pweevee-1.1.0-beta-tests.pl` | **documented self-declared skip** — the suite covers the 1.1.0-beta era and the superseded `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb` it needs is absent. Not weakened, not deleted |

Nothing was made green by weakening an assertion; no test was deleted. The two input-IPA skips
are environmental (missing build input), not regressions: the same suites report the same skip
whenever that input is absent, and the sections they skip are covered directly by the candidate
run of `embedded-artifact-test.pl` above.

---

## 10. Compatibility disclosure (unchanged and still visible)

On an **iPhone SE (2nd generation), iOS 17.8.1**, Spotify **login and signup currently
return a "Spotify server error."** The issue is acknowledged for a future update. Launch
success does not prove full compatibility. The release notes and the compatibility matrix
continue to state this; the version-free wording added in §3 preserves it across releases.

---

## 11. Open items for the user's review

1. **Tracked `Spotipw/` tree = old lineage.** It still contains
   `SGTUpdateURL = https://pweevee.skytweak.dpdns.org/api/update` and the `spoti.pw`
   package identity. This is *not* the tree the shipped dylib is built from (that is
   `taurus-rc/source`), and `dylib-guard-test.pl` fails any build made from it. Left
   untouched deliberately: deleting or rewriting a tracked historical tree is the user's
   call, not a cleanup step. Flagged so it cannot be mistaken for the build source.
2. **App source names an experimental entry** ("PwEevee (watchfix experimental)",
   `com.skywatch.spotify`) alongside the main app. It corresponds to a real published
   build, so it was not removed; worth a naming decision at publication time.
3. **Signing/installability** remain as documented in the earlier reports: the IPA is not
   re-signed end to end, the sideloader re-signs at install, and Developer Mode is
   required for that installation path (see `developer-mode-audit-3.1.0.md`).
4. **No physical-device verification** of this candidate: install, launch, runtime and the
   Spotify login limitation are unverified on hardware from this environment.

---

## 12. Manual publication steps still required

1. Review the cleanup diff and this report.
2. Commit and push to `master` (staging only the files listed in §7).
3. Create the GitHub release for tag `v3.1.0` and upload `PwEevee-3.1.0.ipa`
   (SHA-256 `fd3f41e2…f87dc2`).
4. Let the existing workflows run (`update-releases` then `appsource-update`), or run
   `scripts/update-releases.sh` locally, then regenerate and deploy `website/`.
5. Confirm the hero/download target now names 3.1.0 and the compatibility disclosure is
   visible.

Nothing above was executed by this pass.
