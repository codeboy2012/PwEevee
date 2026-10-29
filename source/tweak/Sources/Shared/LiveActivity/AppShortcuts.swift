// Spotify's App Shortcuts: what Siri answers to, what the Shortcuts app shows under Spotify before any
// shortcut is made, and what the Action button lists under Shortcut > Spotify. An app has one provider, and
// Spotify 9.1.78 has none of its own. Tweak only: the system reads it from the App Intents metadata
// scripts/build-extension.sh makes for Spotify, and a widget extension may not carry one.
// Every phrase names the app; the system's own media commands already own "next song" and "pause".
import AppIntents
import Foundation

// What every intent below posts for the tweak to act on; Shortcuts.m observes it and runs the player. The
// intents run in Spotify's own process, where the tweak is loaded, so a notification reaches it in-process.
let SGShortcutActionNotification = Notification.Name("SGShortcutAction")

@available(iOS 17.0, *)
struct SGLikeIntent: AppIntent {
    static let title: LocalizedStringResource = "Like This Song"
    static let description = IntentDescription("Adds the song playing to Liked Songs.")

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "like")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SGPlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the song playing.")

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "toggle")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SGNextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song.")

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "next")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SGPreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Skips to the previous song.")

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "previous")
        return .result()
    }
}

@available(iOS 17.0, *)
enum SGKaraokeMode: String, AppEnum {
    case sing, karaoke

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Karaoke")
    static let caseDisplayRepresentations: [SGKaraokeMode: DisplayRepresentation] = [
        .sing: "Sing",
        .karaoke: "Karaoke",
    ]
}

@available(iOS 17.0, *)
struct SGSingIntent: AppIntent {
    static let title: LocalizedStringResource = "Karaoke"
    static let description = IntentDescription("Turns Sing on, the song's vocals turned down.")

    @Parameter(title: "Mode")
    var mode: SGKaraokeMode

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "sing")
        return .result()
    }
}

@available(iOS 17.0, *)
enum SGSleepLength: String, AppEnum {
    case fifteen = "15", thirty = "30", sixty = "60"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer Length")
    static let caseDisplayRepresentations: [SGSleepLength: DisplayRepresentation] = [
        .fifteen: "15 minutes",
        .thirty: "30 minutes",
        .sixty: "1 hour",
    ]
}

@available(iOS 17.0, *)
struct SGSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Sleep Timer"
    static let description = IntentDescription("Pauses Spotify after a time.")

    @Parameter(title: "Length")
    var length: SGSleepLength

    init() {}

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: SGShortcutActionNotification, object: "sleep:\(length.rawValue)")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SGAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SGLikeIntent(), phrases: [
            "Like this song in \(.applicationName)",
            "Add this song to Liked Songs in \(.applicationName)",
        ], shortTitle: "Like This Song", systemImageName: "heart")
        AppShortcut(intent: SGPlayPauseIntent(), phrases: [
            "Play or pause \(.applicationName)",
        ], shortTitle: "Play or Pause", systemImageName: "playpause")
        AppShortcut(intent: SGNextTrackIntent(), phrases: [
            "Skip this song in \(.applicationName)",
            "Next track in \(.applicationName)",
        ], shortTitle: "Next Track", systemImageName: "forward")
        AppShortcut(intent: SGPreviousTrackIntent(), phrases: [
            "Previous track in \(.applicationName)",
        ], shortTitle: "Previous Track", systemImageName: "backward")
        AppShortcut(intent: SGSingIntent(), phrases: [
            "\(\.$mode) Karaoke in \(.applicationName)",
            "Sing along in \(.applicationName)",
        ], shortTitle: "Karaoke", systemImageName: "music.mic")
        AppShortcut(intent: SGSleepTimerIntent(), phrases: [
            "Set a sleep timer in \(.applicationName)",
            "Sleep timer \(\.$length) in \(.applicationName)",
        ], shortTitle: "Sleep Timer", systemImageName: "moon.zzz")
    }
}
