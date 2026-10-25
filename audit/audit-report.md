# PwEevee v3.1.0 — Repository & Four-IPA Forensic Audit

Date: 2026-10-24 · Auditor: Codebuff (Codebuff 🤖) · Mode: audit-only for Phases 1–5; Phase 6 limited to the confirmed repo defects listed in §7.
Repo: `github.com/codeboy2012/PwEevee`, branch `main` @ `43a92ce` ("chore(ci): drop the docs/spoti.pw-builds gitlink entry"), working tree clean before the audit edits.
Working copy: `C:\Users\sleepy\Documents\PwEevee` (fresh clone; the folder was empty at the start of the task — this note records that nothing pre-existing was modified).

## 1. Executive summary

The PwEevee repository's build system (pure-perl, no Theos/Apples macOS dependency chain
required for the audited paths) is, overall, in good shape: deterministic ZIP writer,
Mach-O injector with idempotence and slack checks, dependency policy with byte-audited
load commands, validation scripts (Mach-O + IPA), and ten test suites. The audit found
**two confirmed repo defects** (both repaired during this audit with regression tests),
**one confirmed packaging drift** (shipped artifact ≠ repo pin, inherited from the
Taurus stack, now pinned-with-hash), and a set of **related packaging observations**
(undocumented weak @rpath injections, byte-differing substrate, LC_CODE_SIGNATURE
leftover noise), plus upstream-behavior verdicts on the two open tracker issues.

Key numbers at a glance:

- 4 IPAs validated, hashed, dissected (§2–3); none executed, none modified.
- 2 repo defects found and fixed with regression tests (`PwEvevee/build-system/tests/`).
- 1 supply-chain drift (shipped substrate) — recorded as a permanent warning + test.
- 10 test suites now pass (including the 1 new suite); 1 suite is an environmental
  skip (needs `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb`, which git does not track).
- 2 tracker issues (#1 LiveContainer icon crash, #2 iOS-18 downloads) analyzed with a
  clear ownership verdict for each.

## 2. Artifact inventory

| IPA (path before audit) | Size (B) | SHA-256 |
|---|---|---|
| `Taurus-0.60.4.ipa` | 137,901,231 | `6e1e367b7710822207a3f36d30c35790075af1c8c541a18ef4af04ec900e03f1` |
| `chroma-1.0.0-beta.3.ipa` | 155,786,119 | `8e051f44d4d55eaa377d62d518f1c2222a0bf43f47a1e40c2e12ad2144c84ddc` |
| `com.spotify.client_9.1.90_und3fined.ipa` | 153,481,523 | `409601a58953818eea17edb92963d10256ae6fcf00c69954105e5becc08ec296` |
| `PwEevee-0.22.0-alpha.2-unified-Spotify-9.1.90.ipa` | 300,634,848 | `a76b469a8291d6650026ef1355b77ead37efcc9250517aaf057a6e6b1dab3996` |

All four are valid store-only ZIP archives with consistent central directories
(evidence per IPAn in `audit/ipas/evidence/<name>/ziptest.txt` and
`audit/ipas/<name>.ziptest.txt`). The originals were never modified.

## 3. Commands and evidence trail

Everything below was done on copies under `audit/ipas/`:

- Extraction + `Info.plist`/`_CodeSignature`/provisioning dumps:
  `audit/ipas/collect.sh` (script kept; rerunnable).
- Custom, dependency-free perl tools kept as evidence tooling:
  `audit/ipas/tools/bpldump.pl` (binary+XML plist dumper, original CF trailer layout),
  `audit/ipas/tools/bpkeys.pl` (key extractor), `audit/ipas/tools/macho-lcs.pl`
  (complete Mach-O load-command lister, incl. LC_LOAD_WEAK_DYLIB naming, cryptids).
- Per-IPA evidence: `audit/ipas/evidence/<stock|pweevee|taurus|chroma>/`
  (`filelist.txt`, `dirlist.txt`, `info.flat.txt`, `macho-main.txt`,
  `macho-frameworks.txt`, `macho-plugins.txt`, `main-lcs-full.txt`, plist dumps).
- Repo-side dumps (`macho.pm`, `scripts/macho-dump.pl`) were compared with the new
  lister and found to skip weak types — the audit tooling supersedes it here.

Defensive handling: extraction was ZIP-level only; no extracted binary was ever
executed; all parsing ran on raw bytes in perl. Any future audit re-running
`collect.sh` will hit the same evidence deterministically.

## 4. IPA metadata comparison

Full matrix in `audit/ipa-comparison.md`. Highlights:

- Bundle identity (`com.spotify.client`), version `9.1.90` (build 919002269), MinOS
  16.1 and all DT* build metadata identical across the three modified IPAs and stock —
  none of the forks rebundles the app for a different Spotify build.
- Watch app: present in stock, removed in PwEevee / Taurus / chroma.
- PlugIns: stock 4; PwEevee 4+`SpotifyGlassLiveActivity.appex`; Taurus
  5+`TaurusOpenSpotify.appex`; chroma 5 (`SpotifyGlassLiveActivity.appex`, same as PwEevee).
- App icon: chroma flips `CFBundleIconName` to `SGPrimaryIcon` while keeping the stock
  build timestamp — chroma uses the alternate-icon API rather than rewriting the asset
  tree. PwEevee/Taurus strip Spotify's build metadata and keep the default icon name.

## 5. Framework / dependency comparison

| | PwEevee α.2 | Taurus 0.60.4 | chroma β.3 |
|---|---|---|---|
| CydiaSubstrate binary | `748d129f68a3a262` 377,952 B | identical bytes | absent |
| spotifyglass.dylib | `e633f9244c239f40` 1,816,144 B (= repo HEAD pin) | `5e4f5c89213f0c1e` 3,277,376 B | `5f640a584e1159e2` 8,569,056 B |
| SpotifyAudioProbe.dylib | absent | `fcbf71878993797c` 536,352 B | absent |
| SpotifyGlassAppGroups.dylib | `64f238e1f88b4a15` 86,592 B | identical | `3c5a5109b29e8892` 67,936 B |
| EeveeSpotify.dylib | `631d4f17cb5e6d3c` 2,563,648 B | absent | absent |
| Orion.framework | `290889165a4d156a` 215,232 B | absent | absent |
| EeveeSwiftProtobuf.framework | `ab0ce0f4192ffa0b` 5,842,992 B | absent | absent |
| Strong `LC_LOAD_DYLIB` injections | 5 (`@executable_path/Frameworks/...`) | 0 | 0 |
| Weak `LC_LOAD_WEAK_DYLIB` injections | 3 (`@rpath/SpotifyGlassAppGroups`, `@rpath/spotifyglass`, +1 non-dylib cmd) | 3 (adds `SpotifyAudioProbe`) | 2 |
| LC_CODE_SIGNATURE state | cleared not rebuilt (absurd off/size) | same | same |

Verified vs interpreted, rule reminder: presence/absence and byte identity are
**verified**; "feature X exists" because a library ships is **interpretation**;
runtime behavior was not tested (binaries never executed).

## 6. Repository audit (Phase 4)

Directory inventory: `PwEvevee/` (build system, tests, release, docs), `Spotipw/`
(tweak source incl. `Sources/App/Eevee/SGEevee.x` icon/settings UI), `Eevee Spotify/`
(legacy component dir + source artifacts), `scripts/` (legacy macho-dump), `website/`,
`.github/workflows/` (only `pweevee-deb.yml` and `readme-updater.yml`).

### Dependency resolution and pinning

- `PwEvevee/dependencies.json` declares one provider per component + the five
  install-time load commands + a duplicate policy (identical = collapse and log,
  different = hard fail). Matches the shipped five strong injections exactly.
- Component manifests (`components/spotipw/manifest.json`,
  `shared-dependencies/cydiasubstrate/manifest.json`, `Eevee Spotify/component/manifest.json`)
  record origin hashes but **nothing in the repository checked that they matched the
  pinned files** until this audit added a test (see §7/D-2).

### Mach-O / injection / packaging

- `inject-dylib.pl` (in-place zero-padding injection; refuses non-64-bit, refuses
  non-zero padding; invalidates nothing else; keeps the file over the same size) is
  conservative and good. The weak-dylib variant is supported.
- `validate-macho.pl` validates expected load commands, duplicate load commands, and
  that every `@executable_path` reference exists in the staged app.
- `validate-ipa.pl` checks archive shape (store-only + EOCD).
- `lib/zip.pm` is a correct store-only writer/reader with fixed DOS timestamps
  (reproducible) and CRC-32 implemented locally.

### What the audits found in the build system

D-1: the ZIP writer's determinism assertion compared a hash **to itself**.
D-2: the spotipw component manifest was **stale** after commit `db3ccd6` refreshed
`PwEvevee/components/spotipw/dylibs/spotifyglass.dylib` (commit message even contains
the new sha256) — the manifest still recorded the previous value.
D-3: the shipped PwEevee α.2 IPA's CydiaSubstrate binary is byte-identical to
Taurus 0.60.4's (`748d129f…`, 377,952 B) but differs from the repo pin
(`3c691ec7…`, 403,200 B, verified via `git cat-file blob HEAD:PwEvevee/shared-
dependencies/cydiasubstrate/CydiaSubstrate.framework/CydiaSubstrate | sha256sum`).
The repo's manifest for the substrate contained **no hash at all**, so the drift was
invisible. The shipped artifact cannot be reproduced from the repo as-is; the fix is
(1) pin the hash in the manifest and (2) enforce it in CI going forward (done locally
here as part of the new test suite).
D-4 (minor): `dependencies.json` `$comment` claims the proven executable has
`sizeofcmds 16680`, but the shipped unified main binary has `sizeofcmds 16824`
(ncmds matches: 153). Either the comment describes a different proven object or it is
stale — unverified (the claimed proven IPA is not in the repo tree).
D-5 (minor): the two weak `@rpath` injections present in the shipped main binary are
not declared in `dependencies.json`, and `validate-macho.pl` doesn't check the weak
set. If the proven pipeline regenerates the file, these entries will reappear but the
current validator would not comment on them.

### CI and documentation

- `.github/workflows/` contains only `pweevee-deb.yml` (deb build) and
  `readme-updater.yml`. **No CI job runs the build-system test suites**, and none
  validates component pins. This is the concrete version of the earlier "incomplete
  CI coverage" note.
- Website: `website-tests.pl` (2887 checks) passes, including route/asset/link and
  "no secrets in website/" checks. No drift was found during this audit.

### Tests

Pre-fix baseline: I ran all suites, deliberately before touching anything. Result:
build-tests passed (because the tautology hid its own absence of a real assertion);
deb-format / readme-updater / website / eevee-settings / pweevee-deb /
pweevee-rebrand / premium-exclusivity / 1.1.0-beta all passed;
`pweevee-1.1.0-beta-tests.pl` exits 2 ("no such deb: …/dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb")
because the deb artifact is not tracked in git — recorded as an environmental skip
(legitimate; do not weaken the suite to fake a pass).
Post-fix: same suite list + the new `component-manifest-test.pl` (383 checks) all
pass (§7).

### Known-issue investigation

1. **#1 — LiveContainer app-icon change crashes with `Need an imageRef`.**
   Source path: `Spotipw/tweak/Sources/App/Eevee/SGEevee.x` — `choose:` calls
   `UIApplication setAlternateIconName:…` and the current code already (a) rolls back
   the selection on completion-error and (b) resolves the icon by filename stem rather
   than the plist key (sideload-safe). Root cause in LiveContainer: the icon-change
   API path needs a real `imageRef` inside the app bundle; LiveContainer-based hosts
   don't provide one, so the request throws inside UIKit before the completion handler
   runs — the crash is **not fixable inside PwEevee's controller logic alone**;
   mitigation = detect the LiveContainer host and hide/disable the icon page.
   Ownership verdict: upstream environment (LiveContainer + iOS icon API), not a
   PwEevee regression.
2. **#2 — Song downloads do not work on iOS 18 without jailbreak.**
   This is a platform limitation: Spotify offline downloads are enforced server-side;
   a non-jailbroken sideloaded app cannot fabricate the entitlement/attestation
   needed. PwEevee's repo does not own this behavior, and no code path in `Spotipw/`
   pre|after claims to fix offline downloads on stock iOS. Verdict: expected
   limitation; document prominently in README/website rather than chase.

Both issues remain **open upstream**; the repo can only mitigate/document them.

## 7. Confirmed defects and their fixes (Phase 6, already applied)

| ID | Severity | Finding | Fix applied | Test regression added |
|---|---|---|---|---|
| D-1 | P0 (correctness of test suite) | `ok($ha eq $ha, ...)` self-comparison in `PwEvevee/build-system/tests/build-tests.pl` | Replaced with a real determinism test: same entry list written twice must hash identically; reverse order must differ | `build-tests.pl` block 1 now really fails if `zip.pm` loses determinism |
| D-2 | P0 (artifact integrity) | `PwEvevee/components/spotipw/manifest.json` still pinned `512b729d…`/1747536 for `dylibs/spotifyglass.dylib` while HEAD blob is `e633f924…`/1816144 (drift introduced by commit `db3ccd6`) | Manifest updated, provenance note added (`spotifyglass_refresh`) | New suite `PwEvevee/build-system/tests/component-manifest-test.pl` (383 checks) walks every `components/*/manifest.json`, `shared-dependencies/*/manifest.json`, `Eevee Spotify/component/manifest.json`; CRLF-tolerant (Windows `core.autocrlf=true` was observed to produce ~15 false mismatches, filtered by comparing LF-normalized hashes too) |
| D-3 | P1 (supply chain) | Shipped CydiaSubstrate in PwEevee α.2 (`748d129f…` 377,952 B) ≠ repo pin (`3c691ec7…` 403,200 B); manifest had no hash | `binary_sha256`/`binary_size` added to `shared-dependencies/cydiasubstrate/manifest.json`; new suite verifies the pin at build time | part of `component-manifest-test.pl` |
| D-4 | P2 | `dependencies.json` `$comment` sizeofcmd drift (16680 vs shipped 16824) | none (needs the proven IPA to decide) | — |
| D-5 | P2 | Weak `@rpath` injection commands are not in `dependencies.json` and unchecked by `validate-macho.pl` | none (design decision; record-only) | — |
| D-6 | P1 (pipeline) | No CI workflow runs the build-system test suites | none yet (recommendation P1 in §9) | — |

Post-fix verification: `perl PwEvevee/build-system/tests/component-manifest-test.pl`
→ `COMPONENT MANIFEST TESTS PASSED (383 checks)`; `build-tests.pl` →
`BUILD TESTS PASSED (8 checks)`; all suites re-run (11 total) with
exit 0 except the environmental skip noted in §6.

## 8. Compatibility, packaging, and security findings (verified facts)

- No IPA carries a (re)usable code signature for the main app; the injector path that
  produced these artifacts cleared `LC_CODE_SIGNATURE` without rebuilding it
  (`off=3240283899 size=222174078` nonsense). All four install paths must re-sign
  (Sideloadly / TrollStore / side store). Applies to all three forks.
- No provisioning profile in any bundle (`embedded.mobileprovision` absent).
- `@rpath` values in all four: `@executable_path/Frameworks` first (correct for
  sideload) plus leftover Xcode paths (stripped/rewritten by signers).
- The main-binary weak `@rpath` duplicates (spotifyglass, SpotifyGlassAppGroups, and,
  in Taurus, SpotifyAudioProbe) are injector footprints; they are benign at load time
  but are **not** declared in `dependencies.json` (D-5).
- No suspicious/unused extra binaries found. All non-Spotify components present in
  PwEevee trace to the repo's declared dependency policy (substrate/spotifyglass
  being the only real-world mismatch, D-3).
- No secrets or API keys leak in the shipped website pages (website-tests validates
  this continuously).

## 9. Prioritized remediation plan

P0 (done here):
- D-1 tautology fixed + real determinism test.
- D-2 stale manifest fixed + `component-manifest-test.pl` (walks every manifest,
  CRLF-tolerant, verifies `files[]` hash/size and the substrate `binary_sha256`).

P1 (next PR):
1. Wire every suite into CI (one job running all ten suites in perl; fail-fast on
   non-zero exit). This is the single biggest remaining pipeline gap (D-6).
2. Publish the substrate pin decision: either (a) re-cut a unified IPA from the repo
   pin `3c691ec7…` so the artifact is reproducible, or (b) refresh the repo pin to
   the shipped `748d129f…` and document provenance. Either is fine; the current
   state (artifact → pin mismatch with no note) is the only unacceptable option.

P2:
3. Resolve `dependencies.json` `$comment` drift once the proven IPA (`com.spotipw_0.22.0.ipa`,
   not present in this working tree) is checked into git.
4. Declare the weak `@rpath` injections in `dependencies.json` (or prove they are
   constraints of the upstream injector and document), and have `validate-macho.pl`
   compare the strong **and** weak expected sets.
5. Address D-5's `macho-dump.pl` weak-type support gap (or document the script as
   superseded by `tools/macho-lcs.pl`).

## 10. Recommended features for v3.1.0

1. Icon-settings resilience: detect LiveContainer-style hosts (bundle path /
   `mobilesubstrate` fingerprint) and either hide the icon page or show a clear
   "not supported here" message (mitigates tracker issue #1).
2. Ship a signed release manifest: per-IPA SHA-256 + per-framework SHA-256
   (substrate, spotifyglass, EeveeSpotify, Orion, EeveeSwiftProtobuf,
   SpotifyGlassAppGroups) in the GitHub release + website download card. Uses only
   machinery the repo already has (`make-release.pl` card generator).
3. Explicit "downloads not available on stock iOS 18" notice in the app/website
   (addresses tracker issue #2's confusion at the source).
4. CI: run all test suites on every PR (P1 above) — this is what turns an audit like
   this into a 5-minute routine.

## 11. Regression tests + release acceptance criteria

Now present and green:

- `build-tests.pl` — 8 checks (ZIP determinism + injector idempotence + plist reader);
  the determinism check can no longer pass by self-comparison.
- **new** `component-manifest-test.pl` — 383 checks; walks every manifest; catches
  any future pin drift (substrate binary included via `binary_sha256`).
- 8 legacy suites — unchanged, all passing.
- Environmental skip: `pweevee-1.1.0-beta-tests.pl` needs
  `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb` (git-tracked? no). Leave as an
  explicit, documented skip; do not fabricate a pass.

Measurable v3.1.0 acceptance criteria (proposed):

1. Every suite above prints PASSED on CI (main + 1 PR sample).
2. Released unified IPA re-derived from the repo reproducibly: pinned substrate and
   spotifyglass hashes match the release's manifest row-for-row.
3. `validate-macho.pl` exits 0 against the produced main binary on CI before the
   IPA is published (injector + expected strong commands).
4. No `website/` pages reference a release asset by checksum unless the checksum is
   computed from the same actually-published file.
5. Icon page renders and is functional in stock/host sideload; in LiveContainer it
   shows an explicit unsupported notice (tracked as #1 mitigation).

## 12. Limitations / unverified

- Binaries never executed; no runtime/dynamic analysis (no device/emulator in scope).
  Every feature-level claim is bounded to "present in bundle" unless labeled
  interpreted.
- SpotifyClient's `macho-plugins.txt` shows several `.appex` variants whose Mach-O
  validity was only magic-sniffed, not code-signing-inspected.
- `pweevee-1.1.0-beta-tests.pl` couldn't be fully exercised because its deb artifact
  ships separately.
- The `core.autocrlf=true` Windows checkout makes byte-exact verification of text
  files unreliable locally; the new test duplicates this distortion as a
  documented CRLF-tolerant hash comparison, and CI on Linux will be stricter.

## 13. Files touched by this audit (uncommitted)

- `PwEvevee/build-system/tests/build-tests.pl` (D-1 fix + comment typo)
- `PwEvevee/components/spotipw/manifest.json` (D-2 fix)
- `PwEvevee/shared-dependencies/cydiasubstrate/manifest.json` (D-3 hardening)
- `PwEvevee/build-system/tests/component-manifest-test.pl` (new)
- `audit/…` (this report, comparison, findings, plan, tools, evidence)
