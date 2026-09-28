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

> ⚠️ **PRE-RELEASE — BUGS MAY OCCUR**
>
> PwEevee v1.0.2 is an early release combining SpoTi.pw v0.23.0-beta with EeveeSpotify v6.6.8. This release is available for users to try, report bugs, and provide feedback as the project continues to improve.

**Base:** SpoTi.pw v0.23.0-beta  
**Upstream commit:** `49e02e2`  
**Integrated component:** EeveeSpotify v6.6.8  
**Spotify target:** v9.1.76  
**PwEevee release:** v1.0.2  
**Status:** Pre-release

PwEevee combines **SpoTi.pw** and **EeveeSpotify** into a unified Spotify modification experience. This release incorporates the SpoTi.pw v0.23.0-beta baseline while integrating PwEevee's custom settings organization, app icon support, and feature configuration.

### Known issues

As a pre-release, PwEevee v1.0.2 may contain bugs, incomplete functionality, or unexpected behavior. Possible issues include:

- Individual features not behaving as expected
- Settings or integrations behaving inconsistently
- App signing or installation problems depending on the signing method
- Compatibility differences between Spotify versions
- Unexpected interactions between SpoTi.pw and EeveeSpotify features

These are potential areas to watch for, not a claim that every listed issue has been reproduced. Please report any bugs with steps to reproduce them and relevant logs.

### Spotify compatibility

The intended Spotify target is **v9.1.76**.

Other Spotify versions, including v9.1.84, are not guaranteed to work unless tested with this release.

### Downloads

Download **PwEevee v1.0.2** from the GitHub Releases page.

As this is a pre-release, expect changes and possible bugs in future updates. Feedback and bug reports are welcome.

---

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
