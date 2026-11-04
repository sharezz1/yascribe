import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

// MARK: syntetyczny serwer i stanowisko (żadnej sieci, żadnego prawdziwego archiwum, klucze `test-fake-…`)

private struct WireError: Error {
    let status: Int
    let body: String
}

private func concept(_ text: String) -> [Double] {
    let t = text.lowercased()
    var v = [0.0, 0.0, 0.0, 0.01]
    if t.contains("budget") || t.contains("costs") || t.contains("money") { v[0] = 1 }
    if t.contains("owner") || t.contains("who") { v[1] = 1 }
    if t.contains("release") || t.contains("ship") { v[2] = 1 }
    return v
}

private final class Wire: HTTPClient, @unchecked Sendable {
    struct Call: Sendable {
        let host: String
        let kind: String
        let model: String
        let input: String
        let user: String
    }
    private let lock = NSLock()
    private var log: [Call] = []
    let embed: @Sendable (Call) throws -> [Double]
    let chat: @Sendable (Call) throws -> String
    let delay: @Sendable (Call) -> Duration?
    var calls: [Call] { lock.withLock { log } }
    var embeds: [Call] { calls.filter { $0.kind == "embeddings" } }
    var chats: [Call] { calls.filter { $0.kind == "chat" } }

    init(embed: @escaping @Sendable (Call) throws -> [Double] = { concept($0.input) },
         chat: @escaping @Sendable (Call) throws -> String = { $0.user.contains("[1] ") ? "Found [1]." : "NO_ANSWER" },
         delay: @escaping @Sendable (Call) -> Duration? = { _ in nil }) {
        self.embed = embed
        self.chat = chat
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        let isEmbedding = request.url!.path.hasSuffix("/embeddings")
        let messages = body["messages"] as? [[String: Any]] ?? []
        let call = Call(host: request.url!.host() ?? "", kind: isEmbedding ? "embeddings" : "chat", model: body["model"] as? String ?? "",
                        input: body["input"] as? String ?? "", user: messages.last?["content"] as? String ?? "")
        lock.withLock { log.append(call) }
        if let pause = delay(call) { try await Task.sleep(for: pause) }
        let reply: [String: Any]
        do {
            reply = isEmbedding ? ["data": [["embedding": try embed(call)]]] : ["choices": [["message": ["content": try chat(call)]]]]
        } catch let e as WireError {
            return (Data(e.body.utf8), HTTPURLResponse(url: request.url!, statusCode: e.status, httpVersion: nil, headerFields: nil)!)
        }
        return (try JSONSerialization.data(withJSONObject: reply),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private let askedChanged = "A meeting or the Ask model changed while answering. Ask again."

private extension ArchiveModel.TurnState {
    var answer: ArchiveAsk.Answer? { if case .answered(let a) = self { a } else { nil } }
    var failure: String? { if case .failed(let m, _) = self { m } else { nil } }
    var opensSettings: Bool { if case .failed(_, let s) = self { s } else { false } }
    var neutral: String? { if case .noAnswer(let m) = self { m } else { nil } }
    var isCancelled: Bool { self == .cancelled }
}

@MainActor private final class Harness {
    let dir: URL
    let wire: Wire
    let model = ArchiveModel()
    let notes = NotesModel()
    var items: [SessionItem] = []
    var folders: [String: String] = [:]
    var currentFolder: String?
    var selected: String?
    var fixedScope: Set<String>?
    var providers: [UUID: Provider]
    var settings: GlobalSettings
    var moving = false
    var reports: [String] = []
    let embedProvider: Provider
    let chatProvider: Provider
    let askA: RoleAssignment
    let askB: RoleAssignment

    var indexURL: URL { dir.appendingPathComponent("archive-index.json") }
    var chatsURL: URL { dir.appendingPathComponent("chats") }
    var existingFolders: Set<String> = ["X", "Y"]
    var store: ArchiveConversationStore { ArchiveConversationStore(directory: chatsURL) }

    /// Jak `AppModel.wireArchive`: zakres rozmowy z miejsca użytkownika (spotkanie > folder > całość), zapisany jako identyfikator.
    func useAutomaticScope() {
        model.captureScope = { [unowned self] in
            if let selected { return .meeting(selected) }
            if let currentFolder { return .folder(currentFolder) }
            return .all
        }
        model.resolveSavedScope = { [unowned self] ref in
            ref.resolve(sessions: items, folderID: { self.folders[$0.id] },
                        folderName: { id in id.flatMap { self.existingFolders.contains($0) ? $0 : nil } })
        }
    }
    var space: String { space(of: settings.embedding) }
    var last: ArchiveModel.TurnState? { model.turns.last?.state }

    func space(of assignment: RoleAssignment?) -> String {
        guard let assignment, let provider = providers[assignment.providerID] else { return "" }
        return ArchiveIndex.space(provider: provider, model: assignment.model)
    }

    /// `like`: ten sam katalog danych, serwer, dostawcy i spotkania, ale nowy `ArchiveModel` („restart").
    init(wire: Wire = Wire(), embedLocal: Bool = false, like other: Harness? = nil) {
        dir = other?.dir ?? FileManager.default.temporaryDirectory.appendingPathComponent("mn-archive-\(UUID().uuidString)")
        self.wire = other?.wire ?? wire
        embedProvider = other?.embedProvider ?? Provider(name: "Embed Cloud", baseURL: URL(string: embedLocal ? "http://localhost:11434/v1" : "https://embed.example.test/v1")!)
        chatProvider = other?.chatProvider ?? Provider(name: "Chat Cloud", baseURL: URL(string: "https://chat.example.test/v1")!)
        providers = other?.providers ?? [:]
        providers[embedProvider.id] = embedProvider
        providers[chatProvider.id] = chatProvider
        askA = RoleAssignment(providerID: chatProvider.id, model: "ask-A")
        askB = RoleAssignment(providerID: chatProvider.id, model: "ask-B")
        settings = other?.settings ?? GlobalSettings(embedding: RoleAssignment(providerID: embedProvider.id, model: "embed-1"))
        if other == nil { settings.askModel = askA }
        items = other?.items ?? []
        folders = other?.folders ?? [:]
        model.indexURL = indexURL
        model.chatsURL = chatsURL
        model.sources = { [unowned self] in items.map { ArchiveModel.source(for: $0, notes: notes, transcript: $0.transcript(corrected: true)) } }
        model.sourceFor = { [unowned self] id in
            items.first { $0.id == id }.map { ArchiveModel.source(for: $0, notes: notes, transcript: $0.transcript(corrected: true)) }
        }
        model.labels = { [unowned self] in Dictionary(items.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }) }
        model.embedding = { [unowned self] in settings.embedding }
        model.askModel = { [unowned self] in settings.askModel }
        model.makeClient = { [unowned self] id in
            guard let provider = providers[id] else { return .failure(AppModel.ClientProblem(message: "This provider no longer exists.")) }
            return .success(OpenAICompatibleClient(provider: provider, key: provider.isLocal ? nil : "test-fake-key", http: self.wire))
        }
        model.providerFor = { [unowned self] id in providers[id] }
        model.isMoving = { [unowned self] in moving }
        model.report = { [unowned self] in reports.append($0) }
        model.resolveScope = { [unowned self] scope in
            if let fixedScope, scope == .list { return (fixedScope, "Fixed scope") }
            return ArchiveModel.resolve(scope, sessions: items, matches: { [unowned self] in currentFolder == nil || folders[$0.id] == currentFolder },
                                        listLabel: currentFolder ?? "All meetings", selectedID: selected)
        }
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    func addMeeting(_ id: String, title: String = "Standup", notes text: String = "", lines: [String] = [], folder: String? = nil) -> SessionItem {
        let url = dir.appendingPathComponent("sessions").appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if !text.isEmpty { _ = try? NotesStore(session: url).writeMyNotes(text) }
        let spoken = lines.isEmpty ? nil : Transcript(utterances: lines.enumerated().map {
            Utterance(speaker: .them, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 5, text: $0.element, words: [], approximateTiming: false)
        }, failedChunks: [])
        var item = SessionItem(url: url, startedAt: Date(timeIntervalSince1970: 1_700_000_000), transcript: spoken, runID: spoken == nil ? nil : "run")
        item.notes = SessionNotes(myNotes: text, meta: NoteMeta(manualTitle: title))
        items.append(item)
        folders[id] = folder
        return item
    }

    /// Edycja na dysku i w liście (jak `reloadSessions` po zapisie).
    func edit(_ id: String, notes text: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        _ = try? NotesStore(session: items[i].url).writeMyNotes(text)
        items[i].notes.myNotes = text
    }

    func delete(_ id: String) {
        if let item = items.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll { $0.id == id }
        model.forget(id)
    }

    /// Zmiana ustawień; `hook: true` = jak `AppModel.settings` `didSet`.
    func change(hook: Bool = true, _ change: (inout GlobalSettings) -> Void) {
        let old = settings
        change(&settings)
        if hook { model.settingsDidChange(old: old, new: settings) }
    }

    func settle() async {
        for _ in 0..<3_000 where model.isBusy { try? await Task.sleep(for: .milliseconds(5)) }
        await model.flushWrites()
    }

    func until(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// Pytanie; pierwsze budowanie indeksu u zdalnego dostawcy zatwierdza (chyba że `confirm: false`).
    func ask(_ question: String, confirm: Bool = true) async {
        model.ask(question)
        await settle()
        if confirm, model.consent != nil {
            model.confirmIndexing()
            await settle()
        }
    }

    func storedIndex() -> ArchiveIndex { ArchiveIndex.load(from: indexURL, space: space) }
}

// MARK: 9. brak konfiguracji

@Test @MainActor func missingConfigurationFailsWithSettingsLinkAndSendsNothing() async throws {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10")
    h.settings.embedding = nil
    await h.ask("What is the budget?")
    #expect(h.last?.failure == "Choose an embedding model in Settings → Archive search to ask about your meetings.")
    #expect(h.last?.opensSettings == true)
    h.settings.embedding = RoleAssignment(providerID: h.embedProvider.id, model: "embed-1")
    h.settings.askModel = nil
    await h.ask("What is the budget?")
    #expect(h.last?.failure == "Choose an Ask model in Settings → Archive search to ask about your meetings.")
    #expect(h.last?.opensSettings == true)
    h.settings.askModel = h.askA
    h.providers[h.chatProvider.id] = nil
    await h.ask("What is the budget?")
    #expect(h.last?.failure == "This provider no longer exists." && h.last?.opensSettings == true)
    h.providers[h.chatProvider.id] = h.chatProvider
    h.moving = true
    await h.ask("What is the budget?")
    #expect(h.last?.failure?.hasPrefix("Meetings are being moved") == true)
    h.moving = false
    let chatURL = h.store.url(for: h.model.currentChatID)
    let saved = try Data(contentsOf: chatURL)
    let turns = h.model.turns.count
    await h.ask(String(repeating: "q", count: 1_001))
    #expect(h.reports.last == "Questions can be up to 1 000 characters.")
    let unchanged = try Data(contentsOf: chatURL)
    #expect(h.model.turns.count == turns && unchanged == saved)
    h.model.ask("   \n")
    #expect(h.model.turns.count == turns) // puste pytanie nie tworzy tury
    #expect(h.wire.calls.isEmpty && !h.model.isBusy)
}

// MARK: 10. zgoda na pierwsze budowanie indeksu

@Test @MainActor func firstRemoteBuildNeedsConsentAndSendsNothingBeforeIt() async {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10")
    h.addMeeting("m2", notes: "Owner is Ann")
    await h.ask("What is the budget?", confirm: false)
    #expect(h.model.consent?.meetings == 2 && h.model.consent?.provider == "Embed Cloud" && h.model.consent?.model == "embed-1")
    #expect(h.wire.calls.isEmpty && !h.model.isBusy)
    h.model.confirmIndexing()
    await h.settle()
    #expect(h.model.consent == nil && h.last?.answer != nil)
    #expect(h.wire.embeds.count == 3) // 2 spotkania + zapytanie
    h.addMeeting("m3", notes: "Ship in May")
    await h.ask("When is the release?", confirm: false)
    #expect(h.model.consent == nil && h.last?.answer != nil) // kolejne aktualizacje bez pytania
}

@Test @MainActor func cancellingTheConsentCardSendsNothing() async {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?", confirm: false)
    #expect(h.model.consent != nil)
    h.model.cancel()
    #expect(h.model.consent == nil && h.last?.isCancelled == true)
    h.model.confirmIndexing() // po anulowaniu nic nie wznawia
    await h.settle()
    #expect(h.wire.calls.isEmpty && h.last?.isCancelled == true)
}

@Test @MainActor func localEmbeddingProviderNeedsNoConsent() async {
    let h = Harness(embedLocal: true)
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?", confirm: false)
    #expect(h.model.consent == nil && h.last?.answer != nil)
    #expect(h.wire.embeds.first?.host == "localhost")
}

// MARK: 11. od pytania do odpowiedzi, zakres, restart

@Test @MainActor func answerUsesOnlyScopeEvidenceAndSurvivesRestartWithoutReembedding() async throws {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10", folder: "X")
    h.addMeeting("m2", notes: "Budget is 99", folder: "Y")
    h.currentFolder = "X"
    await h.ask("What is the budget?")
    let answer = try #require(h.last?.answer)
    #expect(answer.sources.map(\.sessionID) == ["m1"] && answer.sources[0].vector.isEmpty)
    let prompt = try #require(h.wire.chats.last?.user)
    #expect(prompt.contains("Budget is 10") && !prompt.contains("Budget is 99"))
    #expect(h.model.turns.last?.scopeLabel == "X" && h.model.turns.last?.scopeIDs == ["m1"])
    #expect(h.wire.chats.allSatisfy { $0.host == "chat.example.test" } && h.wire.embeds.allSatisfy { $0.host == "embed.example.test" })

    let before = h.wire.embeds.count
    let restarted = Harness(like: h)
    restarted.currentFolder = "X"
    await restarted.ask("What is the budget?", confirm: false)
    #expect(restarted.last?.answer?.sources.map(\.sessionID) == ["m1"])
    #expect(h.wire.embeds.count == before + 1) // tylko zapytanie
}

@Test @MainActor func noEvidenceMeansNoChatCallAndNoAnswerText() async {
    let h = Harness()
    h.addMeeting("m1", title: "Empty") // bez transkryptu i notatek
    await h.ask("What is the budget?")
    #expect(h.last?.neutral == "No meetings with transcripts or notes in All meetings.")
    #expect(h.wire.chats.isEmpty)
    h.addMeeting("m2", notes: "Budget is 10")
    let unsupported = Harness(wire: Wire(chat: { _ in "NO_ANSWER" }))
    unsupported.addMeeting("m1", notes: "Budget is 10")
    await unsupported.ask("What is the weather?")
    #expect(unsupported.last?.neutral == "I couldn't find a supported answer in All meetings.")
    let invented = Harness(wire: Wire(chat: { _ in "The budget is 10 [1] and 20 [7]." }))
    invented.addMeeting("m1", notes: "Budget is 10")
    await invented.ask("What is the budget?")
    #expect(invented.last?.neutral != nil && invented.last?.answer == nil) // nieznany numer: nic nie jest pokazane
}

// MARK: 12. My notes: prawdziwa ścieżka NotesModel.saveMyNotes

@Test @MainActor func unsavedMyNotesAreIndexedAndAnsweredFromNotTheStaleCopy() async throws {
    let h = Harness()
    let item = h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    #expect(h.storedIndex().chunks.contains { $0.text.contains("Budget is 10") })

    h.notes.saveMyNotes("Budget is 20", for: item) // SessionItem nadal trzyma 10
    #expect(h.notes.pendingMyNotes("m1") == "Budget is 20" && h.items[0].notes.myNotes == "Budget is 10")
    // (a) pytanie przed autozapisem
    await h.ask("What is the budget?")
    #expect(h.wire.embeds.contains { $0.input == "Standup\nBudget is 20" })
    let stored = h.storedIndex()
    #expect(!stored.chunks.contains { $0.text.contains("Budget is 10") } && stored.chunks.contains { $0.text.contains("Budget is 20") })
    let prompt = try #require(h.wire.chats.last?.user)
    #expect(prompt.contains("Budget is 20") && !prompt.contains("Budget is 10"))
    #expect(h.last?.answer != nil)

    // (b) po autozapisie: dysk = 20, kopia w SessionItem nadal 10, źródło i odcisk z 20
    try await Task.sleep(for: .milliseconds(1_000))
    #expect(h.notes.pendingMyNotes("m1") == nil)
    #expect(NotesStore(session: item.url).readMyNotes() == "Budget is 20" && h.items[0].notes.myNotes == "Budget is 10")
    let source = ArchiveModel.source(for: h.items[0], notes: h.notes, transcript: nil)
    let expected = ArchiveIndex.Source(sessionID: "m1", title: "Standup", myNotes: "Budget is 20", summary: nil, transcript: nil)
    #expect(source.fingerprint == expected.fingerprint && source.pending.first?.text == "Budget is 20")
}

@Test @MainActor func editingMyNotesDuringASlowAnswerRejectsThePublication() async {
    let h = Harness(wire: Wire(delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(400) : nil }))
    let item = h.addMeeting("m1", notes: "Budget is 20")
    await h.ask("What is the budget?")
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    h.notes.saveMyNotes("Budget is 30", for: item)
    await h.settle()
    #expect(h.last?.failure == askedChanged && h.last?.answer == nil)
}

// MARK: 13. model odpowiedzi zmieniony w trakcie

private func slowModelA() -> Wire {
    Wire(chat: { "\($0.model) says [1]" }, delay: { $0.kind == "chat" && $0.model == "ask-A" ? .milliseconds(400) : nil })
}

@Test @MainActor func lateReplyOfTheOldAskModelNeverBecomesAnAnswer() async throws {
    let h = Harness(wire: slowModelA())
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?") // zbuduj indeks (model A, wolna odpowiedź)
    h.model.ask("budget again?")
    await h.until { h.wire.chats.count == 2 }
    h.change { $0.askModel = h.askB } // jak settings didSet
    #expect(h.last?.failure == "The Ask model changed. Ask again." && !h.model.isBusy)
    try await Task.sleep(for: .milliseconds(600)) // spóźniona odpowiedź A
    #expect(h.last?.failure == "The Ask model changed. Ask again." && h.model.turns.allSatisfy { $0.state.answer?.text != "ask-A says [1]" || $0.question == "What is the budget?" })
    await h.ask("And now?")
    #expect(h.last?.answer?.text == "ask-B says [1]" && h.wire.chats.last?.model == "ask-B")
}

@Test @MainActor func prePublishChecksCatchSwapsThatBypassedTheHook() async {
    func slow(_ swap: (Harness) -> Void) async -> ArchiveModel.TurnState? {
        let h = Harness(wire: slowModelA())
        h.addMeeting("m1", notes: "Budget is 10")
        await h.ask("What is the budget?")
        h.model.ask("budget again?")
        await h.until { h.wire.chats.count == 2 }
        swap(h)
        await h.settle()
        return h.last
    }
    // sam model odpowiedzi, bez haka
    #expect(await slow { $0.change(hook: false) { $0.askModel = $0.askModel.map { RoleAssignment(providerID: $0.providerID, model: "ask-B") } } }?.failure == askedChanged)
    // ten sam model i id dostawcy, inny adres
    #expect(await slow { h in
        h.providers[h.chatProvider.id] = Provider(id: h.chatProvider.id, name: "Chat Cloud", baseURL: URL(string: "https://elsewhere.example.test/v1")!)
    }?.failure == askedChanged)
    // przestrzeń embeddingu
    #expect(await slow { h in h.change(hook: false) { $0.embedding = RoleAssignment(providerID: h.embedProvider.id, model: "embed-2") } }?.failure == askedChanged)
}

// MARK: 14. edycja i usunięcie w trakcie

@Test @MainActor func meetingEditedWhileIndexingIsNotInsertedStale() async {
    let h = Harness(wire: Wire(delay: { $0.kind == "embeddings" && $0.input.contains("slow") ? .milliseconds(250) : nil }))
    h.addMeeting("m1", notes: "slow Budget is 10")
    h.addMeeting("m2", notes: "Owner is Ann")
    h.model.ask("What is the budget?")
    await h.settle()
    h.model.confirmIndexing()
    await h.until { h.wire.embeds.contains { $0.input.contains("slow") } }
    h.edit("m1", notes: "Budget is 11")
    await h.settle()
    let stored = h.storedIndex()
    #expect(!stored.chunks.contains { $0.text.contains("Budget is 10") } && stored.fingerprints["m1"] == nil)
    #expect(stored.fingerprints["m2"] != nil)
    await h.ask("What is the budget?") // następne pytanie dogania zmianę
    #expect(h.storedIndex().chunks.contains { $0.text == "Budget is 11" } && h.last?.answer?.sources.first?.text == "Budget is 11")
}

@Test @MainActor func meetingDeletedDuringAnAnswerIsNeverCitedAndForgetEmptiesTheFile() async {
    let h = Harness(wire: Wire(delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(400) : nil }))
    h.addMeeting("m1", notes: "Budget is 10")
    h.addMeeting("m2", notes: "Owner is Ann")
    await h.ask("What is the budget?")
    #expect(h.storedIndex().fingerprints["m1"] != nil)
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    h.delete("m1")
    await h.settle()
    #expect(h.last?.failure == askedChanged && h.last?.answer == nil)
    #expect(h.storedIndex().fingerprints["m1"] == nil && !h.storedIndex().chunks.contains { $0.sessionID == "m1" })

    let restarted = Harness(like: h) // indeks jeszcze niewczytany w tym modelu
    restarted.model.forget("m2")
    await restarted.model.flushWrites()
    #expect(restarted.storedIndex().fingerprints.isEmpty && restarted.storedIndex().chunks.isEmpty)
}

// MARK: 15. kolejne pytanie i anulowanie

@Test @MainActor func newQuestionCancelsThePreviousAndItsLateReplyNeverOverwritesIt() async throws {
    let h = Harness(wire: Wire(chat: { $0.user.contains("slow") ? "slow reply [1]" : "fresh reply [1]" },
                               delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(400) : nil }))
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("warm up the index")
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    h.model.ask("What is the budget?")
    await h.settle()
    #expect(h.model.turns[1].state.isCancelled && h.model.turns[2].state.answer?.text == "fresh reply [1]")
    try await Task.sleep(for: .milliseconds(600))
    #expect(h.model.turns[1].state.isCancelled && h.model.turns[2].state.answer?.text == "fresh reply [1]")
}

@Test @MainActor func cancelStopsTheQuestionAndLateReplyIsIgnored() async throws {
    let h = Harness(wire: Wire(delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(300) : nil }))
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("warm up the index")
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    #expect(h.model.isBusy)
    h.model.cancel()
    #expect(h.last?.isCancelled == true && !h.model.isBusy)
    try await Task.sleep(for: .milliseconds(500))
    #expect(h.last?.isCancelled == true)
    h.model.clear()
    #expect(h.model.turns.isEmpty)
}

// MARK: 16. zmiana embeddingu w trakcie indeksowania

@MainActor private func fiveMeetings(_ h: Harness) { for i in 1...5 { h.addMeeting("m\(i)", notes: "Budget is \(i)0") } }

@Test @MainActor func embeddingChangeDuringIndexingAbortsAndWipesTheFile() async throws {
    let h = Harness(wire: Wire(delay: { $0.kind == "embeddings" ? .milliseconds(150) : nil }))
    fiveMeetings(h)
    let oldSpace = h.space
    h.model.ask("What is the budget?")
    await h.settle()
    h.model.confirmIndexing()
    await h.until { !h.wire.embeds.isEmpty }
    h.change { $0.embedding = RoleAssignment(providerID: h.embedProvider.id, model: "embed-2") }
    #expect(h.last?.failure == "The embedding model changed. Ask again.")
    await h.settle()
    try await Task.sleep(for: .milliseconds(400))
    #expect(!FileManager.default.fileExists(atPath: h.indexURL.path) && h.wire.embeds.count < 5)
    // następne pytanie buduje nowy indeks tylko w nowej przestrzeni
    await h.ask("What is the budget?")
    #expect(h.last?.answer != nil && h.space != oldSpace)
    #expect(h.storedIndex().fingerprints.count == 5)
    #expect(ArchiveIndex.load(from: h.indexURL, space: oldSpace).fingerprints.isEmpty)
}

@Test @MainActor func embeddingSwappedWithoutTheHookIsCaughtBeforeAnyInsert() async throws {
    let h = Harness(wire: Wire(delay: { $0.kind == "embeddings" ? .milliseconds(150) : nil }))
    fiveMeetings(h)
    h.model.ask("What is the budget?")
    await h.settle()
    h.model.confirmIndexing()
    await h.until { !h.wire.embeds.isEmpty }
    h.change(hook: false) { $0.embedding = RoleAssignment(providerID: h.embedProvider.id, model: "embed-2") }
    await h.settle()
    try await Task.sleep(for: .milliseconds(300))
    #expect(h.last?.failure == "The embedding model changed. Ask again.")
    #expect(!FileManager.default.fileExists(atPath: h.indexURL.path) && h.wire.embeds.count < 5)
}

@Test @MainActor func loadingSettingsAtStartDoesNotWipeTheIndex() async {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    h.model.settingsDidChange(old: GlobalSettings(), new: h.settings) // AppModel.load() przy starcie: nil → zapisany embedding
    await h.model.flushWrites()
    #expect(h.storedIndex().fingerprints["m1"] != nil)
}

// MARK: 17. błędy dostawców

@Test @MainActor func providerErrorsFailOnlyThroughTheConfiguredProvider() async {
    let chat500 = Harness(wire: Wire(chat: { _ in throw WireError(status: 500, body: "boom") }))
    chat500.addMeeting("m1", notes: "Budget is 10")
    await chat500.ask("What is the budget?")
    #expect(chat500.last?.failure?.hasPrefix("Couldn't get an answer from Chat Cloud:") == true && chat500.last?.failure?.contains("HTTP 500") == true)
    #expect(Set(chat500.wire.calls.map(\.host)).isSubset(of: ["embed.example.test", "chat.example.test"]))

    let embed401 = Harness(wire: Wire(embed: { _ in throw WireError(status: 401, body: "bad key") }))
    embed401.addMeeting("m1", notes: "Budget is 10")
    await embed401.ask("What is the budget?")
    #expect(embed401.last?.failure?.hasPrefix("Couldn't index your meetings with Embed Cloud:") == true && embed401.last?.failure?.contains("HTTP 401") == true)
    #expect(embed401.wire.chats.isEmpty && Set(embed401.wire.calls.map(\.host)) == ["embed.example.test"])
    #expect(embed401.storedIndex().fingerprints.isEmpty && !embed401.model.isBusy)
}

@Test @MainActor func unusableQueryVectorFailsInsteadOfGuessing() async {
    let h = Harness(wire: Wire(embed: { $0.input.contains("Question") || !$0.input.contains("\n") ? [0, 0, 0, 0] : concept($0.input) }))
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    #expect(h.last?.failure == ArchiveError.invalidVector.errorDescription && h.wire.chats.isEmpty)
}

// MARK: 18. zakres

@Test @MainActor func scopeIsFolderOrExplicitAllOrOpenMeetingAndNeverBroadens() async {
    let h = Harness()
    h.addMeeting("m1", title: "Alpha", notes: "Budget is 10", folder: "X")
    h.addMeeting("m2", title: "Beta", notes: "Budget is 99", folder: "Y")
    h.currentFolder = "X"
    #expect(ArchiveModel.resolve(.list, sessions: h.items, matches: { h.folders[$0.id] == "X" }, listLabel: "X", selectedID: nil)?.ids == ["m1"])
    #expect(ArchiveModel.resolve(.all, sessions: h.items, matches: { _ in false }, listLabel: "X", selectedID: nil)?.ids == ["m1", "m2"])
    #expect(ArchiveModel.resolve(.meeting, sessions: h.items, matches: { _ in true }, listLabel: "X", selectedID: nil) == nil)
    #expect(ArchiveModel.resolve(.meeting, sessions: h.items, matches: { _ in true }, listLabel: "X", selectedID: "gone") == nil)
    #expect(ArchiveModel.resolve(.meeting, sessions: h.items, matches: { _ in true }, listLabel: "X", selectedID: "m2")?.label == "This meeting: Beta")

    h.model.scope = .meeting // żadne spotkanie nie jest otwarte: bez pytania, bez poszerzenia
    await h.ask("What is the budget?")
    #expect(h.last?.failure == "Open a meeting first, or choose All meetings." && h.wire.calls.isEmpty)

    h.model.scope = .list
    await h.ask("What is the budget?")
    #expect(h.wire.chats.last?.user.contains("Budget is 99") == false && h.last?.answer?.sources.map(\.sessionID) == ["m1"])
    h.model.scope = .all
    await h.ask("What is the budget?")
    #expect(h.model.turns.last?.scopeLabel == "All meetings" && h.model.turns.last?.scopeIDs == ["m1", "m2"])
    #expect(h.wire.chats.last?.user.contains("Budget is 99") == true)
    h.selected = "m2"
    h.model.scope = .meeting
    await h.ask("What is the budget?")
    #expect(h.model.turns.last?.scopeLabel == "This meeting: Beta" && h.last?.answer?.sources.map(\.sessionID) == ["m2"])
}

// MARK: 19. kolejne pytania w rozmowie

private func followUpWire() -> Wire {
    Wire(chat: { call in
        let question = call.user.components(separatedBy: "\n\nQuestion: ").last ?? ""
        if question.lowercased().contains("who") { return "Ann owns it [1]." }
        return call.user.contains("Budget is 20") ? "Budget is 20 [1]." : "Budget is 10 [1]."
    })
}

@Test @MainActor func followUpCarriesQuotedHistoryAndFreshEvidenceOnly() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10. Owner is Ann.")
    await h.ask("What is the budget?")
    #expect(h.last?.answer?.text == "Budget is 10 [1].")
    await h.ask("And who owns it?")
    #expect(h.wire.embeds.last?.input == "What is the budget?\nAnd who owns it?") // zapytanie zawiera poprzednie pytanie
    let prompt = try #require(h.wire.chats.last?.user)
    #expect(prompt.contains("Earlier conversation (quoted, not a source):\nQ: What is the budget?\nA: Budget is 10.\n"))
    #expect(h.wire.chats.last.map { _ in true } == true)
    let answer = try #require(h.last?.answer)
    #expect(answer.sources.map(\.sessionID) == ["m1"] && answer.sources[0].text.contains("Owner is Ann")) // źródła tylko ze świeżych fragmentów
    h.model.clear() // „New chat": historia znika
    await h.ask("And who owns it?")
    #expect(h.wire.chats.last?.user.contains("Earlier conversation") == false)
}

@Test @MainActor func historyTurnWithEditedMeetingIsDroppedEvenAfterReindexing() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    #expect(h.last?.answer?.text == "Budget is 10 [1].")
    h.edit("m1", notes: "Budget is 20") // ten sam identyfikator, nowy odcisk po ponownym indeksowaniu
    await h.ask("And what about costs?")
    let prompt = try #require(h.wire.chats.last?.user)
    #expect(!prompt.contains("Earlier conversation") && !prompt.contains("Budget is 10"))
    #expect(prompt.contains("Budget is 20") && h.last?.answer?.text == "Budget is 20 [1].")
    await h.ask("And who is it?") // teraz poprzednia odpowiedź (świeża) wchodzi do kontekstu
    #expect(h.wire.chats.last?.user.contains("A: Budget is 20.") == true)
}

@Test @MainActor func historyTurnWithDeletedMeetingOrOtherScopeIsNotIncluded() async {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10")
    h.addMeeting("m2", notes: "Owner is Ann")
    h.fixedScope = ["m1", "m2"] // ten sam zakres przed i po usunięciu
    await h.ask("What is the budget?")
    h.delete("m1")
    await h.ask("And who owns it?")
    #expect(h.wire.chats.last?.user.contains("Earlier conversation") == false && h.last?.answer?.sources.map(\.sessionID) == ["m2"])

    let scoped = Harness(wire: followUpWire())
    scoped.addMeeting("m1", notes: "Budget is 10", folder: "X")
    scoped.addMeeting("m2", notes: "Owner is Ann", folder: "Y")
    scoped.currentFolder = "X"
    await scoped.ask("What is the budget?")
    scoped.currentFolder = nil // zakres się zmienił
    await scoped.ask("And who owns it?")
    #expect(scoped.wire.chats.last?.user.contains("Earlier conversation") == false)
}

// MARK: 20. sto spotkań

@Test @MainActor func hundredMeetingsIndexSearchAndKeepStableOrder() async throws {
    let h = Harness()
    for i in 1...100 { h.addMeeting(String(format: "m%03d", i), title: "Meeting \(i)", notes: "Item \(i): budget review, costs line \(i)") }
    await h.ask("What are the costs?", confirm: false)
    #expect(h.model.consent?.meetings == 100)
    h.model.confirmIndexing()
    await h.settle()
    let first = try #require(h.last?.answer)
    #expect(h.wire.embeds.count == 101 && h.storedIndex().fingerprints.count == 100)
    #expect(first.sources.count == 1 && h.wire.chats.last?.user.components(separatedBy: "\n[").count ?? 0 > 6)
    await h.ask("What are the costs?")
    #expect(h.last?.answer == first && h.wire.embeds.count == 102) // bez ponownego embeddingu, ten sam wynik
    let prompts = h.wire.chats.suffix(2).map(\.user)
    #expect(prompts[1].contains("Earlier conversation (quoted, not a source):"))
    let evidence = prompts.map { $0.components(separatedBy: "Excerpts:\n").last?.components(separatedBy: "\n\nQuestion:").first }
    #expect(evidence[0] == evidence[1])
}

// MARK: 21. trwała historia rozmów

@MainActor private func chatFiles(_ h: Harness) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: h.chatsURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
}

@Test @MainActor func completedAnswerIsOnDiskImmediatelyAndRestartRestoresItWithoutSending() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10")
    h.model.ask("What is the budget?")
    await h.until { h.model.consent != nil }
    h.model.confirmIndexing()
    await h.until { h.last?.answer != nil }
    // bez flushWrites i bez czekania: zapis rozmowy jest synchroniczny z publikacją odpowiedzi
    let saved = try h.store.load(h.model.currentChatID)
    #expect(saved.turns.count == 1 && saved.turns[0].kind == .answered && saved.title == "What is the budget?")
    #expect(saved.scope == nil) // tryb dawny: bez automatycznego zakresu
    let raw = try String(contentsOf: h.store.url(for: h.model.currentChatID), encoding: .utf8)
    #expect(!raw.contains("test-fake") && saved.turns[0].sources?.allSatisfy { $0.vector.isEmpty } == true)
    await h.settle()

    let calls = h.wire.calls.count
    let restarted = Harness(like: h)
    restarted.model.loadChats()
    #expect(restarted.model.savedChats.map(\.id) == [h.model.currentChatID] && restarted.model.persistenceError == nil)
    restarted.model.openChat(h.model.currentChatID)
    #expect(restarted.model.turns.count == 1 && restarted.model.turns[0].state.answer?.text == "Budget is 10 [1].")
    #expect(restarted.model.currentChatTitle == "What is the budget?" && !restarted.model.isBusy && h.wire.calls.count == calls)
}

@Test @MainActor func newChatKeepsThePreviousOneAndPastChatsSortByActivityAndContinue() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10. Owner is Ann.")
    await h.ask("What is the budget?")
    let first = h.model.currentChatID
    h.model.newChat()
    #expect(h.model.turns.isEmpty && h.model.currentChatID != first && h.model.currentChatTitle.isEmpty)
    #expect(chatFiles(h).count == 1) // pusty szkic nie jest zapisywany
    try await Task.sleep(for: .milliseconds(1_100))
    await h.ask("Who owns it?")
    let second = h.model.currentChatID
    #expect(chatFiles(h).count == 2)
    h.model.loadChats()
    #expect(h.model.savedChats.map(\.id) == [second, first])
    h.model.openChat(first)
    #expect(h.model.currentChatID == first && h.model.turns.count == 1)
    await h.ask("And who owns it?") // kontynuacja zapisanej rozmowy z jej historią
    #expect(h.wire.chats.last?.user.contains("Earlier conversation") == true)
    #expect(try h.store.load(first).turns.count == 2 && h.store.load(second).turns.count == 1)
}

@Test @MainActor func interruptedAnswerIsRecoveredAsInterruptedAndNeverResent() async throws {
    let h = Harness(wire: Wire(delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(500) : nil }))
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("warm up the index")
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    let id = h.model.currentChatID
    let crashed = try Data(contentsOf: h.store.url(for: id)) // stan na dysku w chwili „awarii"
    #expect(try h.store.load(id).turns.last?.kind == .working)
    h.model.cancel()
    await h.settle()
    try crashed.write(to: h.store.url(for: id))

    let calls = h.wire.calls.count
    let restarted = Harness(like: h)
    restarted.model.openChat(id)
    let last = restarted.model.turns.last?.state
    #expect(last?.failure?.contains("interrupted") == true && !restarted.model.isBusy)
    try await Task.sleep(for: .milliseconds(300))
    #expect(h.wire.calls.count == calls) // restart niczego nie wysłał ponownie
}

@Test @MainActor func corruptMismatchedAndSymlinkedFilesAreSkippedAndGoodChatsSurvive() async throws {
    let h = Harness()
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    let good = h.model.currentChatID
    let fm = FileManager.default
    try Data("{ not json".utf8).write(to: h.store.url(for: UUID()))
    // poprawna rozmowa pod cudzą nazwą pliku
    try fm.copyItem(at: h.store.url(for: good), to: h.store.url(for: UUID()))
    // dowiązanie do poprawnej rozmowy
    let outside = h.dir.appendingPathComponent("outside.json")
    var matching = try h.store.load(good)
    matching.id = UUID()
    let link = h.store.url(for: matching.id)
    try h.store.save(matching)
    try fm.moveItem(at: link, to: outside)
    try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    try Data("x".utf8).write(to: h.chatsURL.appendingPathComponent("notes.json"))

    h.model.loadChats()
    #expect(h.model.savedChats.map(\.id) == [good])
    #expect(h.model.persistenceError?.contains("4 saved chats were unreadable") == true)

    let badID = UUID()
    try Data("{ not json".utf8).write(to: h.store.url(for: badID))
    h.model.newChat()
    h.model.openChat(badID)
    #expect(h.model.persistenceError?.hasPrefix("Couldn't open this chat") == true && h.reports.last?.hasPrefix("Couldn't open") == true)
    #expect(try h.store.load(good).turns.count == 1) // poprawny plik nietknięty
    h.model.openChat(good)
    #expect(h.model.turns.count == 1 && h.model.persistenceError == nil)
}

@Test @MainActor func saveFailureIsVisibleKeepsThePreviousFileAndTheAnswerStaysShown() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("What is the budget?")
    let id = h.model.currentChatID
    #expect(h.model.persistenceError == nil)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: h.chatsURL.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: h.chatsURL.path) }
    await h.ask("And who owns it?")
    #expect(h.last?.answer != nil) // odpowiedź jest widoczna mimo błędu zapisu
    #expect(h.model.persistenceError?.hasPrefix("Couldn't save this chat") == true && h.reports.contains { $0.hasPrefix("Couldn't save this chat") })
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: h.chatsURL.path)
    #expect(try h.store.load(id).turns.count == 1) // poprzednia wersja nietknięta
    await h.ask("Who owns it?") // po naprawie zapis wraca i błąd znika
    #expect(h.model.persistenceError == nil)
    #expect(try h.store.load(id).turns.count == 3)
}

@Test @MainActor func conversationScopeIsAutomaticStableAndNeverBroadens() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10", folder: "X")
    h.addMeeting("m2", notes: "Budget is 99", folder: "Y")
    h.useAutomaticScope()
    h.currentFolder = "X"
    #expect(h.model.currentScope == .folder("X") && h.model.currentScopeLabel == "X")
    await h.ask("What is the budget?")
    #expect(h.model.turns[0].scopeIDs == ["m1"] && h.model.currentScope == .folder("X"))
    h.currentFolder = nil // użytkownik przechodzi gdzie indziej: wątek zachowuje zakres
    await h.ask("And what about costs?")
    #expect(h.model.turns[1].scopeIDs == ["m1"] && h.wire.chats.last?.user.contains("Budget is 99") == false)
    #expect(h.wire.chats.last?.user.contains("Earlier conversation") == true) // ten sam zakres: historia zostaje
    #expect(try h.store.load(h.model.currentChatID).scope == .folder("X"))

    // restart: zapisany zakres wraca z pliku, nie z bieżącej selekcji
    let restarted = Harness(like: h)
    restarted.useAutomaticScope()
    restarted.model.openChat(h.model.currentChatID)
    #expect(restarted.model.currentScope == .folder("X") && restarted.model.currentScopeLabel == "X")
    await restarted.ask("Budget again?", confirm: false)
    #expect(restarted.model.turns.last?.scopeIDs == ["m1"])

    // członkostwo folderu zmienia się: zakres rozwiązywany na nowo, stara odpowiedź spoza zakresu nie wchodzi do kontekstu
    restarted.addMeeting("m3", notes: "Budget is 33", folder: "X")
    await restarted.ask("And now?", confirm: false)
    #expect(restarted.model.turns.last?.scopeIDs == ["m1", "m3"])
    #expect(restarted.wire.chats.last?.user.contains("Earlier conversation") == false)

    // folder zniknął: bez pytania i bez poszerzenia do całego archiwum
    restarted.existingFolders.remove("X")
    let chats = restarted.wire.chats.count
    restarted.model.ask("Anything?")
    #expect(restarted.last?.failure?.hasPrefix("This chat's folder or meeting no longer exists") == true)
    #expect(restarted.wire.chats.count == chats)

    // spotkanie: nowa rozmowa dziedziczy otwarte spotkanie; po jego usunięciu zakres znika
    restarted.model.newChat()
    restarted.selected = "m2"
    #expect(restarted.model.currentScope == .meeting("m2") && restarted.model.currentScopeLabel == "This meeting: Standup")
    await restarted.ask("What is the budget?", confirm: false)
    #expect(restarted.model.turns[0].scopeIDs == ["m2"])
    restarted.selected = nil
    restarted.delete("m2")
    restarted.model.ask("Still there?")
    #expect(restarted.last?.failure?.hasPrefix("This chat's folder or meeting no longer exists") == true)
    #expect(restarted.model.currentScopeLabel == "Scope no longer available")
}

@Test @MainActor func unfiledScopeFollowsMembershipAndDeletedFolderCountsAsNoFolder() async {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10", folder: "X")
    h.addMeeting("m2", notes: "Budget is 99")
    h.addMeeting("m3", notes: "Budget is 55", folder: "GONE") // folder już nie istnieje
    h.useAutomaticScope()
    h.model.captureScope = { .unfiled }
    await h.ask("What is the budget?")
    #expect(h.model.turns[0].scopeIDs == ["m2", "m3"] && h.model.currentScope == .unfiled)
}

@Test @MainActor func staleSourcesAfterRestartNeverEnterFollowUpContext() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10. Owner is Ann.")
    h.useAutomaticScope()
    await h.ask("What is the budget?")
    let id = h.model.currentChatID
    await h.settle()

    // bez zmian po restarcie: historia wchodzi do kontekstu
    let same = Harness(like: h)
    same.useAutomaticScope()
    same.model.openChat(id)
    await same.ask("And who owns it?", confirm: false)
    #expect(same.wire.chats.last?.user.contains("A: Budget is 10.") == true)

    // edycja po zamknięciu aplikacji: stara odpowiedź nie wchodzi
    h.edit("m1", notes: "Budget is 20. Owner is Ann.")
    let edited = Harness(like: h)
    edited.useAutomaticScope()
    edited.model.openChat(id)
    await edited.ask("And who owns it?", confirm: false)
    var prompt = edited.wire.chats.last?.user ?? ""
    #expect(!prompt.contains("Earlier conversation") && !prompt.contains("Budget is 10") && edited.last?.answer != nil)

    // usunięcie: to samo; źródło z poprzedniej tury nie jest ani cytowane, ani cytowalne
    let kept = Harness(like: h)
    kept.addMeeting("m2", notes: "Owner is Bob")
    kept.delete("m1")
    kept.useAutomaticScope()
    kept.model.openChat(id)
    await kept.ask("And who owns it?") // usunięcie opróżnia indeks, więc pierwsze budowanie znów pyta o zgodę
    prompt = kept.wire.chats.last?.user ?? ""
    #expect(!prompt.contains("Earlier conversation") && kept.last?.answer?.sources.map(\.sessionID) == ["m2"])
}

@Test @MainActor func tamperedFingerprintsKeepTurnsOutOfContext() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10")
    h.useAutomaticScope()
    await h.ask("What is the budget?")
    let id = h.model.currentChatID
    var saved = try h.store.load(id)
    saved.turns[0].fingerprints = [:] // brak odcisków = brak zaufania
    try h.store.save(saved)
    let restarted = Harness(like: h)
    restarted.useAutomaticScope()
    restarted.model.openChat(id)
    #expect(restarted.model.turns[0].state.answer != nil) // nadal widoczna
    await restarted.ask("And who owns it?", confirm: false)
    #expect(restarted.wire.chats.last?.user.contains("Earlier conversation") == false)
}

@Test @MainActor func lateResultAfterNewChatOrSwitchNeverTouchesAnotherChat() async throws {
    let h = Harness(wire: Wire(chat: { $0.user.contains("slow") ? "slow reply [1]" : "fresh reply [1]" },
                               delay: { $0.kind == "chat" && $0.user.contains("slow") ? .milliseconds(400) : nil }))
    h.addMeeting("m1", notes: "Budget is 10")
    await h.ask("warm up the index")
    let warm = h.model.currentChatID
    h.model.ask("slow budget?")
    await h.until { h.wire.chats.count == 2 }
    h.model.newChat() // unieważnia trwające pytanie
    let draft = h.model.currentChatID
    #expect(draft != warm && h.model.turns.isEmpty)
    try await Task.sleep(for: .milliseconds(700))
    #expect(h.model.turns.isEmpty && chatFiles(h).count == 1 && !FileManager.default.fileExists(atPath: h.store.url(for: draft).path))
    let saved = try h.store.load(warm)
    #expect(saved.turns.count == 2 && saved.turns[1].kind == .cancelled)

    // przełączenie na inną rozmowę w trakcie pytania
    h.model.ask("slow again?")
    await h.until { h.wire.chats.count == 3 }
    let busy = h.model.currentChatID
    h.model.openChat(warm)
    try await Task.sleep(for: .milliseconds(700))
    #expect(h.model.currentChatID == warm && h.model.turns.allSatisfy { $0.state.answer?.text != "slow reply [1]" || $0.question == "warm up the index" })
    #expect(try h.store.load(busy).turns.last?.kind == .cancelled)
}

@Test @MainActor func persistedCitationsOutsideScopeNeverEnterFollowUp() async throws {
    let h = Harness(wire: followUpWire())
    h.addMeeting("m1", notes: "Budget is 10. Owner is Ann.", folder: "X")
    h.addMeeting("m2", notes: "Budget is 90. Owner is Bob.", folder: "Y")
    h.useAutomaticScope()
    h.currentFolder = "X"
    await h.ask("What is the budget?")
    let id = h.model.currentChatID
    var chat = try h.store.load(id)
    let outside = try #require(h.storedIndex().chunks.first { $0.sessionID == "m2" })
    let fingerprint = try #require(h.storedIndex().fingerprints["m2"])
    chat.turns[0].sources = [outside]
    chat.turns[0].text = "Outside the folder [1]."
    chat.turns[0].fingerprints = ["m2": fingerprint]
    try h.store.save(chat)

    let reopened = Harness(like: h)
    reopened.useAutomaticScope()
    reopened.existingFolders = h.existingFolders
    reopened.model.openChat(id)
    #expect(reopened.model.currentScope == .folder("X"))
    await reopened.ask("And who owns it?", confirm: false)
    let prompt = try #require(reopened.wire.chats.last?.user)
    #expect(!prompt.contains("Earlier conversation") && !prompt.contains("Outside the folder"))
    #expect(reopened.last?.answer?.sources.map(\.sessionID) == ["m1"])
}
