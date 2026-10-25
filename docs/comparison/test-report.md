# PwEevee 1.1.0-beta-a vs the field — test report

Scope of this report: everything run in the October 25 2026 session (v3.1.0 stabilization +
alternate-icon pipeline + brand assets + comparison docs). The earlier forensic audit
(Oct 24) is summarized in [../audit/audit-report.md](../audit/audit-report.md) and its
own evidence lives under `audit/ipas/`.

Environment: Windows 10 (Git Bash), Strawberry/perl 5.x, no macOS runner reachable
(see "Blocked environment" below). Every suite is a pure-Perl, dependency-light
harness with hard exit codes; counts below are the literal ok-print counts.

## Run commands (exact, from the repo root)

```
perl PwEvevee/build-system/tests/plist-roundtrip-tests.pl
perl PwEvevee/build-system/tests/alternate-icon-tests.pl
perl PwEvevee/build-system/tests/brand-asset-tests.pl
perl PwEvevee/build-system/tests/build-tests.pl
perl PwEvevee/build-system/tests/component-manifest-test.pl
perl PwEvevee/build-system/tests/deb-format-test.pl
perl PwEvevee/build-system/tests/eevee-settings-tests.pl
perl PwEvevee/build-system/tests/pweevee-deb-tests.pl
perl PwEvevee/build-system/tests/pweevee-premium-exclusivity-tests.pl
perl PwEvevee/build-system/tests/pweevee-rebrand-tests.pl
perl PwEvevee/build-system/tests/readme-updater-tests.pl
perl PwEvevee/build-system/tests/website-tests.pl
perl PwEvevee/build-system/release/render-site.pl        # re-render, then website-tests above
perl PwEvevee/build-system/tests/pweevee-1.1.0-beta-tests.pl   # environmental skip, see below
```

## Results (this session)

| Suite | Result | Notes |
|---|---|---|
| `plist-roundtrip-tests.pl` | **PASSED — 29 checks** | new: binary/XML plist reader+writer (bplist.pm). Covers >256-object plists (2-byte refs), exact 8/negative ints (no float collapse), trailer layout, dict 2×npairs marker, deterministic output, shared-subnode preservation, `same()` dict semantics, malformed-input negatives |
| `alternate-icon-tests.pl` | **PASSED — 28 checks** | new: patch-alternate-icon.pl. Idempotent re-patch (byte-identical Info.plist on 2nd run, no duplicate entries), unrelated keys survive, foreign provider entries preserved, `~ipad` mirroring only when the host declares it (and never created otherwise), staged icon hash/size verified, negatives: corrupted icon / wrong-sha manifest / missing icon / missing manifest all die hard **before staging**; validate-ipa.pl reports `ALTERNATE ICON MISSING` when the referenced file is deleted |
| `brand-asset-tests.pl` | **PASSED — 38 checks** | new: committed PNGs parse (PwPng), exact square dims (180/512/180/32), RGBA alpha usable, manifest sha256+size match committed bytes, no Spotify-marked asset wired into the website, no Spotify image filename in rendered index, **determinism**: `make-app-icon.pl` re-run twice with an explicit backup → all generated outputs byte-identical (any divergence would be restored + failed) |
| `build-tests.pl` | **PASSED — 8 checks (2 skip)** | injector/plist sub-tests deliberately skip because `Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa` is not on disk; skip is printed, not masked. ZIP determinism test is the real two-write hash comparison |
| `component-manifest-test.pl` | **PASSED — 389 checks** | every component pin verified by sha256+size incl. CydiaSubstrate `binary_sha256`; CRLF-tolerant |
| `deb-format-test.pl` | **PASSED — 30 checks** | |
| `eevee-settings-tests.pl` | **PASSED — 70 checks** | |
| `pweevee-deb-tests.pl` | **PASSED — 6 checks** | |
| `pweevee-premium-exclusivity-tests.pl` | **PASSED — 47 checks** | mutual exclusivity of Premium-spoof rows |
| `pweevee-rebrand-tests.pl` | **PASSED — 30 checks** | includes: update checker endpoint pinned to `repos/codeboy2012/PwEevee/releases`, no upstream releases endpoint in code |
| `readme-updater-tests.pl` | **PASSED — 29 checks** | |
| `website-tests.pl` | **OK — 2827 checks** | re-run after re-render that added the Taurus + EeveeIPA upstream links (`website/index.html` now carries both) |
| `pweevee-1.1.0-beta-tests.pl` | **ENVIRONMENTAL SKIP — exit 2** | needs `dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb`, which git does not track. Fails loudly (`no such deb: …`), never fakes a pass |

Totals: **12 passed suites, 1 documented environmental skip, 0 silent failures.**

## What was changed this session (files)

Build system (all new or edited under `PwEvevee/build-system/`):

- [alternate-icon-tests.pl](../../PwEvevee/build-system/tests/alternate-icon-tests.pl) — new suite
- [brand-asset-tests.pl](../../PwEvevee/build-system/tests/brand-asset-tests.pl) — new suite
- [patch-alternate-icon.pl](../../PwEvevee/build-system/package/patch-alternate-icon.pl) — idempotent alternate-icon registration (staging step, wired into `unified.sh` as a hard step), `~ipad` mirroring, sha256 manifest enforcement, test-only `PWEEVEE_BRAND_ICONS_DIR` override
- [bplist.pm](../../PwEvevee/build-system/lib/bplist.pm) — binary plist writer reworked: trailer offsets file-absolute, dict marker = 2×npairs refs, first-pass object counting enables >256 objects with 2/4-byte refs, exact `pack q>` integers, corrected `same()`; reader robust for negative/64-bit ints
- [plist-roundtrip-tests.pl](../../PwEvevee/build-system/tests/plist-roundtrip-tests.pl) — new suite
- [validate/validate-ipa.pl](../../PwEvevee/build-system/validate/validate-ipa.pl) — new referenced-alternate-icon check (any `CFBundleAlternateIcons` entry whose `name`/`name.png` is missing from the staged app root fails packaging)
- [unified.sh](../../PwEvevee/build-system/unified.sh) — patch step wired before packaging; manifest records the brand icon
- `PwEvevee/brand-icons/pweevee-icon.png` + `manifest.json` — committed, hash-pinned IPA icon family member (generated by `release/make-app-icon.pl`)

Website:

- `website-src/layout.html` — added verified upstream links: Taurus source (`samj-exe/taurus`), EeveeIPA prebuilt distribution (`estrogencat/EeveeIPA`, labeled as *not Eevee's source*); re-rendered via `render-site.pl`

Documentation (this directory): `architecture.md`, `feature-matrix.md`, `licensing-and-provenance.md`, `roadmap.md`, `test-report.md` (an HTML dashboard and icon-attribution/source-provenance pages were scoped out of this phase — roadmap.md P2 notes them as future polish and the claims those pages would carry live in source-provenance form inside `licensing-and-provenance.md`)

## Explicit skips and honest limitations

1. `pweevee-1.1.0-beta-tests.pl` — requires the built deb artifact; exit 2 recorded.
2. `build-tests.pl` — two sub-tests skip (source IPA absent); other 8 checks ran.
3. **macOS build not executed.** `ssh -o BatchMode=yes xcode@192.168.1.127` →
   `Permission denied (publickey,password,keyboard-interactive)`. No SSH key is
   installed for this machine; the exposed password must not be reused. **Unblock
   (user action, then this agent can proceed):**
   1. On the Windows box, if no dedicated key exists yet:
      `ssh-keygen -t ed25519 -f ~/.ssh/pweevee_mac -C "pweevee-build"` (empty
      passphrase is acceptable only on a disk BitLocker protects; otherwise set one
      and use ssh-agent).
   2. On the Mac (once, locally at its keyboard or via any existing session):
      `mkdir -p ~/.ssh && chmod 700 ~/.ssh`, then append the **public** line of
      `~/.ssh/pweevee_mac.pub` to `~/.ssh/authorized_keys` and
      `chmod 600 ~/.ssh/authorized_keys`.
   3. On Windows add to `~/.ssh/config`:
      `Host pweevee-mac` / `HostName 192.168.1.127` / `User xcode` /
      `IdentityFile ~/.ssh/pweevee_mac` / `IdentitiesOnly yes`.
   4. Then `ssh -o BatchMode=yes pweevee-mac echo ok` must print `ok` before any
      build step is attempted. After that, run `unified.sh`, `tweak/Makefile` and
      the harness checks on the Mac in an isolated work directory. Nothing was
      asserted about Xcode/Theos state there because nothing was reachable.
4. Runtime behavior of the IPAs (launch, lyrics fetch, Live Activity) was never
   tested — binaries are executed by no test here. Static + packaging evidence only.
5. The four original IPAs in Downloads were never modified; the alternate-icon
   fixture is a committed copy (`Info-Spotify-9.1.90.plist`) plus temp copies.

## Honest claim status for the icon pipeline

- Verified: patcher idempotence on real Spotify Info.plist fixture, hash-pinned
  staged icon, validate-ipa catch of removed icon files, determinism of artwork,
  manifest↔committed-bytes agreement.
- Not verified (needs a device): that `setAlternateIconName("PwEevee")` actually
  swaps the icon on iOS; that the iPad leg resolves (plists only mirror what the
  host already declares). Keep the LiveContainer caveat: upstream host limitation,
  icon change crashes there by its own cause (see `licensing-and-provenance.md`).
