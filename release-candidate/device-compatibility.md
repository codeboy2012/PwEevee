# PwEevee v3.1.0 RC — device compatibility

## Requested targets vs what was testable

| Device target | Requested iOS | Status | Reason |
|---|---|---|---|
| iPhone 18 | iOS 27 | **NOT TESTED — DEVICE/OS UNAVAILABLE** | No iPhone 18 hardware; no iOS 27 runtime, device or signed image reachable from this workspace; the Mac (needed for Xcode/simulators) stayed unreachable because no SSH key was installed. No substitution was made. |
| iPhone 17 | iOS 26 | **NOT TESTED — DEVICE/OS UNAVAILABLE** | Same: no authorized device/simulator reachable at all this session. |
| iPhone 16 | iOS 18 | **NOT TESTED — DEVICE/OS UNAVAILABLE** | Same. The machine had no iOS simulator capability to invoke, and remote device testing was not authorized. |

**No combination of install → launch → settings persistence → icon swap →
update-checker → Eevee behavior was observed on real hardware or on a simulator
in this session.** Every claim above honesty-first: substituted versions were
explicitly refused per instructions.

## Simulators

Not available on this Windows workspace (no Xcode/simulator runtime), and the
self-hosted macOS runner was not reachable through SSH (`Permission denied
(publickey,password)` with a dedicated key absent). Simulator smoke checks were
therefore impossible; they would have run on the Mac had authentication been
configured.

## Source-derived compatibility expectations (clearly labeled — NOT runtime evidence)

From the audited sources and the RC artifact's own metadata:

- Base Spotify 9.1.90 binary is **arm64** (Mach-O validation passed on it), so the
  RC is nominally installable on any modern iPhone with `arm64`/`arm64e`
  hardware — **static fact about the binary, not a device-verified claim**.
- Redesign gating: `Pages.m` gates "Redesigned UI" with `SGRedesignAvailable()`
  and shows a "Needs iOS 26" degradation path below iOS 26. On an iPhone 16 +
  iOS 18 one should therefore expect legacy-look behavior with the redesign row
  greyed/stated unavailable — **source-derived expectation; untested**.
- Watch companion: the embedded Watch tree was normalized by `watchfix-stage`
  (self-check OK; ids `com.spotify.client` → `…watchkitapp`); its on-pairing
  behavior needs a real device+watch — untested.
- Alternate-icon mechanism needs `setAlternateIconName:` at runtime — untested.

## What a proper device matrix needs (for whoever continues)

1. SSH key installed for `xcode@192.168.1.127` (steps in `docs/comparison/test-report.md`).
2. On the Mac: Xcode simulators for iOS 18/26/27 runtimes if installed — run the
   harnesses (`Spotipw/harness/*`) and install the RC into a simulator.
3. For real iPhones: signing credentials the user authorizes; sideload; repeat
   the checklist in `docs/comparison/test-report.md` §Honest claim status.

## Related suites that DID run (non-device)

watch-fix suite 46/46 (with the contained python), all 13 core suites green —
see `release-readiness.md` for the full table. None of them substitute for device
verification.
