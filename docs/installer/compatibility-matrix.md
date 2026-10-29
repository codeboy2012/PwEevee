# PwEevee installer — certificate & profile compatibility matrix

Date: 2026-10-25. Every row states its evidence class:
**verified** = checked by code the user runs (`/install` validator) or by a cited source,
**expected** = reasoned from cited docs but not device-verified,
**blocked** = cannot be determined in this build (stated, never guessed).

The artifact these rows describe: the PwEevee rebuild of Spotify 9.1.90
(256 MB compressed, ~‑80 MB installed), main app + **5 app extensions**
(IntentsExtension, NotificationContentExtension, NotificationServiceExtension,
SpotifyGlassLiveActivity, WidgetExtension) + 3 embedded frameworks + 2 injected dylibs.
Background facts with citations: the private distribution-readiness report, retained outside this repository.

## A. Credential types

| Credential | Status | Notes / evidence |
|---|---|---|
| Free Apple ID (Personal Team) development certificate + generated profile | expected | altstore.io flow; 7-day app IDs, 3 apps, ≤3 devices. App Groups stripped → widgets degrade (silent/empty), app still runs. |
| Paid Apple Developer Program development profile | expected | keychain-access-groups + App Group only if the groups exist for the team; upstream group names would need capability configuration |
| Enterprise In-House (ProvisionsAllDevices) | expected; validator detects the profile flag and states it | requires enterprise trust settings |
| Apple-issued distribution App Store profile | unsupported | store-signed flow requires Apple's servers; sideloading is a different path |
| TrollStore-consumed builds | out of scope of the website signer path | profile-less; flags in the matrix docs only |

### A.1 Developer Mode on iOS 16+ (added 2026-10-27)

**Apple-documented:** Developer Mode (Settings → Privacy & Security) "grant[s] or den[y] permission
for locally installed apps to run" and covers "installing an `.ipa` file with Apple Configurator"; it
does not affect "ordinary installation techniques, such as buying apps from the App Store or
participating in a TestFlight team"
(<https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device>). Apple's
registered-device page adds: *"To run your iOS, iPadOS, visionOS, or watchOS app that you install
from an iOS Package Archive, enable Developer Mode on that device"* — in the same section that
describes the **ad hoc** profile.

Consequences for this matrix:

- **Every locally installed credential class above** — free Personal Team, paid development, and the
  ad hoc path — is inside Developer Mode's documented scope. Test the expectation as
  *Developer Mode required* unless a device proves otherwise on the actual iOS version.
- The bullet `TrollStore-consumed builds` is the only profile-less path, and it is not an
  Apple-sanctioned distribution route (CoreTrust exploit, iOS ≤ 17.0).
- iOS 16+ also needs the separate certificate-trust step (Settings → General → VPN & Device
  Management), which is required with or without Developer Mode.
- Evidence class: **Apple-documented** for the requirement and its scope; **expected** for the ad hoc
  exception question (Apple does not state either way; Google Firebase documents a "Developer Mode
  Required" launch error for ad hoc–provisioned apps on iOS 16+). Full audit:
  [developer-mode-audit-3.1.0.md](../../release-candidate/developer-mode-audit-3.1.0.md).

## A.2 Known issue carried for a future update (added 2026-10-27)

**iPhone SE (2nd generation), iOS 17.8.1 — Spotify login and signup currently return a
"Spotify server error."** Reproduced on the device named above; acknowledged for a future
update. The build installs and launches, but **authentication does not work on iOS 17** in
this release, so no iOS version is marked as fully compatible on the strength of a launch
alone. This is recorded here, in the release notes, in
[docs/TROUBLESHOOTING.md](../TROUBLESHOOTING.md) and on the website's compatibility page.

## B. Per-check results the /install validator produces

| Check | What it does | Result values |
|---|---|---|
| IPA integrity | ZIP End-of-Central-Directory + central directory scan; per-entry size sanity | validated / unsupported (truncated, 4 GB entries, zip64-only) |
| Main app identity | `Payload/<app>/Info.plist` → bundle ID, version, minimum OS | validated / unable to verify (plist unreadable) |
| Profile freshness | profile ExpirationDate vs system clock (UTC) | validated (days remaining) / unsupported (expired) |
| App-ID match | profile `application-identifier` prefix + bundle ID suffix vs main app bundle ID | validated / unsupported (mismatch named exactly) |
| Extension coverage | 5 appex bundle IDs listed; per-tool rule stated | expected (SideStore ≥ 0.6.2 reuses the main profile — cited) / unable to verify (tool-dependent) |
| Provisioned devices (free/ad-hoc profile) | `ProvisionedDevices` list presence + count | validated (N devices, current device registration cannot be read in-browser — flagged) |
| App Group entitlements | profile `Entitlements` g1.oups + main app bundle scan | validated / unsupported with the free-team limitation copy |
| aps-environment | profile entitlements presence | validated (present/absent, informational) |
| `.p12` container | PKCS#12 ASN.1 wrapper structure, salted-data detection, MacData presence | unable to verify for contents (cert/private-key decrypt requires PBE — PKCS12 KDF + RC2/3DES, not implemented in this build) |
| Certificate / key correspondence and expiry | requires decrypted p12 contents | blocked in-browser this build; on-device tools perform it |

## C. Installation paths (supported vs not)

| Path | Status | Why |
|---|---|---|
| Export the validated IPA and hand it to AltStore Classic / SideStore on the same or another device | supported (this build's primary path) | the tool signs locally; credentials stay local |
| Feather / Sideloadly local signing on a computer or device | supported | same class: tool-side local signing |
| `itms-services://` one-tap wireless install from this site | **not supported** | requires a CA-signed HTTPS manifest plus a *signed* IPA; an unsigned IPA cannot complete it, and provisioning an ad-hoc or enterprise flow is a separate verified process — enabling it would imply more than is true |
| Site-hosted signed IPA upload | not implemented | the upload route does not exist; if a future build adds optional temporary hosting it must be explicit opt-in with expiry/deletion, per the project brief |
| "The app is installed" claims | never shown | no in-tab mechanism can observe an installation result |

## D. False-statement rules enforced in code and copy

- Unsupported or unverifiable → the badge says exactly that, with the reason.
- Nothing claims "signed" based only on ZIP extraction or a hash command.
- Bundle IDs/entitlements are never rewritten by the site to make signing pass.
