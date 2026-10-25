# PwEevee v3.1.0 — prioritized roadmap

Evidence-first status. **[A]** artifact-verified, **[C]** code + test-verified in
this repo, **[D]** upstream-documented only, **[U]** unverified.

## P0 — release-blocking correctness / trust

| # | Item | State |
|---|---|---|
| P0-1 | Binary-plist writer + reader: operator/length tables, exact integer preservation, > 256-object offsets | **[C] done** — `plist-roundtrip-tests.pl`, 27 checks green, incl. 300-object tree + 32-bit-int exact round-trip + malformed-input refusals |
| P0-2 | Alternate-icon patcher: idempotent re-run, iPhone/iPad icon metadata, referenced-asset existence, unrelated keys untouched | **[C] done** — `alternate-icon-tests.pl`, 28 checks; v2 canonical-payload design means re-run writes identical bytes, sim+real-plist negative tests (missing asset, dirty re-run) included |
| P0-3 | `validate-ipa.pl` hard gate: alternate-icon declarations + referenced files must exist inside the IPA | **[C] done** — wired into `unified.sh` after packaging; fails with named, missing asset |
| P0-4 | Dependency integrity: hash/sizes pinned and tested | **[C] done** — `manifest.json` per component; D-2 (spotifyglass pin == artifact bytes) + a D-3 test that refuses a mismatching CydiaSubstrate pin; the actual D-3 pin refresh/re-cut stays a maintainer release decision |
| P0-5 | Reproducibility: ZIP writer deterministic for identical input | **[C] done** — fixed self-comparison assert + new build test |
| P0-6 | Branding: PwEevee-owned original artwork, verified not Spotify's; website + build use it | **[C] done** — `brand-asset-tests.pl` (38 checks) incl. double-run determinism, no-Spotify-mark guard, pinned master hashes |
| P0-7 | macOS build of a real IPA | **[U] blocked** — Mac key auth is required first (below); no IPA was built or validated in this phase |

## P1 — next work (approved candidates)

| # | Item | Basis |
|---|---|---|
| P1-1 | **Alternate icons shipped in the v3.1.0 unified IPA** — the patcher is now gated and tested end-to-end on fixture IPAs; wire the icon set into `components/spotipw` after one device verification | builds on P0-2/P0-3 [C]; device check still [U] |
| P1-2 | **Update checker** against `https://github.com/codeboy2012/PwEevee` latest release API, graceful offline/limit behavior, independent of upstream checkers | repo verified live; not implemented yet |
| P1-3 | **ILI9341 chip family upstream refresh** — pull latest upstream spoti.pw changes into the integration layer once P0 gates are green on a device | upstream [D] |
| P1-4 | LiveActivity hardening: only-start-when-foregrounded is already repository policy; add an instrumentation check that it never fires while backgrounded | [D]→[C] gap |

## P2 — polish / later

| # | Item | Basis |
|---|---|---|
| P2-1 | Additional alternate icon colorways (the pipeline is icon-set agnostic) | own artwork only |
| P2-2 | Website dark-mode audit against `accessibility` guidelines | independent |
| P2-3 | docs/comparison dashboard French/Japanese translations | independent |

## Release gates for v3.1.0

A release may be cut when **all** of these hold:

1. All suites green incl. the three new ones (plist 27 ✅, alternate-icon 28 ✅,
   brand-asset 38 ✅) plus existing suites.
2. One real IPA is built on the Mac, passes `validate-ipa.pl` with alternate icons
   present, and its spotiglass/Substrate bytes match `unified/manifest.json`.
3. Branded assets verified (P0-6) and the No-Spotify-mark guard is part of CI.
4. Update checker shows PwEevee versions only (P1-2).
5. `licensing-and-provenance.md` attribution present on the website credits page.
