# PwEevee v4 Roadmap

This roadmap outlines the planned development of PwEevee v4. It is organized into phases to communicate priorities, dependencies, and project direction.

This is a phase plan, not a release schedule. There are no release dates or estimated completion windows. A phase being listed does not mean its work has started or is finished. Status changes only when the relevant work has been implemented, tested, and verified.

The current release is **v3.1.6.1**. It will remain available through [GitHub Releases](https://github.com/codeboy2012/PwEevee/releases/tag/v3.1.6.1) while v4 is developed.

## Phase 1 — v3 transition and cleanup

**Status: in progress**

Prepare the repository for v4 development without disrupting the existing legacy release.

- Keep the published v3.1.6.1 release, tag, and assets unchanged.
- Remove retired v3 website code, generated data, and obsolete refresh automation.
- Replace outdated public documentation with a clear v4 transition notice.
- Audit the repository for abandoned scripts, redundant files, stale references, and obsolete workflows.
- Preserve the existing source, build, packaging, and release-validation paths that remain useful.
- Keep structured GitHub issue forms, templates, and useful labels in place.
- Review existing project documentation and identify what needs to be rewritten for v4.
- Ensure old release links and download references continue to work.
- Establish a clean repository baseline before beginning major architectural changes.

**Completion criteria:**
- Retired website infrastructure is no longer part of the active project.
- Existing v3.1.6.1 release assets remain available and unchanged.
- Active workflows and build paths are documented and verified.
- The repository is ready for the v4 foundation work.

## Phase 2 — Architecture and foundation

**Status: planned**

Establish the technical foundation that the rest of v4 will build upon.

- Rebuild the project's core architecture around a maintainable v4 codebase.
- Define clear responsibilities and boundaries between PwEevee and its upstream integrations.
- Separate original PwEevee functionality from upstream-dependent functionality.
- Establish consistent internal APIs and component interfaces.
- Introduce predictable configuration and metadata formats.
- Design a centralized approach to component version detection and update tracking.
- Make upstream compatibility checks reproducible.
- Establish consistent logging, diagnostics, and error-reporting conventions.
- Reduce unnecessary coupling between the user interface, build system, and underlying components.
- Document important architectural decisions so future contributors can understand the reasoning behind them.
- Establish a reliable development environment and baseline test suite.

**Upstream integration principles:**
- Treat Chroma as the current identity of the project previously known as Spoti.pw, not as a separate integration.
- Track Chroma through its official distribution and version information rather than assuming a PwEevee-distributed package exists.
- Keep EeveeSpotify integration independently identifiable and maintainable.
- Avoid silently substituting outdated upstream versions when current version information cannot be verified.

**Completion criteria:**
- The architecture is documented.
- Core components have defined responsibilities.
- Version metadata and compatibility checks have a documented contract.
- The baseline build and test process runs reproducibly.

## Phase 3 — Core development and original features

**Status: planned**

Develop the functionality that makes PwEevee more than a wrapper around existing upstream projects.

- Build PwEevee-specific functionality directly into the v4 architecture.
- Expand customization options and provide a more consistent settings experience.
- Improve app-icon selection, previewing, and installation workflows.
- Introduce better configuration management and persistence.
- Improve first-run setup and onboarding.
- Provide clearer feedback when an operation succeeds, fails, or requires additional action.
- Improve diagnostics so users can identify problems without manually searching through unrelated logs.
- Make error handling consistent across the application.
- Improve handling of missing, outdated, incompatible, or unavailable components.
- Reduce unnecessary manual steps in common workflows.
- Review existing v3 functionality and decide what should be retained, redesigned, or retired.
- Keep original PwEevee features independent from upstream implementation details wherever practical.

**Potential areas of development:**
- A more capable customization manager.
- Better component and compatibility information.
- Improved app configuration and preference management.
- More informative installation and build results.
- Better recovery guidance for failed operations.
- Additional original features that fit the project's long-term direction.

These are development areas, not guaranteed release features. Final scope will depend on implementation feasibility and testing.

**Completion criteria:**
- Core PwEevee functionality is implemented within the new architecture.
- New features have appropriate tests.
- Existing functionality selected for retention has been checked for regressions.
- Errors and unsupported configurations are handled consistently.

## Phase 4 — User experience and interface

**Status: planned**

Design a coherent experience across the application rather than treating each feature as a separate panel.

- Redesign the application interface around a consistent visual language.
- Improve navigation and the organization of settings and customization tools.
- Make important actions easier to discover.
- Provide clear loading, success, warning, and failure states.
- Improve accessibility, readability, and layout consistency.
- Make the interface adapt appropriately to supported device sizes and iOS versions.
- Reduce unnecessary visual clutter and confusing workflows.
- Ensure that the interface reflects the actual state of the underlying components.
- Keep customization controls understandable without hiding important technical information.
- Review the experience on both older and newer supported iOS versions.

**Completion criteria:**
- Main application workflows have a consistent interface.
- Navigation and settings are understandable.
- Interface states accurately reflect application behavior.
- The redesigned experience passes the supported-device testing baseline.

## Phase 5 — Website and documentation

**Status: planned**

Create a new public-facing home for PwEevee that reflects the v4 project.

- Build the new PwEevee website from scratch.
- Do not restore the retired v3 website or its automation.
- Establish a clear project landing page explaining what PwEevee is.
- Provide straightforward installation and setup documentation.
- Publish compatibility information for supported iOS and Spotify versions.
- Explain the roles of PwEevee, Chroma, and EeveeSpotify.
- Make current downloads and older releases easy to find.
- Display release notes and important changes.
- Provide troubleshooting guidance for common installation and runtime problems.
- Document known limitations and unsupported configurations.
- Include links to the source repository, issue tracker, and contribution guidelines.
- Keep documentation synchronized with actual application behavior and released versions.

**Website principles:**
- Keep the website lightweight and maintainable.
- Avoid unnecessary dependencies and complicated publishing infrastructure.
- Use official GitHub release information as the source of truth for downloadable release assets.
- Never display an outdated download as the latest release.
- Clearly distinguish current releases from legacy releases.
- Do not claim compatibility or feature availability without verification.

**Completion criteria:**
- The new website is deployed and accessible.
- Installation, compatibility, and troubleshooting documentation is available.
- Release information and download links have been verified.
- The website does not depend on retired v3 publishing infrastructure.

## Phase 6 — Integration, compatibility, and quality assurance

**Status: planned**

Verify that the new application works reliably with its dependencies and supported environments.

- Test across supported iOS versions and device configurations.
- Validate compatibility with supported Spotify builds.
- Verify Chroma and EeveeSpotify integrations against their current upstream versions.
- Test behavior when an upstream component changes, becomes unavailable, or is incompatible.
- Validate IPA generation and packaging.
- Verify bundle identifiers, entitlements, app metadata, and required resources.
- Validate signing requirements and installation workflows.
- Test clean installations and upgrade scenarios.
- Check that application settings and customization choices behave consistently.
- Investigate regressions from earlier releases.
- Test important workflows from beginning to end.
- Review crash reports, diagnostic output, and known issues.
- Confirm that release assets are complete and usable.

**Testing priorities:**
- Application launch and basic functionality.
- Customization and settings persistence.
- Lyrics and Now Playing behavior.
- Animated album artwork.
- App-icon functionality.
- Upstream component integration.
- IPA packaging and installation.
- Compatibility across supported iOS and Spotify versions.

**Completion criteria:**
- Critical workflows pass testing.
- Known release-blocking issues are resolved.
- Supported compatibility claims are backed by actual testing.
- Release artifacts pass packaging and integrity checks.

## Phase 7 — Release preparation

**Status: planned**

Prepare the project and its release artifacts for public distribution.

- Finalize the v4 feature set.
- Review the complete change history since v3.1.6.1.
- Prepare clear release notes.
- Verify all downloadable assets.
- Generate and publish SHA-256 checksums.
- Confirm that matching Spotify base IPA assets are included when required.
- Document installation, signing, and upgrade requirements.
- Prepare troubleshooting and rollback guidance.
- Verify all release links on GitHub and the new website.
- Review repository documentation for outdated v3 references.
- Confirm that the release is reproducible from the documented build process.

**Completion criteria:**
- Release notes accurately describe the shipped changes.
- All required release assets are present and verified.
- Installation and upgrade instructions have been tested.
- No known release-blocking issues remain.

## Phase 8 — PwEevee v4.0.0 launch

**Status: planned**

Publish v4 when the required development and verification work is complete.

- Publish the v4.0.0 GitHub release.
- Publish the matching release assets and checksums.
- Publish the final release notes and installation instructions.
- Update the new website to identify v4.0.0 as the current release.
- Keep v3.1.6.1 available as a legacy release.
- Announce the release through GitHub Releases and the rebuilt website.
- Monitor incoming bug reports and compatibility feedback.
- Begin planning post-launch maintenance and follow-up improvements.

**Completion criteria:**
- v4.0.0 is publicly available.
- Release assets and documentation are verified.
- The website points to the correct release.
- The legacy v3.1.6.1 release remains accessible.

## Development principles

These principles apply throughout the v4 development process.

- **Open source:** Keep the project transparent and maintainable.
- **Reliability:** Prefer verified functionality over rushed feature additions.
- **Maintainability:** Avoid unnecessary complexity and tightly coupled components.
- **Upstream awareness:** Track upstream changes and compatibility rather than relying on stale assumptions.
- **Original development:** Build meaningful PwEevee-specific functionality instead of only repackaging existing projects.
- **User experience:** Make common tasks understandable and predictable.
- **Documentation:** Keep public instructions consistent with the actual implementation.
- **Honest compatibility:** Never claim a device, iOS version, or Spotify build is supported without appropriate verification.

## What this roadmap is not

- It is not a promise that every proposed idea or potential feature will ship.
- It is not a countdown or an estimated release window.
- It is not a list of completed work.
- It does not guarantee compatibility with every iOS version, device, or Spotify release.
- It does not guarantee that upstream projects will maintain their current APIs or distribution methods.
- It does not mean that a phase is complete simply because implementation has started.

**Phase 1 is the only phase currently marked as in progress.** All other phases remain planned until their work actually begins. A phase will only be marked complete after its completion criteria have been met and verified.

The goal of PwEevee v4 is to establish a stronger foundation for long-term development, deliver meaningful original functionality, and make the overall project easier to use, maintain, and contribute to.
