# PwEevee installer — certificate & profile compatibility matrix

Date: 2026-10-25. Every row states its evidence class:
**verified** = checked by code the user runs (`/install` validator) or by a cited source,
**expected** = reasoned from cited docs but not device-verified,
**blocked** = cannot be determined in this build (stated, never guessed).

The artifact these rows describe: the PwEevee rebuild of Spotify 9.1.90
(256 MB compressed, ~‑80 MB installed), main app + **5 app extensions**
(IntentsExtension, NotificationContentExtension, NotificationServiceExtension,
SpotifyGlassLiveActivity, WidgetExtension) + 3 embedded frameworks + 2 injected dylibs.
Background facts with citations: [taurus-rc/reports/distribution-readiness.md](../../taurus-rc/reports/distribution-readiness.md).

## A. Credential types

| Credential | Status | Notes / evidence |
|---|---|---|
| Free Apple ID (Personal Team) development certificate + generated profile | expected | altstore.io flow; 7-day app IDs, 3 apps, ≤3 devices. App Groups stripped → widgets degrade (silent/empty), app still runs. |
| Paid Apple Developer Program development profile | expected | keychain-access-groups + App Group only if the groups exist for the team; upstream group names would need capability configuration |
| Enterprise In-House (ProvisionsAllDevices) | expected; validator detects the profile flag and states it | requires enterprise trust settings |
| Apple-issued distribution App Store profile | unsupported | store-signed flow requires Apple's servers; sideloading is a different path |
| TrollStore-consumed builds | out of scope of the website signer path | profile-less; flags in the matrix docs only |

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
