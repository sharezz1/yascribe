import Foundation
import Testing
import YascribeNotes
import YascribeUpdates
@testable import YascribeApp

@Test func languagePreferencesUseApplicationDomain() throws {
    let name = "UILanguageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(UILanguage.current(in: defaults) == .auto)
    #expect(!UILanguage.auto.select(in: defaults, domain: name))
    defaults.set(["pl"], forKey: "AppleLanguages")
    #expect(UILanguage.current(in: defaults) == .auto)
    #expect(UILanguage.auto.select(in: defaults, domain: name))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    #expect(UILanguage.pl.select(in: defaults, domain: name))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["pl"])
    #expect(!UILanguage.pl.select(in: defaults, domain: name))
    defaults.set(["en", "pl"], forKey: "AppleLanguages")
    #expect(UILanguage.pl.select(in: defaults, domain: name))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["pl"])
    #expect(UILanguage.en.select(in: defaults, domain: name))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["en"])
    #expect(UILanguage.auto.select(in: defaults, domain: name))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    #expect(!UILanguage.auto.select(in: defaults, domain: name))
}

@MainActor private final class RestartActivity: RecordingActivity {
    var recording = false
    var moving = false
    var isBusy: Bool { recording || moving }
}

@Test @MainActor func languageRestartChecksAgainAndConsumesIntent() {
    let restart = LanguageRestart()
    let activity = RestartActivity()
    let gate = RestartGate(activity: activity)
    let directory = URL(fileURLWithPath: "/tmp/finalizing")
    func canRestart(directory: URL? = nil, dictating: Bool = false, retryAudio: Bool = false, background: Bool = false) -> Bool {
        AppModel.canRestartForLanguage(updateGate: gate, recordingDirectory: directory,
                                      dictationBusy: dictating, dictationHasRetryAudio: retryAudio, backgroundWork: background)
    }
    var terminations = 0
    var launches = 0
    func terminate() { terminations += 1 }
    func launch() { launches += 1 }

    #expect(!restart.consume(ifIdle: canRestart(), launch: launch))
    activity.recording = true
    restart.request(ifIdle: canRestart(), terminate: terminate)
    activity.recording = false
    activity.moving = true
    restart.request(ifIdle: canRestart(), terminate: terminate)
    activity.moving = false
    restart.request(ifIdle: canRestart(directory: directory), terminate: terminate)
    restart.request(ifIdle: canRestart(dictating: true), terminate: terminate)
    restart.request(ifIdle: canRestart(retryAudio: true), terminate: terminate)
    restart.request(ifIdle: canRestart(background: true), terminate: terminate)
    gate.installationStarted()
    restart.request(ifIdle: canRestart(), terminate: terminate)
    gate.installationEnded()
    activity.recording = true
    #expect(gate.shouldPostpone { })
    activity.recording = false
    restart.request(ifIdle: canRestart(), terminate: terminate)
    gate.installationEnded()
    #expect(terminations == 0)

    restart.request(ifIdle: canRestart(), terminate: terminate)
    #expect(!restart.consume(ifIdle: canRestart(retryAudio: true), launch: launch))
    #expect(!restart.consume(ifIdle: canRestart(), launch: launch))
    restart.request(ifIdle: canRestart(), terminate: terminate)
    #expect(restart.consume(ifIdle: canRestart(), launch: launch))
    #expect(terminations == 2 && launches == 1)
}

@Test @MainActor func failedLanguageRestartDoesNotAffectLaterQuit() {
    let restart = LanguageRestart()
    restart.request(ifIdle: true) { }
    #expect(!restart.consume(ifIdle: true) { throw CocoaError(.fileWriteUnknown) })
    #expect(!restart.requested)
    #expect(!restart.consume(ifIdle: true) { Issue.record("Ordinary quit launched a restart helper") })
}

@Test @MainActor func flushingNotesSavesEveryDraftAndKeepsFailedEditsForRetry() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-session-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let good = SessionItem(url: root.appendingPathComponent("good"), startedAt: Date(), transcript: nil, runID: nil)
    let missing = SessionItem(url: root.appendingPathComponent("missing"), startedAt: Date(), transcript: nil, runID: nil)
    try FileManager.default.createDirectory(at: good.url, withIntermediateDirectories: true)
    let notes = NotesModel()
    var errors: [String] = []
    notes.report = { errors.append($0) }
    notes.saveMyNotes("Ready", for: good)
    notes.saveMyNotes("Keep this draft", for: missing)

    #expect(!notes.flushPendingSaves())
    #expect(errors.count == 1)
    #expect(NotesStore(session: good.url).readMyNotes() == "Ready")
    #expect(notes.pendingMyNotes(missing.id) == "Keep this draft")

    try FileManager.default.createDirectory(at: missing.url, withIntermediateDirectories: true)
    #expect(notes.flushPendingSaves())
    #expect(NotesStore(session: missing.url).readMyNotes() == "Keep this draft")
    #expect(!notes.hasPendingNotes(missing.id))
}
