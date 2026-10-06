<p align="center">
  <img src="https://raw.githubusercontent.com/codeboy2012/PwEevee/refs/heads/main/website/assets/icon-512.png" width="160" alt="PwEevee">
</p>

<h1 align="center">PwEevee</h1>

<p align="center">
  <strong>
    An independent Spotify iOS integration, build, and distribution project.
  </strong>
</p>

<p align="center">
  <a href="#about">About</a> ·
  <a href="#v200">v2.0.0</a> ·
  <a href="#recommended-build">Recommended Build</a> ·
  <a href="#combined-build">Combined Build</a> ·
  <a href="#base-ipa">Base IPA</a> ·
  <a href="#features">Features</a> ·
  <a href="#compatibility">Compatibility</a> ·
  <a href="#building">Building</a> ·
  <a href="#credits">Credits</a> ·
  <a href="#ai-disclosure">AI Disclosure</a> ·
  <a href="#legal">Legal</a>
</p>

<p align="center">
  <a href="https://github.com/codeboy2012/PwEevee/releases/latest">
    <img src="https://img.shields.io/github/v/release/codeboy2012/PwEevee?style=for-the-badge&label=Latest%20Release" alt="Latest Release">
  </a>
  <a href="https://github.com/codeboy2012/PwEevee/releases">
    <img src="https://img.shields.io/github/downloads/codeboy2012/PwEevee/total?style=for-the-badge&label=Downloads" alt="Downloads">
  </a>
  <a href="https://github.com/codeboy2012/PwEevee">
    <img src="https://img.shields.io/github/stars/codeboy2012/PwEevee?style=for-the-badge" alt="GitHub Stars">
  </a>
</p>

---

## About

**PwEevee** is an independent project focused on integrating, packaging, testing, and distributing modified Spotify iOS builds.

PwEevee does not attempt to recreate the upstream projects it uses. Instead, it combines upstream components with PwEevee's own integration, build, packaging, documentation, and distribution work.

The project currently works with:

- **EeveeSpotify**
- **SpoTi.pw**
- Spotify iOS builds
- Supporting dependencies and components
- IPA integration and packaging
- Compatibility and validation workflows
- Release and distribution infrastructure

The goal is to make the resulting builds easier to understand, install, and distribute while maintaining clear attribution to the original projects.

> **PwEevee is an independent project and is not affiliated with Spotify or Apple.**

---

# v2.0.0

## PwEevee v2.0.0

**PwEevee v2.0.0** is a major overhaul of the project centered around **EeveeSpotify 7.0.0**.

This release moves PwEevee significantly forward from the v1.x generation and introduces a much newer customization experience, including:

-  Liquid Glass
-  Redesigned settings
-  Tab customization
-  Appearance customization
-  Player customization
-  Custom lyrics
-  App flag tools
-  Privacy improvements
-  Stability improvements
-  Updated iOS 26/27 experience
-  Major EeveeSpotify 7.0.0 updates

### Release information

| Component | Version |
|---|---|
| **PwEevee** | **v2.0.0** |
| **EeveeSpotify** | **v7.0.0** |
| **SpoTi.pw** | **v0.50.0** |
| **Primary build** | EeveeSpotify 7.0.0 |
| **Spotify base** | Spotify 9.1.78 |

---

#  Recommended Build

## EeveeSpotify 7.0.0

### `EeveeSpotifyv7.0.0.ipa`

**154 MB**

**SHA-256**

```text
1fff261d89e085e11dbf234ae1205c82c42ee144f31b23b92f24631a6cfe688f
```

This is the **recommended PwEevee v2.0.0 build**.

It focuses on the new EeveeSpotify 7.0.0 experience without requiring the optional SpoTi.pw integration.

### Why this is recommended

Recent SpoTi.pw releases contain functionality that may be restricted behind paid/premium features.

PwEevee therefore recommends the standalone EeveeSpotify build for users who want the most complete free experience available through this project.

The standalone build provides a large feature set without requiring the newer SpoTi.pw component.

### Highlights

-  Liquid Glass
-  Redesigned settings
-  Tab customization
-  Appearance customization
-  Player customization
-  Custom lyrics
-  App flag tools
-  Privacy improvements
-  Stability improvements
-  Updated iOS 26/27 experience
-  Major EeveeSpotify 7.0.0 updates

> **Recommendation:** If you are unsure which IPA to use, use `EeveeSpotifyv7.0.0.ipa`.

---

# Combined Build

## SpoTi.pw 0.50.0 + EeveeSpotify 7.0.0

### `SpoTiv50.0.0+EeveeSpotifyv7.0.0.ipa`

**133 MB**

**SHA-256**

```text
8f29fae6681e99a90f69f6e6f7165d87f192bc761388867eb08e0ad0e4d115d6
```

This is the optional **combined PwEevee build**.

It contains:

- **SpoTi.pw 0.50.0**
- **EeveeSpotify 7.0.0**

The combined build provides additional functionality from the SpoTi.pw integration alongside EeveeSpotify.

However, it is **not the primary recommended build**.

### Important

The combined build does **not** contain every feature available in SpoTi.pw 0.50.0.

Some SpoTi.pw functionality may also be subject to upstream availability or premium restrictions.

For the best free experience, **use the standalone EeveeSpotify 7.0.0 build instead.**

---

# Base IPA

## Spotify 9.1.78 — No Watch

### `com.spotify.client_9.1.78_No_Watch.ipa`

**169 MB**

**SHA-256**

```text
b03c869e0811634d94f90fd66fa57d0d4ec0c839324381c5f89ee67e5a0b4db4
```

This is the **Spotify 9.1.78 base IPA** used as a foundation for compatible builds.

The `No_Watch` variant is provided separately from the modified PwEevee builds.

### This is NOT the recommended end-user build.

It is primarily useful as a base for users who understand IPA customization, signing, and tweak injection workflows.

---

# Features

PwEevee v2.0.0 is built around the updated EeveeSpotify 7.0.0 generation.

##  Customization

Customize the Spotify experience with features such as:

- Appearance controls
- Tab customization
- Player customization
- Settings customization
- Alternate app icon support
- Updated visual styling
- Liquid Glass integration

##  Lyrics

EeveeSpotify 7.0.0 includes significant lyrics-related functionality, including:

- Custom lyrics
- Enhanced lyrics behavior
- Word-synced lyrics support
- Improved lyrics customization

##  App Flags

PwEevee v2.0.0 includes access to updated app flag functionality.

This can expose additional configuration and experimental options provided by the underlying implementation.

## Liquid Glass

EeveeSpotify 7.0.0 introduces an updated Liquid Glass experience designed around newer iOS versions.

PwEevee v2.0.0 carries this updated experience into the recommended build.

---

# Build Overview

```text
                    PwEevee v2.0.0
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
      EeveeSpotify 7.0.0          SpoTi.pw 0.50.0
             │                           │
             │                    Optional integration
             │                           │
             └─────────────┬─────────────┘
                           │
                           ▼
                    PwEevee Packaging
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       Recommended IPA            Combined IPA
       EeveeSpotify 7.0.0       SpoTi.pw + Eevee
```

---

# Compatibility

Compatibility depends on several factors:

- Spotify version
- iOS version
- Device architecture
- Signing method
- Sideloading environment
- Other installed modifications
- Selected PwEevee build

## EeveeSpotify 7.0.0

EeveeSpotify 7.0.0 targets modern Spotify **9.1.x** releases and requires:

**iOS 16.1 or newer**

The exact supported Spotify version may vary as Spotify releases new builds.

## Spotify 9.1.78

The included base IPA is:

**Spotify 9.1.78**

This version is the primary base associated with the v2.0.0 release.

> ⚠️ Compatibility with Spotify versions outside the intended range is not guaranteed.

---

# Installation

PwEevee distributes IPA files.

You will need a compatible iOS signing/sideloading method to install an IPA.

The exact installation process depends on your environment and signing method.

PwEevee does not require a specific sideloading application.

Before installing:

1. Verify your iOS version.
2. Verify the Spotify version associated with the IPA.
3. Make sure your signing method supports the application.
4. Remove conflicting Spotify modifications if necessary.
5. Keep a backup of anything important.

> **Do not assume that multiple Spotify modifications can safely be installed together.**

---

# Troubleshooting

If PwEevee does not work correctly, first verify:

### 1. Spotify version

Make sure the Spotify version matches the intended build.

### 2. iOS version

Check that your device meets the requirements of the underlying EeveeSpotify release.

### 3. Signing

Some installation failures are caused by the signing environment rather than PwEevee itself.

### 4. Conflicting tweaks

Other Spotify modifications may conflict with PwEevee.

### 5. Combined build

If you are using:

`SpoTiv50.0.0+EeveeSpotifyv7.0.0.ipa`

try the recommended:

`EeveeSpotifyv7.0.0.ipa`

This helps determine whether the issue originates from the optional SpoTi.pw integration.

---

# Reporting Issues

Found a bug?

Please open an issue on GitHub and include as much information as possible.

### Please provide:

- PwEevee version
- IPA filename
- Spotify version
- iOS version
- Device model
- Signing/sideloading method
- Whether you used the standalone or combined build
- Steps to reproduce the problem
- Crash logs, if available
- Screenshots or recordings when useful

### Example

```text
PwEevee: v2.0.0
Build: EeveeSpotifyv7.0.0.ipa
Spotify: 9.1.78
iOS: 26.x
Device: iPhone ...
Sideloading: ...
Issue: ...
Steps:
1. ...
2. ...
3. ...
```

Good bug reports make problems dramatically easier to reproduce and fix.

---

# Repository

The PwEevee repository contains the project's:

- Integration code
- Build configuration
- Packaging configuration
- Documentation
- Website
- Release tooling
- Supporting project infrastructure

PwEevee also incorporates work from upstream projects.

Upstream source code remains subject to its original licenses and ownership.

---

# Building

PwEevee is intended to be built using an appropriate iOS development environment.

Depending on the component, building may require tools such as:

- Theos
- Xcode / Apple SDKs
- iOS SDKs
- Objective-C / Objective-C++ tooling
- `ldid`
- Debian packaging tools
- IPA extraction/repackaging tools
- Required upstream dependencies

The build process can change when upstream projects change.

PwEevee attempts to keep integration and packaging changes understandable and reproducible.

---

# Project Structure

The project may contain several major areas:

```text
PwEevee/
├── website/
│   └── Project website assets
│
├── integration/
│   └── PwEevee integration work
│
├── packaging/
│   └── IPA/deb packaging
│
├── scripts/
│   └── Build and validation tooling
│
└── README.md
```

> The exact repository structure may change as the project evolves.

---

# Credits

PwEevee would not exist without the upstream projects and developers whose work provides the underlying functionality.

## EeveeSpotify

**EeveeSpotify** is the primary upstream project behind the recommended PwEevee v2.0.0 build.

PwEevee does not claim ownership of EeveeSpotify or its source code.

Please support the original EeveeSpotify project and its developers.

## SpoTi.pw

**SpoTi.pw** is integrated into the optional combined build.

PwEevee does not claim ownership of SpoTi.pw or its source code.

The combined build uses **SpoTi.pw 0.50.0**.

## Spotify

Spotify, the Spotify name, logos, trademarks, and related intellectual property belong to their respective owners.

PwEevee is not affiliated with, sponsored by, or endorsed by Spotify.

## Apple

Apple, iOS, and related trademarks belong to Apple Inc.

PwEevee is not affiliated with, sponsored by, or endorsed by Apple.

---

# AI Disclosure

PwEevee may use AI-assisted development tools during development.

AI assistance may be used for:

- Code analysis
- Debugging
- Refactoring
- Documentation
- Testing assistance
- Build troubleshooting
- UI development
- Release preparation
- General development assistance

AI assistance does not change the ownership or attribution of upstream software.

All upstream projects remain credited to their respective developers and contributors.

---

# Legal

PwEevee is an independent project.

**PwEevee is not affiliated with Spotify or Apple.**

The project does not claim ownership of third-party:

- Source code
- Trademarks
- Logos
- Assets
- Libraries
- Applications
- Intellectual property

Third-party software remains subject to its respective licenses and the rights of its original authors.

Users are responsible for complying with applicable laws, software licenses, platform rules, and terms when using or distributing modified software.

If an upstream project has specific attribution or redistribution requirements, those requirements apply to the relevant component.

---

# Downloads

##  Recommended

**EeveeSpotify 7.0.0**

`EeveeSpotifyv7.0.0.ipa`

**154 MB**

SHA-256:

```text
1fff261d89e085e11dbf234ae1205c82c42ee144f31b23b92f24631a6cfe688f
```

---

## Optional Combined

**SpoTi.pw 0.50.0 + EeveeSpotify 7.0.0**

`SpoTiv50.0.0+EeveeSpotifyv7.0.0.ipa`

**133 MB**

SHA-256:

```text
8f29fae6681e99a90f69f6e6f7165d87f192bc761388867eb08e0ad0e4d115d6
```

---

## Base IPA

**Spotify 9.1.78 — No Watch**

`com.spotify.client_9.1.78_No_Watch.ipa`

**169 MB**

SHA-256:

```text
b03c869e0811634d94f90fd66fa57d0d4ec0c839324381c5f89ee67e5a0b4db4
```

---

# What's New in v2.0.0

### Major update

PwEevee v2.0.0 moves the project to the **EeveeSpotify 7.0.0** generation.

### New

- EeveeSpotify 7.0.0
- Liquid Glass
- Spotify version spoofing
- Updated settings
- Tab customization
- Appearance customization
- Player customization
- Custom lyrics
- Karaoke improvements
- App flag tools
- Remote flag browser
- Privacy improvements
- Stability improvements
- Updated iOS 26 experience

### Changed

- EeveeSpotify is now the recommended PwEevee build.
- SpoTi.pw integration is now optional.
- The project has moved away from relying on SpoTi.pw as the primary experience.
- Updated Spotify 9.1.78 base IPA.
- Major packaging and integration updates.

---

# PwEevee

**v2.0.0**

> **Built around EeveeSpotify 7.0.0.**
>
> **Liquid Glass. Spoofing. Customization. Lyrics. More.**

 **Recommended:** `EeveeSpotifyv7.0.0.ipa`

 **Optional:** `SpoTiv50.0.0+EeveeSpotifyv7.0.0.ipa`
