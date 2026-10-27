# PwEevee 3.1.0 — persistent progress log

Updated: 2026-10-27 (session: resume build, produce and validate a real IPA)

## Checklist

- [x] **P1 Provenance** — crash-fix dylib `5efc…`, release-qual `60ef…`, deb/component `9475…` and a
      fresh rebuild all share byte-identical `__TEXT`/`__DATA_CONST`/`__DATA` sections; only
      UUID, `__LINKEDIT` accounting, and the code-signature blob differ.
- [x] **P2 Binary questions** — the `0x1109–0x111a` differences are the `LC_SEGMENT_64(__LINKEDIT)`
      `vmsize`/`filesize` fields; `0x22c8–0x22d5` is the `LC_CODE_SIGNATURE` command itself.
      Chained-fixups and exports-trie commands are byte-identical. `.unsigned` is a real signing
      defect (CodeDirectory flags=0, no CMS slot, codesign: "no signature"), not a label.
- [x] **P3 Signing/packaging** — Theos signs via a local `ldid` shim that maps to
      `codesign -f -s -` (ad-hoc). `9475…` is the deb artefact signed by real `ldid`
      (its `.unsigned` intermediate name stuck as the identifier); `60ef…`/fresh are the
      ad-hoc **codesign-valid** outputs of the same Theos "Signing spotifyglass" step.
- [x] **P4 Component choice** — fresh clean rebuild (`45242a9f…`) from the confirmed
      `/Users/xcode/pweevee-3.1.0-src` tree; codesign-verified, guard markers present,
      `@rpath` Substrate. Pinned in both trees.
- [x] **P5 Candidate IPA** — built on the Mac from the validated migrated baseline + the pinned signed
      dylib (single-member swap, deflate repack): `fd3f41e21b93a1585492c2a45112715dd9183c1f7b7370074e91866210f87dc2`,
      147,039,801 bytes, 1,193 members.
- [x] **P6 IPA-level validation** — embedded dylib byte-identical to the pin, `codesign --verify` valid,
      `@rpath` Substrate, guard markers pass; repo validators PASSED (scoped 227 edges, `--strict-all`
      483 edges, Mach-O 15 checks, structure); absolute `/Library` sweep clean.
- [x] **P7 Regression test** — `PwEvevee/build-system/tests/embedded-artifact-test.pl` added (23 checks;
      26 with `PWEEVEE_IPA_HOST=1`), proven to FAIL on the crash-fix IPA (6) and the migrated baseline
      (8). Full suite: all 17 suites exit 0.
- [x] **P8 Hang + stale beta test** — no provable main-thread hang (see the final report §6); no
      speculative runtime change. The 1.1.0-beta suite was repaired to skip when its superseded,
      git-ignored artifact is absent (51/51 still pass on the archived deb).
- [x] **P9 Delivery** — `C:\Users\sleepy\Downloads\PwEevee-3.1.0.ipa` written and SHA-256-verified
      against the Mac-built artifact (byte-identical, 147,039,801 bytes).
- [x] **P10 Final report** — `release-candidate/final-report-3.1.0-candidate.md`;
      `release-candidate/build-manifest.json` refreshed to describe the delivered candidate.
- [x] **P11 Developer Mode audit** — the delivered IPA carries **no** provisioning profile and **no**
      certificate-backed signature anywhere (all 14 Mach-Os decoded), no `get-task-allow` and no
      developer-only/private entitlements; the requirement comes from the *installer's development
      profile*, which is iOS 16+'s documented Developer-Mode category. Conclusion: **required** for
      every available route; report at `release-candidate/developer-mode-audit-3.1.0.md`.
- [x] **P12 Docs gap closed** — Developer Mode prerequisite recorded in `docs/TROUBLESHOOTING.md`
      and the credential section of `docs/installer/compatibility-matrix.md` (no test or renderer
      consumes those files; full suite re-run after the edits).

## Final state (2026-10-27)

| Item | Value |
|---|---|
| Delivered IPA | `C:\Users\sleepy\Downloads\PwEevee-3.1.0.ipa` |
| Size / SHA-256 | 147,039,801 B / `fd3f41e21b93a1585492c2a45112715dd9183c1f7b7370074e91866210f87dc2` |
| Repo copy | `dist/PwEevee-3.1.0.ipa` (git-ignored) |
| Pinned dylib | `45242a9f…` (3,245,280 B) — codesign-valid ad-hoc, `@rpath` Substrate |
| Rejected candidates | `5efc…` unsigned, `9475…` `.unsigned` CodeDirectory, `e74b68…` absolute Substrate path |
| Test suite | 17/17 suites exit 0 (1 documented skip) |
| Device status | **not installed, not launched, no runtime/hang result** — no physical device attached (simulators only); the artifact is a device-slice iOS build |

## Artifact inventory (hashes)

| Artifact | Size | SHA-256 | Meaning |
|---|---|---|---|
| `5efc…` | 3,238,680 | `5efc001e3b693b8d96d6f278c18cf6dce329df8cead367f854a0baf74a94f0e8` | crash-fix IPA embedded dylib — **no signature at all** |
| `60ef…` | 3,245,280 | `60efaf4201a20bece8f465eeaa216d975279f59fca4b9594535a397cdafbabca` | earlier `-src` build, ad-hoc codesign-valid |
| `9475…` | 3,264,384 | `9475c1ef6e10049fd1299bd7c67a43ebb21f37e974648ad26d6acd0709777813` | dylib inside `com.spotipw_3.1.0_iphoneos-arm64.deb` (ldid-signed, `.unsigned` ident) |
| `45242a9f…` (fresh) | 3,245,280 | `45242a9fffaf81f0da5b11883fd029a713ab1d980ac89c7ba8267ce5b54ceb24` | clean rebuild of the confirmed `-src` tree, ad-hoc codesign-valid |
| baseline migrated IPA | 304,984,726 | `aa31425dbbc92d8a3b05e85a46cad2e29447411c6c25fd1fc7e9bb2cea8039e6` | repackaging base |
| crash-fix IPA | 147,032,210 | `764d0e353909e4c2643e8161d8217da2f2d3697b71686f031d920ee41baf993a` | previous candidate (unsigned dylib) |

Preserved copies: Mac `/Users/xcode/preserve-3.1.0/`, Windows `parallel-tmp/preserve/`.

## Build provenance

- Source tree: `/Users/xcode/pweevee-3.1.0-src` (no git metadata); source manifest
  `tweak/Sources` + `scripts`, 500 files, manifest SHA-256 `2ffe977aa3437709a5e86b051bfe7ce10accc6412d5f9d68059315628c102155`
  (file list + per-file hashes in `parallel-tmp/src-manifest.txt`).
- `THEOS_PACKAGE_SCHEME := rootless` is applied before `include $(THEOS)/makefiles/common.mk`.
- Clean rebuild: `rm -rf .theos && make` (Theos with `~/bin/ldid` shim → ad-hoc codesign).
- Reproducibility: fresh vs `60ef…` differ **only** in the `LC_UUID` (diff begins at 0x11F8,
  the UUID load command) plus the signature blob that depends on it.

## Phase 2 details (differences, verified)

| Field | `5efc…` (crash-fix IPA) | `60ef…` / fresh | `9475…` (deb) |
|---|---|---|---|
| `ncmds` / `sizeofcmds` | 72 / 8872 | 73 / 8888 | 73 / 8888 |
| `LC_SEGMENT_64(__LINKEDIT)` vmsize | 0x3C000 | 0x40000 | 0x44000 |
| `LC_SEGMENT_64(__LINKEDIT)` filesize | 240,408 | 247,008 | 266,112 |
| `LC_CODE_SIGNATURE` | absent | offset 3,238,688, size 6,592 | offset 3,238,688, size 25,696 |
| CodeDirectory | — | v=0x20400 flags=0x2 (adhoc), ident `spotifyglass.dylib.47ba6b93`, sha256, valid | v=0x20400 flags=0x0, ident `…47ba6b93.unsigned`, no CMS slot, `codesign`: no signature |
| `codesign --verify` | n/a (unsigned) | **valid on disk / satisfies DR** | fails (no signature) |
| Substrate dependency | `@rpath/…` | `@rpath/…` | `@rpath/…` |
| Guard markers (9 required / 2 forbidden) | pass | pass | pass |

`__LINKEDIT` filesize deltas equal the code-signature blob deltas exactly
(247,008 − 240,408 = 6,600 = signature size; 266,112 − 247,008 = 19,104).

## Developer Mode audit (later session, 2026-10-27)

The question: why does launching the delivered build require Developer Mode on iOS, and can that
be avoided legitimately?

**Answer: required.** The requirement is created by the *installer's* development profile, not by
anything in PwEevee's packaging, and Apple's only documented exemptions (App Store, TestFlight;
Enterprise in-house per WWDC22) are unavailable or illegitimate for a modified Spotify build.

Static checks actually run on the delivered artifact (`fd3f41e2…`, unchanged by this audit):

| Check | Result |
|---|---|
| `embedded.mobileprovision` / `.provisionprofile` in the 1,193 archive members | **0** |
| CMS (certificate) signature slot in any of the 14 Mach-Os | **0** — host app, 5 appexes and frameworks have CodeDirectory + requirements but no signature slot |
| Signatures that exist at all | `spotifyglass.dylib` only — ad-hoc (`flags=0x2`, empty CMS wrapper), i.e. the project's own `ldid`-shim output |
| `get-task-allow` as an entitlement in any Mach-O | **none** (one literal ASCII occurrence in the host binary's `__TEXT`, a code reference) |
| `dynamic-codesigning`, `task_for_pid`, `platform-application`, `com.apple.private*`, `com.apple.security.cs.*`, `com.apple.developer.kernel.*` | **none anywhere in the payload** |
| Host archive entitlements | Spotify's own App Store set (`8W66MEA7DD.com.spotify.client`, team `2FNC3A47ZF`, app groups, `aps-environment production`, …) — unauthorizable by any personal/ad-hoc profile, so the signer rewrites them |
| Embedded dylib vs the pin | byte-identical, `45242a9fffaf81f0da5b11883fd029a713ab1d980ac89c7ba8267ce5b54ceb24` |
| Physical device probe (build Mac) | **none attached** — `devicectl` lists only simulated devices (all `shutdown`), no iPhone in `SPUSBDataType`, libimobiledevice absent |

Not attempted, by policy: stripping/adding signatures, editing entitlements, faking `get-task-allow`,
or any device-side experiment (no device, and no static change can affect a device-side policy check).
Three one-variable experiments (T1 gate confirmation, T2 paid ad-hoc falsification, T3 stock-bytes
comparison) are specified in the report §6 for whoever has the phone. Install, launch and runtime
behaviour remain **unverified**; the launch observation is the user's report.

Reproduce: `py parallel-tmp/dm-census.py "C:/Users/sleepy/Downloads/PwEevee-3.1.0.ipa"`,
`py parallel-tmp/dm-audit2.py`, `py parallel-tmp/mac-run.py "xcrun devicectl list devices"`.

## Pre-publication cleanup pass (same day, 2026-10-27)

Repository-wide cleanup before the maintainer publishes 3.1.0 by hand; **nothing was
committed, pushed, tagged or published**, and the candidate was read-only throughout.
Report: `release-candidate/prepublication-audit-3.1.0.md`.

- Branding: the legacy lineage name is `spoti.pw` / `SpoTi.pw` / `spotipw` (`Taurus*` appears
  only as an earlier internal line inside `taurus-rc/` records, and as a comparison subject in
  `docs/comparison/`). Active occurrences corrected in `README.md`,
  `website-src/pages/compatibility.html`,  `docs/installer/compatibility-matrix.md`,
  `docs/TROUBLESHOOTING.md`, plus the stale test count in `docs/ARCHITECTURE.md`
  (`website-tests.pl` 469 → the actual 4,396). Deliberately preserved: `spoti.pw` package identity in the
  tracked `Spotipw/` tree (`com.spotipw` is the stable deb identity), every `taurus-rc/**`
  historical record, upstream attribution and licences, and historical changelog text.
- Superseded download references: the README reproduced the `v2.2.0-pre` notes and three
  `releases/download/v2.2.0-pre/…` links as the project front page; replaced by the 3.1.0
  candidate section with an explicit pending-publication status. Retired repo slug
  `codeboy2012/spoti.pw-builds` removed from the site generator's `own_repo_url` fallback
  (remaining occurrences are recorded history / the local reference-clone path).
- Obsolete IPA artifacts: none tracked for distribution and no repository copy of the
  candidate. `dist/*.ipa`, `audit/ipas/*.ipa` and GitHub 2.x/0.x releases are preserved as
  history or as regression/forensic fixtures; nothing was deleted.
- Catalogues/database: **no application-managed SQLite DB or server-side catalogue exists** —
  the release and app-source catalogues are generated JSON (`releases.json`,
  `website/pweevee/apps.json`), refreshed by `update-releases.pl`/`update-appsource.pl` and by
  the `release: published` workflow. The app source still names `v2.2.0-pre` today and moves to
  3.1.0 on publication; no URL was fabricated.
- New regression suite `PwEevee/build-system/tests/prepublication-tests.pl` (27 checks):
  stale slug (with a named, enforced exemption list), README hash ↔ build-manifest hash
  agreement, no promoted superseded build, app-source assets exist. Validated by three
  negative controls (`parallel-tmp/prepub-negative-controls.py`) with byte-exact restores.
- Full suite after cleanup: **18/18 suites exit 0, 0 failures**, four self-declared skips —
  `pweevee-1.1.0-beta-tests.pl` (superseded beta deb absent) plus the input-IPA-conditioned
  sections of `build-tests.pl`, `bundle-deps-tests.pl` and `embedded-artifact-test.pl`. The
  embedded-artifact suite was re-run explicitly against the candidate with `PWEEVEE_IPA` +
  `PWEEVEE_IPA_HOST=1`: **26 checks passed**. Candidate unchanged: 147,039,801 bytes,
  `fd3f41e21b93a1585492c2a45112715dd9183c1f7b7370074e91866210f87dc2`.
- Open for the maintainer: the tracked `Spotipw/` tree is the old lineage (site update
  endpoint + `spoti.pw` identity) and is **not** the build source — the shipped dylib comes
  from `taurus-rc/source`. The app source also lists a "watchfix experimental" entry.

### Committed and pushed (2026-10-27)

Maintainer asked for the cleanup to land. Commit `0251869` on `main` (50 files) — README
release section, retired repository slug, branding/notice corrections, regenerated website,
new `prepublication-tests.pl`, this log and the audit report. Pushed to `origin/main`.

The push was rebased onto eight automated `data(stats)` commits the refresh workflow had
pushed meanwhile; their snapshot still used the pre-fix `projects.json` and so re-introduced
the retired slug as a repository key. Stats regenerated with `update-stats.pl` (slug-free
keys, fresh numbers) and the site re-rendered with `render-site.pl` so the rendered numbers
match the committed stats — both folded into `0251869`. A companion commit makes
`tests/pweevee-1.1.0-beta-tests.pl` skip (exit 0) when its superseded subject deb (kept in
git-ignored `dist/`) is absent; an explicitly passed path still hard-fails.

Excluded from that commit (still uncommitted, maintainer's call): `PwEevee/components/**`
(the dylib pin + component manifest + package control), `PwEevee/build-system/unified.sh`,
`lib/macho.pm`, `watch/watchfix.sh`, `brand-icons/manifest.json`, the tracked `Spotipw/`
tree, and the untracked `dylib-guard-test.pl` / `embedded-artifact-test.pl` /
`bundle-deps-tests.pl` / `validate-bundle-deps.pl` plus their fixtures. (Those guard suites
are untracked because they assert the new dylib pin, which is uncommitted too.)

Re-verified in a detached worktree at the pushed tree: `prepublication-tests.pl` 27 checks,
`website-tests.pl` 4,396 checks, `readme-updater-tests.pl` 29 checks, `appsource-tests.pl`
118 checks, `brand-asset-tests.pl` 38 checks. Whole suite in that worktree: **13 pass, 2
self-declared skips, 0 fail** (a clean checkout has 15 suites — the three dylib guard suites
are untracked). Release not published; device behaviour still unverified.
