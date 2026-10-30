# EeveeSpotify patches carried by PwEevee

PwEevee ships EeveeSpotify as a **prebuilt component** (`../Evevee Spotify/component/`).
Upstream's binary is pinned byte-for-byte in its manifest, so a fix that has to live in
EeveeSpotify can only ship if the component is rebuilt. This folder holds the minimal
patch we carry, so anyone can reproduce that build.

## cold-cache-gate.patch

Applies to [EeveeSpotify Reincarnated] `ce09a4d` (the snapshot the pinned 7.0.0 binary
was built from, proven by an unchanged inventory of 531 human-readable strings).

It changes one decision: *may a `v1/customize` response be answered from what we already
have?* Upstream answered "yes, while premium patching is on" — true even when nothing has
been rewritten yet, which turns a cold cache into a zero-byte 200 (or a cancelled task)
and leaves Spotify with no usable configuration.

The gate now also requires a non-empty rewritten body, shared through
`CustomizeReplayPolicy` by every place that makes the decision:

- `SpotifyResponsePatcher.shouldHandleCustomize` → `shouldBlock` → `blockedResponseData`
- `SessionProtection`'s `URLSessionTaskResumeHook` (which cancels post-startup re-fetches)
- both `URLSession` delegates' 304 handlers, and their bodiless-completion fallbacks

With a cold cache none of them fires, so the real fetch goes out and is patched on arrival
(the same path the first 30 seconds take). With a warm cache they behave exactly as before.

### Why the replay paths had to change as well

Gating only the *decision* was not sufficient. Three replay sites still read the cache
with a nil-check (`cachedCustomizeData ?? UserDefaults.cachedCustomizeData`), which treats
an empty `Data` as a usable body:

| Site | What went wrong before |
|---|---|
| `blockedResponseData` | gate accepted a persisted-only warm cache, but the reply only read the in-memory copy, so it fell through to `Data()` |
| both 304 handlers | synthesised a `200` around an empty persisted copy and delivered zero bytes |
| bodiless completion | same fallback, same hole |

`CustomizeReplayPolicy.replayData(inMemory:persisted:)` now returns the body that may be
delivered (in-memory first, then persisted, non-empty only), and
`SpotifyResponsePatcher.replayableCustomizeData` is the single accessor all of them use.

### The completion path

Gating the response was still not enough. With nothing to replay, the `304` passed through
the response hook, but the *completion* hook then took its "no buffered body" fallback and
delivered `Data()` with a nil error — a successful empty customize reply, one callback
later. Both delegate hooks now mark that task
(`markCustomizePassedThrough` / `consumeCustomizePassThrough`, lock-guarded in
`SpotifyResponsePatcher`) and forward Spotify's own completion untouched; the policy
decision is `CustomizeReplayPolicy.forwardsUntouched(statusCode:replay:)`, and
`didReceiveData` forwards any bytes for a marked task instead of swallowing them. The ObjC
layer does the same with `kNotModifiedKey` in `replayFor`/`complete`.

Both replay paths log what they delivered (`Replayed customize over 304 (N bytes)`,
`Customize answered from replay cache (N bytes)`, `Customize 304 passed through untouched`),
so a device capture can distinguish a real response from a fabricated one.

## Building the patched component

```bash
git clone https://github.com/jaydenjcpy/EeveeSpotifyReincarnated eevee && cd eevee
git checkout ce09a4d
git apply /path/to/cold-cache-gate.patch

# EeveeSwiftProtobuf.framework must be present in $(THEOS)/lib/iphone/rootless/
# (copy it out of the pinned component, or run `make build-eeveeswiftprotobuf`)
export THEOS=$HOME/theos            # Theos vendors Orion under vendor/orion
make FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless \
     TARGET_CODESIGN=codesign TARGET_CODESIGN_FLAGS='--force --sign -'

cp .theos/obj/EeveeSpotify.dylib "Evevee Spotify/component/package/dynamic-libraries/"
# then refresh the sha256/size entry in "Evevee Spotify/component/manifest.json"
```

The ad-hoc signature Theos applies is what the rest of the pipeline expects; the app is
re-signed by whoever installs it.

Verified on 2026-10-29: applying the patch to a clean `ce09a4d` clone reproduces the five
source files byte-for-byte, and that clone builds a 3,988,816 B `arm64` dylib on its own
(sha256 `e25b4456…`; the pinned build is `dbad4359…` — the two differ only in embedded
build paths, which the compiler records in the binary).

## CustomizeReplayPolicyTest.swift

Standalone `swiftc` harness for the predicate and for the body selection:

```bash
# swiftc only allows top-level code in main.swift, so the harness is compiled as one
cp CustomizeReplayPolicy.swift CustomizeReplayPolicyTest.swift /tmp/
mv /tmp/CustomizeReplayPolicyTest.swift /tmp/main.swift
swiftc /tmp/CustomizeReplayPolicy.swift /tmp/main.swift -o /tmp/customize-policy-test
/tmp/customize-policy-test
```

It covers cold cache (no body / empty body in memory or on disk), warm cache on either
layer, the resolution order, the bodiless-`304` pass-through decision, and negative controls
that reproduce the pre-fix predicate, the old 304 lookup and the old completion fallback —
the lookup is shown fabricating a zero-byte body from an empty persisted copy.
Expected output: `25 passed, 0 failed`. Forcing `forwardsUntouched` to the old behaviour
gives `22 passed, 3 failed`.
