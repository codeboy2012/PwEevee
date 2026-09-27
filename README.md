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

### PwEevee v0.22.0-alpha.2 — Read Disc

> ⚠️ **BETA RELEASE — KNOWN ISSUES**
>
> This release is working and has been tested, but there are still some bugs and rough edges we're working out.

**Base:** SpoTi.pw v0.22.0\
**Integrated component:** EeveeSpotify v6.6.8\
**PwEevee release:** v0.22.0-alpha.2\
**Codename:** Read Disc\
**Status:** Beta / Known Issues

This is the second alpha build of PwEevee, continuing the unified integration of **SpoTi.pw v0.22.0** with **EeveeSpotify v6.6.8**.

The resulting IPA has been tested and is working. This build includes improvements over the previous alpha release, including **working custom app icon support**.

### Known issues

There are still some bugs and unfinished areas being worked out. These may include:

- Bugs in certain features
- Possible unexpected behavior
- Installation or signing issues depending on the signing method
- Compatibility issues with different Spotify versions
- Integration issues that may still be discovered
- Other bugs that have not yet been identified

### Spotify version

This build has been tested with **Spotify v9.1.76**.

**Spotify v9.1.84** is newer and has not yet been fully tested with this build.

For the most reliable experience, use the Spotify version this release was tested against.

There is currently **no guaranteed release schedule**. Future releases will be published when they're ready.

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
