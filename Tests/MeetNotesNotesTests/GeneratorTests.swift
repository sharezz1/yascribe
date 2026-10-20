import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

private func generator(_ stub: ChatStub) -> NoteGenerator { NoteGenerator(client: chatClient(stub), model: "notes-model") }
private let now = Date(timeIntervalSince1970: 5_000)

@Test func generatorStoresTheNoteWithItsTitleAndTemplate() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# Forecast review\n\n## Topic\n- Saturday: 9 000 contacts" }
    let s = try await generator(stub).generate(session: session, template: .standard,
                                               transcript: transcript([utt("Prognoza na sobotę.")]),
                                               context: "Piotr, Adrian", notesLanguage: .polish, now: now)
    #expect(s.title == "Forecast review")
    #expect(s.markdown.hasPrefix("## Topic"))
    #expect(s.templateID == "standard" && s.model == "notes-model" && s.context == "Piotr, Adrian")
    #expect(try NotesStore(session: session).readSummary() == s)
}

@Test func generatorWithNothingToSummarizeSkipsTheModel() async throws {
    // Review Focus #1.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# T\nx" }
    await #expect(throws: NoteGenerationError.nothingToSummarize) {
        _ = try await generator(stub).generate(session: session, template: .standard,
                                               transcript: transcript([utt("zaflagowane", flagged: true)]),
                                               context: "", notesLanguage: .polish, now: now)
    }
    #expect(stub.calls.isEmpty)
    #expect(try NotesStore(session: session).readSummary() == nil)
}

@Test func generatorFailureWritesNothingAndNamesTheModel() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let old = NoteSummary(title: "Old", markdown: "old", templateID: "standard", model: "m", context: "", generatedAt: now)
    try store.writeSummary(old, now: now)
    let stub = ChatStub { _ in throw StubHTTPError(status: 400, body: "{\"error\":\"maximum context length is 8000 tokens\"}") }
    do {
        _ = try await generator(stub).generate(session: session, template: .standard,
                                               transcript: transcript([utt("Prognoza na sobotę.")]),
                                               context: "", notesLanguage: .polish, now: now)
        Issue.record("oczekiwano błędu")
    } catch NoteGenerationError.failed(let message) {
        #expect(message.contains("notes-model") && message.contains("longer context"))
    }
    #expect(try store.readSummary() == old) // poprzednia notatka nietknięta
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).filter { $0.hasPrefix("summary-") }.isEmpty)
}

@Test func generatorGivesUpOnASlowModelAndWritesNothing() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub(delay: .seconds(5)) { _ in "# T\nbody" }
    let slow = NoteGenerator(client: chatClient(stub), model: "notes-model", timeout: 0.2)
    do {
        _ = try await slow.generate(session: session, template: .standard, transcript: transcript([utt("Prognoza na sobotę.")]),
                                    context: "", notesLanguage: .polish, now: now)
        Issue.record("oczekiwano błędu")
    } catch NoteGenerationError.failed(let message) {
        #expect(message.contains("notes-model") && message.contains("didn't answer"))
    }
    #expect(try NotesStore(session: session).readSummary() == nil)
}

@Test func cutOffNoteFailsClearlyAndWritesNothing() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub(finishReason: "length") { _ in "# T\nbody urwane" }
    do {
        _ = try await generator(stub).generate(session: session, template: .standard,
                                               transcript: transcript([utt("Prognoza na sobotę.")]), context: "", notesLanguage: .polish, now: now)
        Issue.record("oczekiwano błędu")
    } catch NoteGenerationError.failed(let message) {
        #expect(message.contains("notes-model") && message.contains("cut off"))
    }
    #expect(try NotesStore(session: session).readSummary() == nil)
}

@Test func generatorPassesItsLimitsToTheChatCall() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# T\nbody" }
    let g = NoteGenerator(client: chatClient(stub), model: "notes-model", timeout: 600, chatTimeout: 660, maxTokens: 2048)
    _ = try await g.generate(session: session, template: .standard, transcript: transcript([utt("Prognoza na sobotę.")]),
                             context: "", notesLanguage: .polish, now: now)
    #expect(stub.calls[0].timeout == 660 && stub.calls[0].maxTokens == 2048 && stub.calls[0].temperature == nil)
}

@Test func generatorThinkingFollowsTheSetting() async throws {
    // F20 P1: domyślnie jak dotąd (nic nie wysyłamy); wyłączone w Settings = `reasoning.enabled: false`.
    var results: [Bool?] = []
    for thinking in [true, false] {
        let session = tempDir()
        defer { try? FileManager.default.removeItem(at: session) }
        let stub = ChatStub { _ in "# T\nbody" }
        var g = NoteGenerator(client: chatClient(stub), model: "notes-model")
        g.thinking = thinking
        _ = try await g.generate(session: session, template: .standard, transcript: transcript([utt("Prognoza na sobotę.")]),
                                 context: "", notesLanguage: .polish, now: now)
        results.append(stub.calls[0].reasoningEnabled)
    }
    #expect(results == [nil, false])
}

@Test func globalSettingsThinkingIsOptionalAndDefaultsToOn() throws {
    // E6: stary settings.json bez pola nadal się czyta; brak = myślenie dozwolone (zachowanie sprzed poprawki).
    let old = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    #expect(old.summaryThinking == nil && old.summaryThinkingEnabled)
    var s = GlobalSettings()
    s.summaryThinking = false
    #expect(!s.summaryThinkingEnabled)
    #expect(try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(s)).summaryThinkingEnabled == false)
}

@Test func truncatedInputNoteFailsClearlyAndWritesNothing() async throws {
    // Odbiór 2.0b, pkt 2c: lokalny serwer obciął prompt (HTTP 200, "stop") — wcześniej zapisywała się "udana" notatka bez tytułu.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub(finishReason: "stop", promptTokens: { _ in 40 }) { _ in "Tylko ogon notatki." }
    let long = transcript([utt(String(repeating: "Prognoza na sobotę jest wyższa. ", count: 150))])
    let gen = NoteGenerator(client: localChatClient(stub), model: "notes-model")
    do {
        _ = try await gen.generate(session: session, template: .standard, transcript: long, context: "", notesLanguage: .polish, now: now)
        Issue.record("oczekiwano błędu")
    } catch NoteGenerationError.failed(let message) {
        #expect(message.contains("notes-model's server cut off the start of the input"))
        #expect(message.contains("Context window") && message.contains("OLLAMA_CONTEXT_LENGTH=16384"))
    }
    #expect(try NotesStore(session: session).readSummary() == nil)
}
