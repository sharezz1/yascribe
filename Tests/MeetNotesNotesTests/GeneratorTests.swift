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
