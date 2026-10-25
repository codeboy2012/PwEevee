# Feature matrix — PwEevee vs Chroma(SpoTi.pw) vs Taurus vs EeveeSpotify

Evidence levels used below (kept deliberately strict — this project has been burned
by tests that compared a value to itself before):

- **[A] Artifact-verified** — measured directly on the audited IPAs (`audit/ipas/evidence/`), or byte-compared in this repository. The strongest claim here.
- **[C] Code-verified** — the feature's source lives in this repo and is covered by a passing test or harness check. No runtime device test, so UI behavior claims stop short of "runs on device".
- **[D] Documented** — asserted by project docs/release notes; plausible, not re-verified here.
- **[U] Upstream-claimed** — claimed by the other project's docs/releases; this repo did not independently verify it.
- **[N] Not available / limitation** — with the reason.

Unless a cell says [A]/[C], treat it as [U] for the other projects. We do not claim
superiority on anything we could not test at runtime.

## Player and looks

| Feature | PwEevee | Chroma/SpoTi.pw | Taurus 0.60.4 | Eevee standalone |
|---|---|---|---|---|
| Liquid Glass redesign (iOS 26+, `UIGlassEffect`) | [C] `Redesigned/` layer, gated by `SGRedesignAvailable()` (iOS<26 falls back to native look automatically) | [U] glass design language | [D] | [N] not a UI mod |
| Spotify-own screens (native look) with tweaks | [C] `Native/` layer, same classes hooked under SG* names | [U] | [D] | [N] |
| Two looks never run together (one stored key, forced off under iOS<26) | [C] `Shared/…/SGUIMode` | [N] single look per fork | [N] | [N] |
| Full-screen player redesign, glass now-playing bar | [C] `Redesigned/Player`, `Redesigned/NowPlayingBar` | [U] | [D] | [N] |

## Lyrics and lock screen

| Feature | PwEevee | Chroma | Taurus | Eevee |
|---|---|---|---|---|
| Word-synced (karaoke) lyrics | [C] `Shared/Lyrics` (KaraokeTiming/Source; instrumental-break dots; pronunciation+translation) + Eevee 7.0.0 `KaraokeBackgroundShader.metallib` in the unified deb | [U] word-sync exists upstream | [U] | [U] word-sync karaoke (7.0) |
| Multi-provider lyrics merge & fallback | [C] `LyricsSources` (Apple TTML via BiniLyrics/Unison, Musixmatch richsync, NetEase yrc, LrcLib floor; donor-track 200 trick) | [U] fewer providers | [U] | [U] |
| Lock screen karaoke line | [C] `LockScreenLyrics` | [U] | [U] | [N] |
| Animated lock-screen artwork (Canvas / Apple Music clip, iOS 26+) | [C] `LockScreenArtwork` (canonicalized from `harness/lockart/` checks on the Mac) | [U] | [U] | [N] |
| Custom lyrics source ordering UI | [C] `LyricsSourcesPage` | [U] | [U] | [N] |

## Audio, haptics, Live Activity

| Feature | PwEevee | Chroma | Taurus | Eevee |
|---|---|---|---|---|
| Speed & pitch in player menu | [C] `Shared/Player/SpeedPitch` (Apple time/pitch unit rebind; simulator-tested) | [U] | [U] | [N] |
| Audio effects engine (equalizer/bass/etc., libbs2b + EEL2) | [C] `Shared/AudioEffects` (harness tested on the Mac) | [U] | [U] | [N] |
| Music Haptics + control haptics | [C] `Shared/Haptics` (Core Haptics analyzer scored on the Mac) | [U] | [U] | [N] |
| Live Activity + Dynamic Island (3 views, queue tap-skip, sleep timer) | [A]+[C] `SpotifyGlassLiveActivity.appex` present in PwEevee IPA (audit §4) and the widget sources are in-repo; same name as chroma's appex (shared origin) | [A] `SpotifyGlassLiveActivity.appex` present in chroma β.3 | [A] different extension (`TaurusOpenSpotify.appex`) shipped instead | [N] |
| App-Groups widget fix (dylib) | [A] `SpotifyGlassAppGroups.dylib` shipped (weak-injected) | [A] present (different bytes, 67,936 B vs PwEevee's 86,592 B) | [A] identical bytes to PwEevee's | [N] |

## Library surfaces

| Feature | PwEevee | Chroma | Taurus | Eevee |
|---|---|---|---|---|
| Decluttered Home/Search/Library/Playlist (allow-lists, glass cards) | [C] `Redesigned/Home|Search|Library|Playlist` (issue #20 chips regression restored in 0.21) | [U] | [U] | [N] |
| Artist block (skip-on-start) | [C] `Shared/ArtistBlock` | [U] | [U] | [N] |
| Privacy: telemetry blocking + counters | [C] `Shared/Privacy` | [U] | [U] | [N] |
| Spotify remote-flags explorer (All flags / Labs pages) | [C] `Shared/Flags` | [U] | [U] | [N] |
| Double-tap gesture zones on player | [C] `Shared/Gestures` | [U] | [U] | [N] |

## Premium-spoofing and ads (verification posture)

| Feature | PwEevee | Chroma | Taurus | Eevee |
|---|---|---|---|---|
| Spoof Premium (SpoTi.pw style) **and** Eevee spoof — mutually exclusive rows, deterministic conflict resolution | [C] `pweevee-premium-exclusivity-tests.pl` (47 checks) + `SGPremiumResolveConflict` | [U] its own premium patch | [U] | [U] Eevee premium spoof |
| Ad block (removes ads) | [C] `Shared/AdBlock` network layer + C++ core path documented | [U] | [U] | [N] (ad paths live in Taurus/SpoTi.pw lineage) |
| **Song offline downloads** | **[N] on stock iOS 18 non-jailbreak — server-enforced, no PwEevee code path claims this; tracker #2 verdict = platform limitation** (document in README/website) | [N] same server enforcement | [N] same | [U] "downloads" claims are not verifiable here; do not advertise them as working because UI shows it |
| **Premium feature guaranteed** | **[N] no.** All premium behavior is a client-side spoof of product state; anything the server checks stays locked. Never advertise server-enforced features as working | same posture | same | same |

## Packaging, injection, update delivery

| Feature | PwEevee | Chroma | Taurus | Eevee |
|---|---|---|---|---|
| Injection model in shipped IPA | [A] 5 strong `@executable_path/Frameworks` LC_LOAD_DYLIB injections + 3 weak `@rpath` leftovers | [A] 0 strong, 2 weak; runtime swizzling, no Substrate dep (per 1.1.0-beta analysis) | [A] 0 strong, 3 weak (+SpotifyAudioProbe 536,352 B, Taurus-only) | [D] standalone deb via MobileSubstrate filter |
| CydiaSubstrate framework in IPA | [A] shipped bytes identical to Taurus's (`748d129f…`); repo pin reconciled + hash-pinned in manifest | [A] absent | [A] present (identical to PwEevee — shared lineage) | [U] via MobileSubstrate runtime |
| Eevee component bundled | [A] `EeveeSpotify.dylib` + Orion + EeveeSwiftProtobuf shipped in α.2 unified IPA; 1.1.0-beta unified deb carries Eevee **7.0.0** + Orion 1.0.2, deb-native paths | [A] absent | [A] absent | [A] its own deb |
| Alternate app icons | [C] `patch-alternate-icon.pl` registers the PwEevee brand icon via `CFBundleAlternateIcons` (host-declared `~ipad` mirrored), idempotent, hash-pinned, validate-gated | [A] chroma flips `CFBundleIconName`→`SGPrimaryIcon` while keeping stock build metadata (alternate-icon API) | [A] strips Spotify build metadata, keeps default icon name | [U] icon ZIPs |
| Watch app | [A] removed (PwEevee/Taurus/chroma) | [A] removed | [A] removed | [N] — position is a packaging decision, all forks agree |
| Update checker | [C] project-owned API + FALLBACK `api.github.com/repos/codeboy2012/PwEevee/releases?per_page=20`; failures degrade gracefully; rebrand tests pin the endpoint; no upstream endpoints in code | [U] its own site API | [U] | [U] |
| Build reproducibility tooling | [C] store-only ZIP (fixed DOS times), canonical bplist writer, Mach-O injector with slack checks, 13 test suites, manifest hash pins | [U] | [U] | [U] |

## Compatibility

| | Spotify base | Min iOS | Notes |
|---|---|---|---|
| PwEevee α.2 unified IPA | 9.1.90 (build 919002269) | 16.1 | identical across all four audited IPAs — nobody rebundles the base |
| PwEevee 1.1.0-beta unified deb | 9.1.78 (917802214) | 16.1 (`firmware >= 16.1`) | deb route: `com.pweevee.unified`; conflicts/replaces com.eevee.spotify, com.spotipw, dev.theos.orion |
| Redesign look | any (feature-gated) | **iOS 26+** for Liquid Glass | under iOS<26 the switch reads "Needs iOS 26" and stored key is preserved for an update |
| LiveContainer host | any | — | **icon change crashes upstream** (`Need an imageRef`) — mitigation: host detection + explicit unsupported notice (open, on roadmap) |
| Offline downloads iOS 18 | — | — | server-enforced; not fixable client-side; documented as expected limitation |

## Source-of-truth index

- Artifact evidence: `audit/ipas/evidence/<stock|pweevee|taurus|chroma>/` (filelists, Info.plist dumps, complete Mach-O load-command listings, sha256s).
- Audit verdicts + tracker issue #1/#2: `audit/audit-report.md` §6, `audit/findings.json`.
- Component-level facts of the unified deb: `docs/PWEEVEE-1.1.0-BETA.md`.
- Feature sources: `docs/tweaks.md` (layer/feature map of the tweak), `Spotipw/tweak/Sources/`.
- Test evidence: `test-report.md` (this directory).
