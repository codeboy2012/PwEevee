# PwEevee v3.1.0 RC — release readiness

**Recommendation: NO-GO for v3.1.0 as a final release this session.**
GO **only** for publishing the RC internally/further device testing. The
artifact and tests are strong, but device verification and signing remain
unverifiable from this environment, and the project's own release-gate list
(`docs/comparison/roadmap.md`) requires them.

## Test execution — exact commands and exit codes (this session)

| Suite (`perl PwEvevee/build-system/tests/<file>`) | Exit | Result |
|---|---|---|
| plist-roundtrip-tests.pl | 0 | PASSED — 29 checks |
| alternate-icon-tests.pl | 0 | PASSED — 28 checks |
| brand-asset-tests.pl | 0 | PASSED — 38 checks |
| build-tests.pl | 0 | PASSED — 8 checks |
| component-manifest-test.pl | 0 | PASSED — 389 checks |
| deb-format-test.pl | 0 | PASSED — 30 checks |
| eevee-settings-tests.pl | 0 | PASSED — 70 checks |
| pweevee-deb-tests.pl | 0 | PASSED — 6 checks |
| pweevee-premium-exclusivity-tests.pl | 0 | PASSED — 47 checks |
| pweevee-rebrand-tests.pl | 0 | PASSED — 30 checks (update-checker endpoint pinned) |
| readme-updater-tests.pl | 0 | PASSED — 29 ok |
| website-tests.pl | 0 | OK — 2827 checks |
| `watch/tests/watchfix-tests.pl` | 0 | **PASSED — 46 checks** (with the contained `tools/python` on PATH; 11/45 fail *without* it because the store-python stub cannot parse binary plists — environmental, not a code defect) |
| pweevee-1.1.0-beta-tests.pl | 2 | **BLOCKED** — needs `dist/PwEevee_1.1.0-beta_*.deb`, which was never built and is untracked; refuses loudly, never fakes |
| pweevee-update-checker | — | **NOT SEPARATELY RUNNABLE** — covered inside `pweevee-rebrand-tests.pl` (30 passed); no standalone suite exists for the network behavior |

Totals: **13 PASSED suites (1,239 checks), 1 BLOCKED, 1 covered under rebrand.**
Artificial pass-reporting: none.

## Build gate

| Item | State |
|---|---|
| RC IPA built with the documented pipeline | **YES** — exit 0 ([build-report.md](build-report.md)) |
| Packaging validators pass on the artifact | YES (15/15 Mach-O; structure PASSED) |
| Pinned binary hashes match (in-IPA vs repo pins) | YES (spotiglass/EeveeSubstrate/apple-icon byte-identical; frameworks in-suite 389 checks) |
| Alternate icons registered in the packaged plist | YES (grep + validator + RC log) |
| Watch companion normalized & kept | YES (watchfix self-check OK; 46-check suite green) |
| Independent reproducible-build comparison | **NOT DONE** — two-build byte comparison not run; no reproducibility claim made |
| Signing/provisioning verification | **NOT DONE** — no credentials; output is unsigned store-only |
| Device launch/settings/icons/update-check runtime | **NOT DONE** — see [device-compatibility.md](device-compatibility.md) |

## Blockers (severity-ranked)

1. **HIGH — device verification gap.** All three requested iPhone/iOS pairs
   NOT TESTED. No hardware, no simulator, no Mac auth.
2. **HIGH — signing.** No credentials; the RC cannot ship publicly signed as-is
   (same caveat as 0.22.0-alpha.2 sideload flow; not a regression).
3. **MEDIUM — Mac access.** One SSH key install away (steps in
   `docs/comparison/test-report.md`); unlocks real builds + simulators.
4. **MEDIUM — beta-deb artifact missing** for `pweevee-1.1.0-beta-tests`;
   either build the deb artifact or formally retire that suite from gate lists.
5. **LOW — contained python dependency** for watchfix on non-Mac hosts;
   `tools/python` lives inside `release-candidate/` only; document or gate.

## Known-tracked items (unchanged this session, from `docs/comparison/roadmap.md`)

- LiveContainer icon change crash (`Need an imageRef`) — upstream host issue, untouched.
- iOS-18 non-jailbreak downloads — platform/server limitation, documented, not claimed fixed.
- CydiaSubstrate pin reconciliation (`748d129f…` vs `3c691ec7…`) — maintainer release decision; the RC ships the hash-pinned repo copy (suite-verified), and the packaged copy equals the pin.

## Go/no-go

- **NO-GO** for a public v3.1.0 release until blockers 1–2 are cleared and the
  roadmap's release gates (§5 of `docs/comparison/roadmap.md`) complete.
- **GO** for: sharing the RC privately for device testing, pulling the repo-side
  release-candidate branch forward, and fixing the LOW/MEDIUM items.
