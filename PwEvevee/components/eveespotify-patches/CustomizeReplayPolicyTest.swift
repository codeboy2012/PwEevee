import Foundation

// Standalone regression harness for the EeveeSpotify cold-cache gate.
// Compile with: swiftc CustomizeReplayPolicy.swift CustomizeReplayPolicyTest.swift -o customize-policy-test
//
// The PRE-FIX predicates are reproduced here as `legacyShouldAnswer` and
// `legacyReplay`, so the same assertions fail against the old behaviour and pass
// against the new one.

var passed = 0
var failed = 0

func check(_ name: String, _ got: Bool, _ want: Bool) {
    if got == want {
        passed += 1
        print("ok   \(name)")
    } else {
        failed += 1
        print("FAIL \(name): got \(got), want \(want)")
    }
}

// Old behaviour: "premium patching is on" was the whole condition, so customize
// was always answered from cache — with Data() when the cache was cold.
func legacyShouldAnswer(isCustomize: Bool, isPatching: Bool) -> Bool {
    isCustomize && isPatching
}

// Old 304 replay expression: `cachedCustomizeData ?? UserDefaults.cachedCustomizeData`.
// A nil in-memory cache falls back to a persisted copy without checking its
// length, so an empty body is "found" and synthesised into a 200.
func legacyReplay(inMemory: Data?, persisted: Data?) -> Data? {
    inMemory ?? persisted
}

let body = Data([0x08, 0x01, 0x12, 0x03, 0x61, 0x62, 0x63])
let other = Data([0x08, 0x02])
let empty = Data()

let cases: [(String, Data?, Data?, Bool)] = [
    ("cold cache (no memory, no disk) must go out", nil, nil, false),
    ("cold cache with empty in-memory body must go out", empty, nil, false),
    ("cold cache with empty persisted body must go out", nil, empty, false),
    ("empty in-memory but valid persisted may replay", empty, body, true),
    ("valid in-memory may replay", body, nil, true),
    ("valid persisted only may replay", nil, body, true),
    ("valid both may replay", body, body, true),
]

print("== fixed predicate ==")
for (name, mem, disk, want) in cases {
    check(name, CustomizeReplayPolicy.canReplay(inMemory: mem, persisted: disk), want)
}

print("== replayData: the body a replay may actually deliver ==")
check("nothing cached yields no body",
      CustomizeReplayPolicy.replayData(inMemory: nil, persisted: nil) == nil, true)
check("an empty in-memory body is not a body",
      CustomizeReplayPolicy.replayData(inMemory: empty, persisted: nil) == nil, true)
check("an empty persisted body is not a body",
      CustomizeReplayPolicy.replayData(inMemory: nil, persisted: empty) == nil, true)
check("a persisted-only warm cache yields that body",
      CustomizeReplayPolicy.replayData(inMemory: nil, persisted: body) == body, true)
check("an empty in-memory body falls through to a valid persisted one",
      CustomizeReplayPolicy.replayData(inMemory: empty, persisted: body) == body, true)
check("the in-memory copy wins when both are valid",
      CustomizeReplayPolicy.replayData(inMemory: body, persisted: other) == body, true)

print("== forwardsUntouched: a bodiless 304 belongs to Spotify ==")
check("304 with no replay passes through",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 304, replay: nil), true)
check("304 with an empty replay passes through",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 304, replay: empty), true)
check("304 with a replayed body is answered by us",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 304, replay: body), false)
check("a 200 with no body is not a revalidation answer",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 200, replay: nil), false)
check("a 200 with a body takes the ordinary path",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 200, replay: body), false)

print("== negative control: pre-fix predicates ==")
// The pre-fix code answered every customize while patching was on, i.e. the
// cold-cache case returned true. Asserting the correct answer must fail there.
var controlFailures = 0
for (_, _, _, want) in cases {
    if legacyShouldAnswer(isCustomize: true, isPatching: true) != want { controlFailures += 1 }
}
check("pre-fix predicate disagrees with the cold-cache expectations",
      controlFailures >= 3, true)
check("pre-fix predicate answers a cold cache from an empty body",
      legacyShouldAnswer(isCustomize: true, isPatching: true), true)

// The 304 hole: the old expression "finds" an empty persisted body, so the hook
// synthesises a 200 and delivers zero bytes — the very symptom under repair.
check("pre-fix 304 lookup fabricates a body from an empty persisted copy",
      legacyReplay(inMemory: nil, persisted: empty) != nil, true)
check("pre-fix 304 lookup would deliver zero bytes",
      (legacyReplay(inMemory: nil, persisted: empty)?.isEmpty ?? false), true)
check("fixed replay refuses that same input",
      CustomizeReplayPolicy.replayData(inMemory: nil, persisted: empty) == nil, true)

// The old completion fallback delivered `replay ?? Data()` for every customize without a
// buffered body — a 304 included — so a cold cache completed as a successful empty reply.
func legacyCompletionBody(hasBuffer: Bool, replay: Data?) -> Data? {
    hasBuffer ? nil : (replay ?? Data())
}
check("pre-fix completion fabricates an empty body for a 304 with no cache",
      legacyCompletionBody(hasBuffer: false, replay: nil) == empty, true)
check("fixed policy refuses to complete that 304 with a body",
      CustomizeReplayPolicy.forwardsUntouched(statusCode: 304, replay: nil), true)

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
