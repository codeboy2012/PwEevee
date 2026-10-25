# Device-testing preparation — simulator inventory & test matrix

Date: 2026-10-25 · scope: read-only inventory + a plan. **No device, simulator, or runtime has
been booted, installed into, or tested yet**; nothing here is a compatibility result.

## 1. What is actually available on the Mac (verified read-only)

### Simulator runtimes installed

| Runtime | Status |
|---|---|
| iOS 27.0 | installed |
| watchOS 27.0 | installed |

> `xcrun simctl list runtimes` also emits `Install Started → Install Failed: Authorization is
> required to install the packages.` — a *background auto-download attempt* by CoreSimulator
> (macOS is fetching newer simulator runtimes and being blocked by admin auth), not a failure
> of any action we took and not corrected here (would require admin auth on the Mac; not
> authorized this phase). I did **not** retry or bypass it.

### Simulated iPhone devices available right now (all Shutdown, iOS 27.0 runtime)

| Device | UDID |
|---|---|
| iPhone 18 Pro | 7F592F7D-56F2-40D4-887D-B2B0165DE5E6 |
| iPhone 18 Pro Max | 1163EB0E-587C-4A7A-8503-55BDF182FF0B |
| iPhone 17e | DDC875F8-5C5E-41F4-9315-D2DFD150A3E9 |
| iPhone Air | C51D7DA7-9F58-43A6-B991-3CE4616FAB94 |
| iPhone 17 | F8237806-7618-4FEA-BAF2-261A71AF262C |

### Watch simulators (watchOS 27.0)

Apple Watch Series 12 (46/42 mm), Apple Watch Ultra 4 (49 mm) — Shutdown.

### SDKs that exist but have no installed runtime

iphonesimulator27.1 SDK is present, but the **iOS 27.0** runtime only (not 27.1) is installed;
no iOS 26 or iOS 18 runtime, and no simulators for the *other* requested OS generations.

## 2. Requested compatibility targets, honest status before any run

| Target | Status right now | Reason |
|---|---|---|
| iPhone 18 / iOS 27 | **NOT TESTED** — simulator hardware **exists** (iPhone 18 Pro / Pro Max / Air, iOS 27 runtime) | nothing has been booted or installed yet |
| iPhone 17 / iOS 26 | **NOT TESTED — OS RUNTIME UNAVAILABLE** | iOS 26 simulator runtime not installed on the Mac; device hardware exists (iPhone 17) |
| iPhone 16 / iOS 18 | **NOT TESTED — DEVICE + OS RUNTIME UNAVAILABLE** | no iPhone 16 simulator (device generation predates the installed SDK), no iOS 18 runtime |

Every unmatched combination stays labeled NOT TESTED and will not be substituted, per the
non-negotiable requirement.

> Simulator ≠ physical device. A simulator passing does not certify physical-device
> behavior (entitlements, provisioning, Watch pairing, real audio stack, background
> transitions, App Store-like integrity checks all differ). Simulator runs are
> *supplementary smoke checks only* and will be reported as such.

## 3. Build/deploy constraints affecting device testing (planned, not confirmed at runtime yet)

| Area | Constraint / plan |
|---|---|
| IPA install into simulator | `xcrun simctl install` accepts .ipa files; whether this signed-store-only build's frameworks (spotifyglass, EeveeSpotify, CydiaSubstrate, Orion, EeveeSwiftProtobuf) *launch* on simulator (arm64 slice presence, @rpath load behavior, MobileSubstrate symbol resolution) is the first thing to verify — expected to be limited because CydiaSubstrate/tweak dylibs are device-only hooks |
| Signing | build is and remains **unsigned store-only**; simulator launches may tolerate this, physical installation will not — physical testing requires code signing with a backup Apple ID/provisioning profile, which needs your explicit authorization and your own credentials; **none created, requested, or exported** |
| Watch component | watchOS 27 simulators exist, but PwEevee normalizes the embedded Watch/ tree with `--watch`; watch-app pairing in simulator is fragile and only meaningful after a successful watch-app embedding build |
| Background/live-tasks, entitlements | data-extension, keychain, and entitlement behaviors are device-only; will be marked N/A on simulator rather than reported as pass |
| Physical-device testing (iPhone hardware) | requires you to attach a physical iPhone to the Mac, unlock it, register it with Xcode for the iOS version in question, and provision/sign — needs **your explicit authorization** + your Apple credentials; I will not install, pair, or deploy without that |

## 4. Proposed test matrix (draft — runs only after a successful authorized build on the Mac)

Columns: **target / what runs / where / what we verify / evidence per row.**

| # | Test | Environment | Checks (would be marked PASSED/FAILED/BLOCKED/SKIPPED/NOT TESTED) |
|---|---|---|---|
| M-1 | Artifact sanity on target | after Mac build | sha256 of fresh IPA matches build manifest; packaging validator exit 0 |
| M-2 | Simulator boot + install + launch | iPhone 18 Pro (iOS 27.0) sim | `xcrun simctl boot` → `simctl install <ipa>` → `simctl launch com.spotify.client`; capture `simctl diagnose`/launchd errors; **supplementary smoke check only** |
| M-3 | Settings screen loads | same | screenshot/log the PwEevee tab; confirm the 247-row inventory still renders |
| M-4 | Alternate icon registration | same | `Info.plist` inside the built artifact shows `CFBundleAlternateIcons` w/ pweevee-icon; simulator icon picker becomes a visual check you can eyeball |
| M-5 | Update checker | same | offline case (no network to github), rate-limit case via mock-free normal GitHub API response, and normal no-update case; validate graceful states |
| M-6 | Eevee tab behavior | same | verify karaoke/Eevee settings render and log errors to device console |
| M-7 | Watch embedding presence | artifact inspection only | confirm Watch binaries still intact after normalization, matching its validator (no device pairing attempted) |
| M-8 | Physical iPhone 18 / iOS 27 | real device (pending your auth) | install via Xcode/sideload tool of your choice; real launch, settings toggles, icon switch, Eevee tab, update check; crash logs via `spctl`/sysdiagnose you capture locally |
| M-9 | Physical iPhone 17 / iOS 26 | real device (pending your auth) | same matrix; OS 26 must come from the device itself |
| M-10 | Physical iPhone 16 / iOS 18 | real device (pending your auth) | same matrix; depends on iOS 18.7 installed on the hardware |

**Blocked/absent preconditions recorded upfront:** no Apple Developer account or signing
identity is configured in this session; physical-device rows M-8/M-9/M-10 cannot be claimed
without it. They remain **NOT TESTED — requires signing + authorized device**.

## 5. What I will need from you when this goes forward

1. Approve the *xz* remedy (G-1, pick Option 1/2/3 from `mac-readiness.md §6`).
2. Approvecreating a fresh, isolated build dir `~/pweevee-work` on the Mac and transferring
   the repo + input IPA there (I will not touch `~/pweevee-build`).
3. Authorize the build command (Phase 3 checkpoint) with the source commit `43a92ce`.
4. For physical testing later: attach each device to the Mac and unlock it, then approve
   the signing step with your own Apple ID credentials (I will not create/export any).
