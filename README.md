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
  <a href="#current-release">Current Release</a> ·
  <a href="#what-pweevee-does">What PwEevee Does</a> ·
  <a href="#repository">Repository</a> ·
  <a href="#building">Building</a> ·
  <a href="#website">Website</a> ·
  <a href="#credits">Credits</a> ·
  <a href="#ai-disclosure">AI Disclosure</a> ·
  <a href="#legal--rights">Legal</a>
</p>

---

## About

**PwEevee** is an independent integration and distribution project for modified Spotify iOS builds.

PwEevee brings together upstream projects and their components into a unified build workflow rather than creating those projects from scratch.

The project currently combines:

- **SpoTi.pw**
- **EeveeSpotify**
- Their required supporting components and dependencies
- A unified integration and packaging pipeline
- Automated validation and build testing
- A public release and distribution website

The goal is to provide a clear, reproducible, and transparent way to build and distribute a unified Spotify iOS IPA while preserving attribution to the projects and people whose work makes the functionality possible.

PwEevee does **not** claim authorship of SpoTi.pw, EeveeSpotify, Spotify, Apple, or any other upstream software.

---

## Current Release

### PwEevee v1.0.2 — SpoTi.pw v0.23.0-beta Integration

> ⚠️ **PRE-RELEASE — BUGS AND COMPATIBILITY ISSUES MAY OCCUR**
>
> PwEevee v1.0.2 combines SpoTi.pw v0.23.0-beta with EeveeSpotify v6.6.8. The combined build has reported compatibility warnings, so do not assume that every integrated component is working correctly on every Spotify version.

**Base:** SpoTi.pw v0.23.0-beta  
**Upstream commit:** `49e02e2`  
**Integrated component:** EeveeSpotify v6.6.8  
**PwEevee release:** v1.0.2  
**Status:** Pre-release

PwEevee combines **SpoTi.pw** and **EeveeSpotify** into a unified Spotify modification experience, with custom settings organization and app icon support.

### Downloads

#### Combined PwEevee build

**`PwEevee.v1.0.2.ipa`**

This is the combined IPA intended to include both SpoTi.pw and EeveeSpotify. The current build has shown compatibility warnings; review the warnings in the app and use it as an experimental pre-release.

#### SpoTi.pw-only build (without EeveeSpotify)

**`Spotpw v0.23.0 PRE.ipa`**

A separate SpoTi.pw-only IPA for users who do not want the EeveeSpotify integration. This build does **not** include EeveeSpotify. Its compatibility notice identifies Spotify **v9.1.78** as the intended version; use a matching Spotify version and do not assume compatibility with v9.1.76.

#### Individual tweak packages

For users customizing their own IPA, the release also provides the individual tweak packages:

- **SpoTi.pw v0.23.0-beta:** `com.spotipw_0.23.0-beta_iphoneos-arm.deb`
- **EeveeSpotify v6.6.8:** `com.eevee.spotify_6.6.8_iphoneos-arm64.1.deb`

These packages are intended for use with an appropriate IPA customization or tweak-injection workflow. Bundling a package in the release does not guarantee compatibility with every IPA or Spotify version.

### Known issues

As a pre-release, PwEevee v1.0.2 may contain bugs, incomplete functionality, or unexpected behavior. Reported concerns include:

- The combined build may report Spotify v9.1.76 as unsupported by SpoTi.pw.
- EeveeSpotify may report itself as unsupported even when it is injected alongside SpoTi.pw.
- App signing or installation problems may vary by signing method.
- Compatibility may differ between Spotify versions.

These are issues to investigate, not a claim that every possible failure has been reproduced. Please report bugs with steps to reproduce them and relevant logs.

### Spotify compatibility

- **Combined PwEevee IPA:** targets Spotify **v9.1.76**, but compatibility warnings have been observed and functionality is not guaranteed.
- **SpoTi.pw-only IPA:** its compatibility notice identifies Spotify **v9.1.78** as the intended target.
- Other Spotify versions are not guaranteed to work.

### Feedback

Please report reproducible bugs and compatibility problems through the repository's Issues page.

**Important:** These are pre-release builds and are not a guarantee of production stability.

## Why EeveeSpotify Is Integrated

SpoTi.pw has historically provided Spotify modifications including functionality such as **Hide Ads** and **Spoof Premium**.

Those capabilities are not expected to remain available as options in future SpoTi.pw releases.

PwEevee therefore integrates EeveeSpotify into the SpoTi.pw-based build so that the project can continue providing a unified build containing functionality from both upstream projects.

This does not make PwEevee the author of either project.

Instead:

```text
SpoTi.pw
    │
    ├── upstream project
    │
    ▼
PwEevee integration
    │
    ├── build
    ├── dependency resolution
    ├── integration
    ├── validation
    ├── packaging
    └── distribution
    │
    ▼
Unified Spotify iOS IPA
    ▲
    │
EeveeSpotify
    │
    └── upstream project
