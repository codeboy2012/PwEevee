# Licensing and provenance

Read this before redistributing any PwEevee artifact. Confidence labels follow the
same convention as `feature-matrix.md`: **[A] artifact-verified**, **[C] code-verified
in this repo**, **[D] documented by a project (not independently verified here)**.

## Official sources vs distribution channels

| Name | Role | Official link | What this repo owns |
|---|---|---|---|
| **PwEevee** (this project) | integration + packaging + distribution | `https://github.com/codeboy2012/PwEevee` (verified live: title "Unified SpoTi.pw + EeveeSpotify project…", latest stable v2.0.0, v2.2.0-pre unified build) | its own build system, tests, website, docs, brand artwork, and the rebranding of the user-facing surface |
| **SpoTi.pw / Chroma** | upstream tweak lineage of spotifyglass | `https://github.com/skopevoj/spoti.pw` (official source) | **nothing** — label every Chroma feature as upstream, do not imply PwEevee owns or recreated it |
| **Taurus** | separate competitor fork of the same lineage | `https://github.com/samj-exe/taurus` (verified live, official) | **nothing** |
| **EeveeSpotify** | upstream Eevee tweak | `https://github.com/SideloadLabs/EeveeSpotifyReincarnated` (verified live; states the original repo was DMCA-taken down and **ships no IPAs in the repo itself**) | **nothing** |
| **EeveeIPA** | community **IPA prebuilt distribution** | `https://github.com/estrogencat/EeveeIPA` (verified live) | nothing; it is *not* Eevee's source repo, and the website labels it as such |
| **SideloadLabs AltSource** | IPA distribution list PwEevee reads but does not own/mirror | `https://github.com/SideloadLabs/SideloasLabs-AltSource` | nothing |

Rule applied everywhere in this repo: a GitHub link is either labeled as an **official
source** or as a **distribution/prebuilt channel**, never blurred. Examples: the
website footer says "EeveeIPA (prebuilt IPAs, not Eevee's source)"; the update
checker's fallback endpoint is the *official PwEevee* repo only.

## What license state is actually verified here

**[C] This repository's own build system, tests, website code, docs, and generated
brand artwork (PwEevee circle-and-chevron mark, icon family, social card):** authored
in this project. The icon manifest itself records
`license: "PwEevee project artwork; not derived from Spotify or any upstream project"`,
and the brand-asset test suite enforces both hash-pin and that wording.

**[A] Shipped third-party binaries (from the Oct 24 forensic audit, `audit/findings.json`):**
| Component | In unified IPA | Provenance evidence |
|---|---|---|
| `spotifyglass.dylib` | `e633f924…` / 1,816,144 B | byte-level pin equals repo HEAD manifest (D-2 fixed, tested) |
| `CydiaSubstrate.framework` | `748d129f…` / 377,952 B | **byte-identical to Taurus 0.60.4's** copy; the repo pin was `3c691ec7…` / 403,200 B → D-3 now recorded as a hash pin + permanent test; the artifact-vs-pin reconciliation remains a maintainer release decision (re-cut from pin, or refresh pin and document) |
| `SpotifyGlassAppGroups.dylib` | `64f238e1…` / 86,592 B | identical bytes also appear in Taurus (shared lineage) |
| `EeveeSpotify.dylib` | `631d4f17…` / 2,563,648 B | upstream Eevee component; the 1.1.0-beta unified deb ships Eevee **7.0.0** "byte-identical to upstream deb" per `docs/PWEEVEE-1.1.0-BETA.md` [D] |
| `Orion.framework`, `EeveeSwiftProtobuf.framework` | pinned hashes in manifests | manifest-verified each run |
| `SpotifyAudioProbe.dylib` | **absent in PwEevee**; Taurus-only (`fcbf7187…`, 536,352 B) | — |

**[D] Upstream licenses referenced but not re-audited here:** the exact license
files of SpoTi.pw, Taurus and EeveeSpotify live in their own repositories (linked
above) — before any redistribution beyond personal use, read them there. This suite
does not claim a license review of upstream code, and no upstream code was copied
into this repository's sources during this phase: integration is by inert dylib
staging + hash pins, plus PwEevee's own integration layer.

**[A] Not owned, never implied:** Spotify AB's app, artwork, trademarks. The
website's footer states non-affiliation explicitly; `brand-asset-tests.pl` fails
the build if any Spotify-marked *image asset* is wired into the website or if the
rendered index references a Spotify-marked file name.

## Explicit non-permissions (no basis found)

- No permission to redistribute Eevee's or Chroma's IPAs under PwEevee's name.
- No claim that server-enforced Spotify features (especially **offline downloads
  on iOS 18 without jailbreak**) were unlocked; tracker #2 verdict is platform
  limitation.
- No claim of endorsement by, or connection to, Spotify AB, Apple, spoti.pw,
  EeveeSpotify or SideloadLabs.

## Re-rendered website links (this phase)

`website-src/layout.html` → `website/index.html` (via `render-site.pl`, watched by
`website-tests.pl`, 2827 checks passing): Repositories column now lists
spoti.pw, EeveeSpotify, **Taurus**, **EeveeIPA (labeled as a prebuilt channel)**,
SideloadLabs AltSource; every URL was fetched live during this phase before being
wired in (`architecture.md` documents the checker that verifies them).
