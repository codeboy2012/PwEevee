# PwEevee v4 roadmap

This is a phase plan, not a release schedule. There are no dates here, and a phase
being listed does not mean it is finished. Status changes only when the work is
actually verified.

The current legacy release is **v3.1.6.1**. It remains available from
[GitHub Releases](https://github.com/codeboy2012/PwEevee/releases/tag/v3.1.6.1) while v4
is built.

## Phase 1 — v3 transition and cleanup

**Status: in progress**

- Keep the published v3.1.6.1 release and its assets unchanged.
- Remove retired v3 website code, generated data and refresh automation.
- Replace the old public documentation with the v4 transition notice.
- Keep the source, build, packaging and release-validation paths reproducible.
- Keep structured issue forms and useful labels in place.

## Phase 2 — Architecture and foundation

**Status: planned**

- Rebuild the project's core architecture around a maintainable v4 codebase.
- Define clean boundaries between PwEevee, Chroma and EeveeSpotify.
- Make component updates, version detection and validation predictable.
- Establish the build and test baseline that later phases depend on.

## Phase 3 — Core development and original features

**Status: planned**

- Build the PwEevee-specific functionality that goes beyond the upstream
  integrations.
- Expand customization, settings and the app-icon experience.
- Improve diagnostics, error handling and first-run guidance.
- Keep upstream compatibility work separate from original PwEevee work.

## Phase 4 — New user experience and website

**Status: planned**

- Design the v4 experience as one coherent product rather than a collection of panels.
- Build the new PwEevee website and documentation from scratch.
- Do not restore the retired v3 website or its automation.
- Keep downloads, release notes and compatibility information easy to find.

## Phase 5 — Compatibility testing and release preparation

**Status: planned**

- Test across supported iOS versions, devices and Spotify builds.
- Validate IPA packaging, signing requirements and upgrade paths.
- Verify integrations against the current upstream releases.
- Prepare release notes, checksums and rollback guidance.

## Phase 6 — v4.0.0 launch

**Status: planned**

- Publish v4.0.0 only when the previous phases are complete and verified.
- Publish the matching release assets and notes.
- Keep v3.1.6.1 available as the legacy release.
- Announce the launch through GitHub Releases and the rebuilt website.

## What this roadmap is not

- It is not a promise that every idea mentioned for v4 will ship.
- It is not a countdown or an estimated release window.
- It is not a list of completed work. Phase 1 is the only phase in progress, and it will
  be marked complete only after the transition work is verified.
