import Foundation
import Testing
import YascribeNotes
@testable import YascribeApp

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mn-chats-\(UUID().uuidString)")
}

private func sample(id: UUID = UUID(), scope: ArchiveScopeRef? = .all) -> ArchiveConversation {
    let chunk = ArchiveIndex.Chunk(sessionID: "m1", start: 5, text: "Budget is 10", vector: Data([1, 2, 3, 4]))
    let answered = ArchiveConversation.Turn(id: UUID(), question: "What is the budget?", scopeLabel: "All meetings", scopeIDs: ["m1"],
                                            kind: .answered, text: "Budget is 10 [1].", sources: [chunk], opensSettings: nil,
                                            fingerprints: ["m1": "abc"])
    return ArchiveConversation(version: 1, id: id, title: "What is the budget?", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                               updatedAt: Date(timeIntervalSince1970: 1_700_000_100), scope: scope, turns: [answered])
}

@Test func storeRoundTripsAndNeverWritesVectorsOrKeys() throws {
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let chat = sample()
    try store.save(chat)
    let raw = try String(contentsOf: store.url(for: chat.id), encoding: .utf8)
    #expect(!raw.contains(Data([1, 2, 3, 4]).base64EncodedString()) && !raw.contains("test-fake") && !raw.contains("apiKey"))
    let loaded = try store.load(chat.id)
    #expect(loaded.turns[0].sources?.first?.vector.isEmpty == true && loaded.turns[0].sources?.first?.text == "Budget is 10")
    #expect(loaded.turns[0].fingerprints == ["m1": "abc"] && loaded.scope == .all && loaded.title == chat.title)
    #expect(store.url(for: chat.id).lastPathComponent == "\(chat.id.uuidString).json")
}

@Test func storeRejectsMismatchedIDBadNamesUnsafeContentAndSymlinks() throws {
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let fm = FileManager.default
    let chat = sample()
    try store.save(chat)

    let other = UUID()
    try fm.copyItem(at: store.url(for: chat.id), to: store.url(for: other))
    #expect(throws: (any Error).self) { try store.load(other) } // id w pliku ≠ nazwa pliku

    let named = store.directory.appendingPathComponent("not-a-uuid.json")
    try fm.copyItem(at: store.url(for: chat.id), to: named)
    #expect(throws: (any Error).self) { try store.load(fileURL: named) }

    var unsafe = sample(scope: ArchiveScopeRef(kind: .folder, id: nil)) // folder bez identyfikatora
    #expect(!unsafe.isValid)
    unsafe = sample()
    unsafe.version = 99
    #expect(!unsafe.isValid)
    unsafe = sample()
    unsafe.turns.append(unsafe.turns[0]) // powtórzone id tury
    #expect(!unsafe.isValid)
    unsafe = sample()
    unsafe.turns[0].question = String(repeating: "q", count: ArchiveAsk.maxQuestionChars + 1)
    #expect(!unsafe.isValid)

    let target = store.directory.appendingPathComponent("outside.json")
    try fm.copyItem(at: store.url(for: chat.id), to: target)
    let linkID = UUID()
    try fm.createSymbolicLink(at: store.url(for: linkID), withDestinationURL: target)
    #expect(throws: (any Error).self) { try store.load(linkID) }
    #expect(throws: (any Error).self) { try store.save(sample(id: linkID)) } // nie zapisujemy przez dowiązanie

    let listed = store.list()
    #expect(listed.chats.map(\.id) == [chat.id] && listed.problems == 4) // other, not-a-uuid, outside (zła nazwa), link
}

@Test func storeRejectsOversizedOrInvalidUpdateBeforeReplacingAReadableChat() throws {
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let chat = sample()
    try store.save(chat)
    let saved = try Data(contentsOf: store.url(for: chat.id))
    var invalid = chat
    invalid.turns[0].question = String(repeating: "q", count: ArchiveAsk.maxQuestionChars + 1)
    #expect(throws: (any Error).self) { try store.save(invalid) }
    var oversized = chat
    let text = String(repeating: "a", count: 190_000)
    oversized.turns = (0..<43).map { _ in
        var turn = chat.turns[0]
        turn.id = UUID()
        turn.text = text
        return turn
    }
    #expect(oversized.isValid)
    #expect(throws: (any Error).self) { try store.save(oversized) }
    #expect(try Data(contentsOf: store.url(for: chat.id)) == saved)
}

@Test func symlinkedChatsDirectoryIsRefused() throws {
    let real = tempDir()
    let link = tempDir()
    defer { try? FileManager.default.removeItem(at: real); try? FileManager.default.removeItem(at: link) }
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let store = ArchiveConversationStore(directory: link)
    #expect(throws: (any Error).self) { try store.save(sample()) }
    #expect(store.list().chats.isEmpty)
    #expect((try? FileManager.default.contentsOfDirectory(atPath: real.path))?.isEmpty == true)
}

@Test func titleComesFromTheFirstLineAndIsBounded() {
    #expect(ArchiveConversation.title(from: "  What is the budget?\nsecond line") == "What is the budget?")
    let long = ArchiveConversation.title(from: String(repeating: "a", count: 200))
    #expect(long.count == ArchiveConversation.maxTitleChars && long.hasSuffix("…"))
}

@Test func scopeRefsResolveAgainstCurrentMembershipAndNeverFallBackToAll() {
    func item(_ id: String, title: String) -> SessionItem {
        var item = SessionItem(url: URL(fileURLWithPath: "/tmp/\(id)"), startedAt: Date(timeIntervalSince1970: 1_700_000_000), transcript: nil, runID: nil)
        item.notes = SessionNotes(myNotes: "", meta: NoteMeta(manualTitle: title))
        return item
    }
    let sessions = [item("a", title: "Alpha"), item("b", title: "Beta"), item("c", title: "Gamma")]
    var folderOf = ["a": "X", "b": "Y"]
    let existing: Set<String> = ["X", "Y"]
    func resolve(_ ref: ArchiveScopeRef) -> (ids: Set<String>, label: String)? {
        ref.resolve(sessions: sessions, folderID: { folderOf[$0.id] }, folderName: { id in id.flatMap { existing.contains($0) ? "Folder \($0)" : nil } })
    }
    #expect(resolve(.all)?.ids == ["a", "b", "c"] && resolve(.all)?.label == "All meetings")
    #expect(resolve(.unfiled)?.ids == ["c"] && resolve(.unfiled)?.label == "No folder")
    #expect(resolve(.folder("X"))?.ids == ["a"] && resolve(.folder("X"))?.label == "Folder X")
    folderOf["c"] = "X" // członkostwo się zmieniło
    #expect(resolve(.folder("X"))?.ids == ["a", "c"] && resolve(.unfiled)?.ids == [])
    #expect(resolve(.folder("GONE")) == nil) // usunięty folder: brak zakresu, nie „All meetings"
    #expect(resolve(.meeting("b"))?.ids == ["b"] && resolve(.meeting("b"))?.label == "This meeting: Beta")
    #expect(resolve(.meeting("gone")) == nil)
}

@Test func savedChatWithUnsafeCitationTimeIsRejected() throws {
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let chat = sample()
    try store.save(chat)
    let url = store.url(for: chat.id)
    var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var turns = try #require(payload["turns"] as? [[String: Any]])
    var sources = try #require(turns[0]["sources"] as? [[String: Any]])
    sources[0]["start"] = 1e100
    turns[0]["sources"] = sources
    payload["turns"] = turns
    try JSONSerialization.data(withJSONObject: payload).write(to: url)
    #expect(throws: (any Error).self) { try store.load(chat.id) }
    #expect(store.list().problems == 1)
}

@Test func archivePresentationKeepsStoredContentCanonical() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let pl = try #require(Bundle(path: root.appendingPathComponent("Resources/pl.lproj").path))
    let en = try #require(Bundle(path: root.appendingPathComponent("Resources/en.lproj").path))
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    var chat = sample()
    chat.turns[0].kind = .noAnswer
    chat.turns[0].text = "No meetings with transcripts or notes in All meetings."
    try store.save(chat)
    let before = try Data(contentsOf: store.url(for: chat.id))
    for bundle in [en, pl] {
        let loaded = try store.load(chat.id)
        let turn = loaded.turns[0]
        let shown = ArchivePresentation.message(try #require(turn.text), scopeLabel: turn.scopeLabel, scope: loaded.scope, bundle: bundle)
        #expect(shown == (bundle == pl ? "Brak spotkań z transkryptami lub notatkami w zakresie: wszystkie spotkania." : turn.text))
        try store.save(loaded)
        #expect(try Data(contentsOf: store.url(for: chat.id)) == before)
    }
    #expect(ArchivePresentation.scope("All meetings", ref: .folder("x"), bundle: pl) == "All meetings")
    let meetingScope = ArchivePresentation.scope("This meeting: Settings", ref: .meeting("m"), bundle: pl)
    #expect(ArchivePresentation.format("Ask about %@", meetingScope, bundle: pl) == "Zapytaj: to spotkanie – Settings")
    #expect(ArchivePresentation.scope("No folder", ref: .unfiled, bundle: pl) == "bez folderu")
    #expect(ArchivePresentation.scope("No folder", ref: .unfiled, bundle: en) == "No folder")
    #expect(ArchivePresentation.message(try #require(chat.turns[0].text), scopeLabel: "All meetings", scope: nil, bundle: pl) == chat.turns[0].text)
    #expect(ArchivePresentation.message("Unknown failure", bundle: pl) == "Unknown failure")
    #expect(ArchivePresentation.message("This answer was interrupted when Yascribe closed. Ask again.", bundle: pl) == "Odpowiedź przerwano po zamknięciu Yascribe. Zadaj pytanie ponownie.")
}

@Test @MainActor func savedKeychainFailureWithSeparatorInProviderNameCanBeDisplayed() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let pl = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    let store = ArchiveConversationStore(directory: tempDir())
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let provider = "from Keychain: Demo"
    let message = "Couldn't read the API key for \(provider) from Keychain: Access denied"
    let expected = "Nie udało się odczytać klucza API dostawcy \(provider) z pęku kluczy: Access denied"
    #expect(ArchivePresentation.message(message, bundle: pl) == expected)

    var chat = sample()
    chat.turns[0].kind = .failed
    chat.turns[0].text = message
    chat.turns[0].sources = nil
    try store.save(chat)
    let archive = ArchiveModel(presentationBundle: pl)
    archive.chatsURL = store.directory
    archive.openChat(chat.id)
    let turn = try #require(archive.turns.first)
    #expect(turn.state == .failed(message, opensSettings: false))
    guard case .failed(let stored, _) = turn.state else { return }
    #expect(archive.displayedMessage(stored, for: turn) == expected)
}
