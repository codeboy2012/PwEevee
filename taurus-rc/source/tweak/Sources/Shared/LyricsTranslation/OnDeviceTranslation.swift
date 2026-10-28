// The two ways to translate a song on the iPhone itself, for LyricsTranslation.h: Apple's Translation
// framework (iOS 26, with the languages downloaded in the Translate app) and Apple Intelligence's language
// model (iOS 26, on the iPhones that have it). Both are Swift only. Nothing leaves the phone.
import Foundation
import FoundationModels
import NaturalLanguage
import Translation
import os

@objc(SGOnDeviceTranslation)
public final class SGOnDeviceTranslation: NSObject {
    private static let log = Logger(subsystem: "spotifyglass", category: "translation")
    // The model asked fresh for each run of this many lines, so a long song stays inside its context, with room
    // for this many tokens of answer a line: a model that runs on stops there instead of filling the context.
    private static let chunkLines = 12
    private static let tokensPerLine = 60

    private static func finish(_ done: @escaping ([String]?, String?) -> Void, _ lines: [String]?, _ error: String?) {
        DispatchQueue.main.async { done(lines, error) }
    }

    private static func name(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    // A line's language when the recognizer is sure of it; short lines ("yeah") guess wildly otherwise.
    private static func languageOf(_ line: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(line)
        guard let (found, chance) = recognizer.languageHypotheses(withMaximum: 1).first, chance >= 0.8 else { return nil }
        return Locale.Language(identifier: found.rawValue)
    }

    // The language to translate from: the one most of the song's other-language lines are in, so a K-pop song
    // half in English is Korean; else the whole song's.
    private static func sourceLanguage(_ lines: [String], target: Locale.Language) -> Locale.Language? {
        var counts: [String: (Locale.Language, Int)] = [:]
        // Each line once, so a repeated chorus does not outvote the verses.
        for line in Set(lines.map { $0.lowercased() }) where !line.isEmpty {
            guard let language = languageOf(line), !same(language, target), let code = language.languageCode?.identifier else { continue }
            counts[code] = (counts[code]?.0 ?? language, (counts[code]?.1 ?? 0) + 1)
        }
        if let most = counts.values.max(by: { $0.1 < $1.1 }) { return most.0 }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(Set(lines).joined(separator: "\n"))
        guard let found = recognizer.dominantLanguage, found != .undetermined else { return nil }
        return Locale.Language(identifier: found.rawValue)
    }

    private static func same(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode
    }

    // MARK: Translation framework

    @objc public static var translationAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    // One translation per line, "" for a line with no words; or nil and why not.
    @objc public static func translate(_ lines: [String], to languageTag: String, done: @escaping ([String]?, String?) -> Void) {
        guard #available(iOS 26.0, *) else { return finish(done, nil, "Translating on this iPhone needs iOS 26.") }
        let target = Locale.Language(identifier: languageTag)
        guard let source = sourceLanguage(lines, target: target) else { return finish(done, nil, "The song's language could not be told from its words.") }
        if same(source, target) { return finish(done, nil, "The song is already in \(name(target)).") }
        Task {
            switch await LanguageAvailability().status(from: source, to: target) {
            case .unsupported:
                return finish(done, nil, "Apple's Translate does not translate \(name(source)) into \(name(target)).")
            case .supported:
                return finish(done, nil, "Download \(name(source)) and \(name(target)) in Settings > Apps > Translate > Languages, then try again.")
            case .installed:
                break
            @unknown default:
                break
            }
            // Lines already in the target language are left as they are, not run through the other language.
            let requests = lines.enumerated().compactMap { index, line in
                line.trimmingCharacters(in: .whitespaces).isEmpty || line == "♪" || languageOf(line).map({ same($0, target) }) == true ? nil
                    : TranslationSession.Request(sourceText: line, clientIdentifier: String(index))
            }
            let started = Date()
            // A first ask can fail while Translate loads its languages; the second, a moment later, finds them in.
            for attempt in 1...2 {
                do {
                    let session = TranslationSession(installedSource: source, target: target)
                    var out = [String](repeating: "", count: lines.count)
                    for response in try await session.translations(from: requests) {
                        if let id = response.clientIdentifier, let index = Int(id) { out[index] = response.targetText }
                    }
                    log.notice("translate: \(source.minimalIdentifier, privacy: .public) to \(target.minimalIdentifier, privacy: .public), \(requests.count) lines in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
                    return finish(done, out, nil)
                } catch {
                    log.error("translate: \(source.minimalIdentifier, privacy: .public) to \(target.minimalIdentifier, privacy: .public), try \(attempt) failed: \(String(describing: error), privacy: .public)")
                    if attempt == 2 { return finish(done, nil, "Apple's Translate could not translate the song (\(error.localizedDescription)).") }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    // MARK: Apple Intelligence

    @available(iOS 26.0, *)
    private static var model: SystemLanguageModel {
        // Lyrics are often explicit: the guardrails for changing text the user already has, not for writing new.
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    @objc public static func appleIntelligenceAvailable(_ languageTag: String) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        let target = Locale.Language(identifier: languageTag)
        return model.availability == .available && model.supportedLanguages.contains { same($0, target) }
    }

    @objc public static func translateWithAppleIntelligence(_ lines: [String], to languageTag: String, song: String?, progress: @escaping ([String]) -> Void,
                                                            done: @escaping ([String]?, String?) -> Void) {
        guard #available(iOS 26.0, *) else { return finish(done, nil, "Apple Intelligence needs iOS 26.") }
        let language = name(Locale.Language(identifier: languageTag))
        // Only the lines given text ("" for those translated already or with no words), 12 to a batch. A batch
        // the model refuses is asked again in halves (translateSplitting), and one that fails is left out while
        // the rest go on, so an explicit line costs only itself.
        let wanted = lines.indices.filter { !lines[$0].isEmpty }
        Task {
            var out = [String](repeating: "", count: lines.count)
            var before: [(String, String)] = []   // the batch just done, lines and translations, for the next one's sense
            var failure: Error?
            var translated = 0
            let started = Date()
            for first in stride(from: 0, to: wanted.count, by: chunkLines) {
                let indices = Array(wanted[first..<min(first + chunkLines, wanted.count)])
                let chunkStarted = Date()
                do {
                    let chunk = indices.map { lines[$0] }
                    let answer = try await translateSplitting(chunk, into: language, song: song, before: before, failure: &failure)
                    for (index, translation) in zip(indices, answer) where translation != nil {
                        out[index] = translation!
                        translated += 1
                    }
                    before = zip(chunk, answer).compactMap { line, translation in translation.map { (line, $0) } }
                    log.notice("intelligence: \(first + indices.count) of \(wanted.count) lines in \(Date().timeIntervalSince(chunkStarted), format: .fixed(precision: 1)) s")
                } catch {
                    failure = error
                    before = []
                    log.error("intelligence: lines \(first + 1)-\(first + indices.count) of \(wanted.count) failed: \(String(describing: error), privacy: .public)")
                }
                if first + chunkLines < wanted.count { let soFar = out; DispatchQueue.main.async { progress(soFar) } }
            }
            log.notice("intelligence: \(translated) of \(wanted.count) lines into \(languageTag, privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
            if translated == 0, let failure { return finish(done, nil, problem(failure)) }
            let left = wanted.count - translated
            finish(done, out, left == 0 ? nil
                : "Apple Intelligence left \(left) of the song's \(wanted.count) lines untranslated. Ask again to try those lines once more.")
        }
    }

    // A batch, or nil for each line the model refused even alone: a refused batch is asked again in halves, down
    // to single lines. Any other error ends the batch.
    @available(iOS 26.0, *)
    private static func translateSplitting(_ lines: [String], into language: String, song: String?, before: [(String, String)],
                                           failure: inout Error?) async throws -> [String?] {
        do {
            return try await translateChunk(lines, into: language, song: song, before: before)
        } catch where refused(error) {
            failure = error
            if lines.count == 1 { return [nil] }
            let half = lines.count / 2
            let head = try await translateSplitting(Array(lines[..<half]), into: language, song: song, before: before, failure: &failure)
            let tail = try await translateSplitting(Array(lines[half...]), into: language, song: song, before: before, failure: &failure)
            return head + tail
        }
    }

    @available(iOS 26.0, *)
    private static func refused(_ error: Error) -> Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: break
            }
        }
        #endif
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: break
            }
        }
        return false
    }

    // iOS 27 throws LanguageModelError, iOS 26 the session's GenerationError. The first is only in the iOS 27 SDK
    // (Swift 6.4), and the release build has the iOS 26 one; GenerationOptions' sampling: label is in both.
    @available(iOS 26.0, *)
    private static func problem(_ error: Error) -> String {
        let declined = "Apple Intelligence declined to translate this song's lyrics."
        let tooLong = "The song is too long for Apple Intelligence."
        let language = "Apple Intelligence does not work in this language."
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return declined
            case .contextSizeExceeded: return tooLong
            case .unsupportedLanguageOrLocale: return language
            default: break
            }
        }
        #endif
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return declined
            case .exceededContextWindowSize: return tooLong
            case .unsupportedLanguageOrLocale: return language
            default: break
            }
        }
        return "Apple Intelligence could not translate the song (\(error.localizedDescription))."
    }

    // Exactly one string per line, held to the count by the schema rather than read out of free text. The batch
    // before it comes along, already translated, so a sentence across the two reads as one and names, pronouns
    // and tone stay as they were; it is context only and gets no answer.
    @available(iOS 26.0, *)
    private static func translateChunk(_ lines: [String], into language: String, song: String?, before: [(String, String)]) async throws -> [String] {
        let json = { (value: Any) in
            String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)) ?? Data(), as: UTF8.self)
        }
        let context = before.isEmpty ? "" : "Just before, already translated: \(json(before.map { [$0.0, $0.1] }))\n\n"
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: tokensPerLine * lines.count + 32)
        let follow = """
            Lines from just before may be given with their translations: they are not to be translated again, only \
            followed, so names, pronouns and tone carry on and a sentence that runs on reads as one.
            """
        // Each line under its own number, in the question and the answer, so a sentence the model joins or splits
        // across lines cannot move the translations after it onto the wrong lines (K-pop's mixed lines did).
        if #available(iOS 26.4, *) {
            let keys = lines.indices.map { String(format: "%02d", $0 + 1) }
            let session = LanguageModelSession(model: model, instructions: """
                You translate the lyrics of \(song ?? "a song") into \(language). You get a JSON object of numbered \
                lines and answer with the same numbers, each holding the translation of that line alone, natural as \
                sung, keeping the meaning of slang and idioms. A line that is empty, a sound or already in \(language) \
                is given back as it is. \(follow)
                """)
            let root = DynamicGenerationSchema(name: "Lines", properties: keys.map {
                DynamicGenerationSchema.Property(name: $0, schema: DynamicGenerationSchema(type: String.self))
            })
            let numbered = "{" + zip(keys, lines).map { "\(json($0)): \(json($1))" }.joined(separator: ", ") + "}"
            let content = try await session.respond(to: context + "Translate: " + numbered,
                                                    schema: try GenerationSchema(root: root, dependencies: []), options: options).content
            return try keys.map { try content.value(String.self, forProperty: $0) }
        }
        let session = LanguageModelSession(model: model, instructions: """
            You translate the lyrics of \(song ?? "a song") into \(language). You get a JSON array of lines and answer \
            with an array of the same length: each line's translation at the same place, natural as sung, keeping the \
            meaning of slang and idioms. A line that is empty, a sound or already in \(language) is given back as it is. \
            \(follow)
            """)
        let line = DynamicGenerationSchema(type: String.self)
        let schema = try GenerationSchema(root: DynamicGenerationSchema(arrayOf: line, minimumElements: lines.count, maximumElements: lines.count),
                                          dependencies: [])
        let answer = try await session.respond(to: context + "Translate: " + json(lines), schema: schema, options: options).content.value([String].self)
        return answer.count == lines.count ? answer : lines.indices.map { $0 < answer.count ? answer[$0] : "" }
    }
}
