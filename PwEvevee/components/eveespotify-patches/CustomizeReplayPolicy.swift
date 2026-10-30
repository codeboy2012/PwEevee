import Foundation

// Single decision for "may this customize be answered from what we already have?".
//
// Both the response patcher (shouldBlock / blockedResponseData) and the
// session-protection hook (cancel customize re-fetches) used to answer that
// question with "is premium patching on?", which is true even when nothing has
// been rewritten yet. On a cold cache that produced a zero-byte 200 (or a
// cancelled task) and Spotify was left with no usable configuration at all.
//
// A body only counts when it is non-empty: an empty Data is a failed rewrite,
// not a configuration to replay. Every replay path — the block, the 304
// synthesis, and the bodiless-completion fallback — asks this type, so the
// emptiness rule cannot drift between them again.
enum CustomizeReplayPolicy {
    /// The body that may be replayed, or nil when there is nothing usable.
    /// In-memory wins over the persisted copy, and an empty body on either
    /// layer falls through to the other before giving up.
    static func replayData(inMemory: Data?, persisted: Data?) -> Data? {
        if let inMemory, !inMemory.isEmpty { return inMemory }
        if let persisted, !persisted.isEmpty { return persisted }
        return nil
    }

    static func canReplay(inMemory: Data?, persisted: Data?) -> Bool {
        replayData(inMemory: inMemory, persisted: persisted) != nil
    }

    /// Whether a customize response has to reach Spotify untouched. A 304 is
    /// Spotify's own revalidation answer; replacing it with `Data()` on the
    /// completion path is the same fabricated success as blocking a cold cache,
    /// only one layer down. A real 200 with no bytes is left to the ordinary
    /// fallback — there is no cached config to stand in for it either way, but
    /// the 304 is the case where the server has explicitly said "use what you
    /// have", so nothing may be invented.
    static func forwardsUntouched(statusCode: Int, replay: Data?) -> Bool {
        statusCode == 304 && (replay?.isEmpty ?? true)
    }
}
