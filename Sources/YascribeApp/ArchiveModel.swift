import Foundation
import Observation
import YascribeNotes
import YascribeProviders
import YascribeTranscription

/// „Ask anything" o spotkaniach: indeks archiwum, pytanie → fragmenty → odpowiedź z przypisami, rozmowa w pamięci
/// (bez zapisu na dysk). Jedna operacja naraz; nowe pytanie, anulowanie, „New chat" i zmiana ustawień unieważniają poprzednią,
/// a wynik publikowany jest tylko, gdy jej bilet (`token`) jest nadal bieżący.
@MainActor
@Observable
final class ArchiveModel {
    enum AskScope: Equatable { case list, all, meeting }
    enum TurnState: Equatable {
        case working(String), answered(ArchiveAsk.Answer), noAnswer(String), failed(String, opensSettings: Bool), cancelled
    }
    struct Turn: Identifiable, Equatable {
        let id: UUID
        let question: String
        let scopeLabel: String
        let scopeIDs: Set<String>
        var state: TurnState
    }

    /// Dawny przełącznik zakresu; używany tylko, gdy `AppModel` nie podłączył `captureScope`/`resolveSavedScope`.
    var scope: AskScope = .list
    private(set) var turns: [Turn] = []

    // Trwała rozmowa (`chats/<UUID>.json`). Rozmowa dostaje zakres przy pierwszym pytaniu i go zachowuje.
    private(set) var currentChatID = UUID()
    private(set) var currentChatTitle = ""
    private(set) var savedChats: [ArchiveChatSummary] = []
    /// Widoczny błąd zapisu albo odczytu rozmów; `nil` = ostatnia operacja się udała.
    private(set) var persistenceError: String?
    @ObservationIgnored private var chatCreatedAt = Date()
    @ObservationIgnored private var chatScope: ArchiveScopeRef?
    @ObservationIgnored private var suppressSaves = false
    /// Katalog `chats/`; `nil` = rozmowy tylko w pamięci (testy i migawki bez katalogu danych).
    var chatsURL: URL?
    /// Zakres miejsca, w którym użytkownik jest teraz: całe archiwum, filtr folderu/bez folderu albo otwarte spotkanie.
    var captureScope: (() -> ArchiveScopeRef)?
    /// Zapisany zakres → bieżące członkostwo; `nil` = zakres już nie istnieje (nigdy nie poszerza się do całego archiwum).
    var resolveSavedScope: ((ArchiveScopeRef) -> (ids: Set<String>, label: String)?)?
    /// Zgoda na pierwsze budowanie indeksu u zdalnego dostawcy: do czasu `confirmIndexing()` albo `cancel()` nic nie jest wysyłane.
    private(set) var consent: (meetings: Int, provider: String, model: String)?
    /// Odciski spotkań z przypisów odpowiedzi w chwili publikacji — tylko one wpuszczają odpowiedź do kontekstu kolejnych pytań.
    @ObservationIgnored private var answeredFingerprints: [UUID: [String: String]] = [:]
    var isBusy: Bool { operation != nil || previewBusy }

    // Podłączane przez `AppModel`.
    var sources: () -> [ArchiveIndex.Source] = { [] }
    /// Jedno spotkanie; tańsze niż `sources()` przy sprawdzaniu każdego wstawienia. Domyślnie przez `sources()`.
    var sourceFor: ((String) -> ArchiveIndex.Source?)?
    var embedding: () -> RoleAssignment? = { nil }
    var askModel: () -> RoleAssignment? = { nil }
    var makeClient: (UUID) -> Result<OpenAICompatibleClient, AppModel.ClientProblem> = { _ in
        .failure(AppModel.ClientProblem(message: "No provider is available."))
    }
    /// Dostawca po id (bez klucza) — do przestrzeni wektorów w sprawdzeniach, które nie powinny dotykać pęku kluczy.
    var providerFor: (UUID) -> Provider? = { _ in nil }
    var resolveScope: (AskScope) -> (ids: Set<String>, label: String)? = { _ in nil }
    var labels: () -> [String: String] = { [:] }
    var isMoving: () -> Bool = { false }
    var report: (String) -> Void = { _ in }
    var indexURL: URL?

    private struct Run {
        let turnID: UUID
        let question: String
        let scopeIDs: Set<String>
        let scopeLabel: String
        let askAssignment: RoleAssignment
        let askProvider: Provider
        let askClient: OpenAICompatibleClient
        let embedAssignment: RoleAssignment
        let embedClient: OpenAICompatibleClient
        let embedSpace: String
    }

    private struct Failure: Error {
        var message: String
        var opensSettings = false
    }

    @ObservationIgnored private var index = ArchiveIndex(space: "")
    @ObservationIgnored private var indexLoaded = false
    private var operation: (token: UUID, turn: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var awaitingConsent: Run?
    @ObservationIgnored private var writes: Task<Void, Never> = Task {}
    private var previewBusy = false

    private static let noEmbeddingMessage = "Choose an embedding model in Settings → Archive search to ask about your meetings."
    private static let noAskModelMessage = "Choose an Ask model in Settings → Archive search to ask about your meetings."
    private static let changedMessage = "A meeting or the Ask model changed while answering. Ask again."
    private static let embeddingChangedMessage = "The embedding model changed. Ask again."

    // MARK: Pytanie

    /// Jedyny sposób zbudowania źródła spotkania: My notes z bufora autozapisu albo z dysku (nigdy kopia z `SessionItem`,
    /// która bywa starsza), tytuł i notatka z `item`, transkrypt po Replacement.
    static func source(for item: SessionItem, notes: NotesModel, transcript: Transcript?) -> ArchiveIndex.Source {
        let myNotes = notes.pendingMyNotes(item.id) ?? NotesStore(session: item.url).readMyNotes()
        return ArchiveIndex.Source(sessionID: item.id, title: item.title, myNotes: myNotes,
                                   summary: item.notes.summary?.markdown, transcript: transcript)
    }

    /// Zakres pytania: bieżący filtr listy, jawnie „All meetings" albo otwarte spotkanie (`nil` = żadne nie jest otwarte).
    /// Nigdy nie poszerza się sam.
    static func resolve(_ scope: AskScope, sessions: [SessionItem], matches: (SessionItem) -> Bool, listLabel: String,
                        selectedID: String?) -> (ids: Set<String>, label: String)? {
        switch scope {
        case .list: return (Set(sessions.filter(matches).map(\.id)), listLabel)
        case .all: return (Set(sessions.map(\.id)), "All meetings")
        case .meeting:
            guard let selectedID, let item = sessions.first(where: { $0.id == selectedID }) else { return nil }
            return ([selectedID], "This meeting: \(item.title)")
        }
    }

    /// Zakres bieżącej rozmowy: zapisany, a dla pustej rozmowy — miejsce, w którym użytkownik teraz jest.
    var currentScope: ArchiveScopeRef? { chatScope ?? (turns.isEmpty ? captureScope?() : nil) }

    /// Etykieta zakresu bieżącej rozmowy według bieżącego członkostwa.
    var currentScopeLabel: String { scopeLabel(for: currentScope) }
    var draftScopeLabel: String { scopeLabel(for: captureScope?()) }

    private func scopeLabel(for ref: ArchiveScopeRef?) -> String {
        guard let ref, let resolveSavedScope else { return resolveScope(scope)?.label ?? "This meeting" }
        return resolveSavedScope(ref)?.label ?? "Scope no longer available"
    }

    private static let scopeGoneMessage = "This chat's folder or meeting no longer exists. Start a new chat."
    private static let fullMessage = "This chat is full. Start a new chat."
    private static let interruptedMessage = "This answer was interrupted when Yascribe closed. Ask again."

    private func resolveForAsk() -> (ids: Set<String>, label: String)? {
        guard let captureScope, let resolveSavedScope else { return resolveScope(scope) }
        if chatScope == nil && turns.isEmpty { chatScope = captureScope() }
        return chatScope.flatMap(resolveSavedScope)
    }

    func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= ArchiveAsk.maxQuestionChars else { return report("Questions can be up to 1 000 characters.") }
        guard turns.count < ArchiveConversation.maxTurns else { return report(Self.fullMessage) }
        abort(.cancelled)
        let resolved = resolveForAsk()
        let turn = Turn(id: UUID(), question: text, scopeLabel: resolved?.label ?? "This meeting", scopeIDs: resolved?.ids ?? [],
                        state: .working("Checking your settings…"))
        turns.append(turn)
        if currentChatTitle.isEmpty { currentChatTitle = ArchiveConversation.title(from: text) }
        saveChat()
        do {
            if resolved == nil, captureScope != nil, resolveSavedScope != nil { throw Failure(message: Self.scopeGoneMessage) }
            start(try prepare(turn, resolved: resolved), consented: false)
        } catch let failure as Failure {
            setState(turn.id, .failed(failure.message, opensSettings: failure.opensSettings))
        } catch {
            setState(turn.id, .failed("\(error)", opensSettings: false))
        }
    }

    /// Sprawdzenia bez sieci; zamraża model odpowiedzi, dostawcę, przestrzeń embeddingu i zakres na całe pytanie.
    private func prepare(_ turn: Turn, resolved: (ids: Set<String>, label: String)?) throws -> Run {
        guard !isMoving() else { throw Failure(message: "Meetings are being moved to a new folder. Ask again when that finishes.") }
        guard let embed = embedding(), !embed.model.isEmpty else { throw Failure(message: Self.noEmbeddingMessage, opensSettings: true) }
        guard let ask = askModel(), !ask.model.isEmpty else { throw Failure(message: Self.noAskModelMessage, opensSettings: true) }
        let embedClient = try client(embed.providerID), askClient = try client(ask.providerID)
        guard let resolved else { throw Failure(message: "Open a meeting first, or choose All meetings.") }
        return Run(turnID: turn.id, question: turn.question, scopeIDs: resolved.ids, scopeLabel: resolved.label,
                   askAssignment: ask, askProvider: askClient.provider, askClient: askClient, embedAssignment: embed,
                   embedClient: embedClient, embedSpace: ArchiveIndex.space(provider: embedClient.provider, model: embed.model))
    }

    private func client(_ providerID: UUID) throws -> OpenAICompatibleClient {
        switch makeClient(providerID) {
        case .success(let client): return client
        case .failure(let problem): throw Failure(message: problem.message, opensSettings: true)
        }
    }

    private func start(_ run: Run, consented: Bool) {
        let token = UUID()
        let task = Task { await execute(run, token: token, consented: consented) }
        operation = (token, run.turnID, task)
    }

    /// Pierwsze budowanie indeksu u zdalnego dostawcy rusza dopiero po zgodzie.
    func confirmIndexing() {
        guard let run = awaitingConsent else { return }
        awaitingConsent = nil
        consent = nil
        setState(run.turnID, .working("Preparing the index…"))
        start(run, consented: true)
    }

    func cancel() { abort(.cancelled) }

    /// „New chat": anuluje trwającą operację (jej tura zapisuje się jako anulowana), zostawia poprzednią rozmowę na dysku
    /// i zaczyna pustą. Indeks zostaje. Pusty szkic nie jest zapisywany.
    func newChat() {
        abort(.cancelled)
        resetChat(id: UUID())
    }

    func clear() { newChat() }

    private func resetChat(id: UUID) {
        turns = []
        answeredFingerprints = [:]
        previewBusy = false
        currentChatID = id
        currentChatTitle = ""
        chatScope = nil
        chatCreatedAt = Date()
        suppressSaves = false
    }

    /// Lista „Past chats" z dysku (najnowsza aktywność pierwsza). Uszkodzony plik nie chowa pozostałych, tylko ustawia `persistenceError`.
    func loadChats() {
        guard let url = chatsURL else { return }
        let (chats, problems) = ArchiveConversationStore(directory: url).list()
        savedChats = chats
        persistenceError = problems == 0 ? nil
            : "\(problems) saved chat\(problems == 1 ? " was" : "s were") unreadable and skipped. The other chats are not affected."
    }

    /// Otwiera zapisaną rozmowę z jej zakresem i pozwala kontynuować. Trwająca operacja jest wcześniej unieważniona,
    /// a przerwane pytania (`working`) wracają jako przerwane — bez ponownego wysłania. Błąd = zostajemy w bieżącej rozmowie.
    func openChat(_ id: UUID) {
        guard let url = chatsURL else { return }
        if id == currentChatID, !turns.isEmpty, !suppressSaves { return }
        let loaded: ArchiveConversation
        do {
            loaded = try ArchiveConversationStore(directory: url).load(id)
        } catch {
            persistenceError = "Couldn't open this chat: \(error.localizedDescription)"
            report(persistenceError ?? "")
            return
        }
        abort(.cancelled)
        resetChat(id: loaded.id)
        currentChatTitle = loaded.title
        chatCreatedAt = loaded.createdAt
        chatScope = loaded.scope
        turns = loaded.turns.map(Self.turn)
        for stored in loaded.turns {
            guard stored.kind == .answered, let prints = stored.fingerprints, !prints.isEmpty,
                  Set(stored.sources?.map(\.sessionID) ?? []).isSubset(of: prints.keys) else { continue }
            answeredFingerprints[stored.id] = prints
        }
        persistenceError = nil
    }

    private static func turn(_ stored: ArchiveConversation.Turn) -> Turn {
        let state: TurnState
        switch stored.kind {
        case .working: state = .failed(interruptedMessage, opensSettings: false)
        case .answered:
            if let text = stored.text, let sources = stored.sources, !sources.isEmpty {
                state = .answered(ArchiveAsk.Answer(text: text, sources: sources))
            } else {
                state = .failed(interruptedMessage, opensSettings: false)
            }
        case .noAnswer: state = .noAnswer(stored.text ?? "")
        case .failed: state = .failed(stored.text ?? "", opensSettings: stored.opensSettings ?? false)
        case .cancelled: state = .cancelled
        }
        return Turn(id: stored.id, question: stored.question, scopeLabel: stored.scopeLabel, scopeIDs: Set(stored.scopeIDs), state: state)
    }

    private func stored(_ turn: Turn) -> ArchiveConversation.Turn {
        var out = ArchiveConversation.Turn(id: turn.id, question: turn.question, scopeLabel: String(turn.scopeLabel.prefix(300)),
                                           scopeIDs: turn.scopeIDs.sorted(), kind: .working)
        switch turn.state {
        case .working: out.kind = .working
        case .answered(let answer):
            out.kind = .answered
            out.text = answer.text
            out.sources = answer.sources
            out.fingerprints = answeredFingerprints[turn.id]
        case .noAnswer(let message): out.kind = .noAnswer; out.text = message
        case .failed(let message, let opens): out.kind = .failed; out.text = message; out.opensSettings = opens
        case .cancelled: out.kind = .cancelled
        }
        return out
    }

    /// Synchroniczny zapis atomowy bieżącej rozmowy: po powrocie plik jest na dysku, więc szybkie zamknięcie aplikacji
    /// nie gubi ukończonej odpowiedzi. Błąd jest widoczny (`persistenceError`, `report`), poprzedni plik zostaje.
    private func saveChat() {
        guard let url = chatsURL, !suppressSaves, !turns.isEmpty else { return }
        let now = Date()
        let conversation = ArchiveConversation(version: ArchiveConversation.currentVersion, id: currentChatID, title: currentChatTitle,
                                               createdAt: chatCreatedAt, updatedAt: now, scope: chatScope, turns: turns.map(stored))
        do {
            try ArchiveConversationStore(directory: url).save(conversation)
            persistenceError = nil
            let summary = ArchiveChatSummary(id: currentChatID, title: currentChatTitle, createdAt: chatCreatedAt, updatedAt: now,
                                             turns: turns.count, scope: chatScope)
            savedChats.removeAll { $0.id == summary.id }
            savedChats.insert(summary, at: 0)
        } catch {
            persistenceError = "Couldn't save this chat: \(error.localizedDescription)"
            report(persistenceError ?? "")
        }
    }

    /// Spotkanie usunięte: znikają jego fragmenty z pamięci i z pliku.
    func forget(_ sessionID: String) {
        if indexLoaded {
            guard index.fingerprints[sessionID] != nil else { return }
            index.remove(sessionID)
            persist(index)
        } else if let url = indexURL, let space = currentSpace() {
            enqueue {
                var stored = ArchiveIndex.load(from: url, space: space)
                guard stored.fingerprints[sessionID] != nil else { return nil }
                stored.remove(sessionID)
                return Self.write(stored, to: url)
            }
        }
    }

    /// `AppModel.settings` `didSet`. Zmiana embeddingu = nowa przestrzeń: anuluj, wyczyść indeks (pamięć i plik).
    /// Zmiana modelu odpowiedzi anuluje trwające pytanie, żeby spóźniona odpowiedź starego modelu nie została opublikowana.
    func settingsDidChange(old: GlobalSettings, new: GlobalSettings) {
        if old.embedding != nil, Self.differs(old.embedding, new.embedding) {
            abort(.failed(Self.embeddingChangedMessage, opensSettings: false))
            index = ArchiveIndex(space: "")
            indexLoaded = false
            persist(nil)
        }
        if Self.differs(old.askModel, new.askModel) {
            abort(.failed("The Ask model changed. Ask again.", opensSettings: false))
        }
    }

    /// Tylko migawki (`Snapshots.swift`): stan bez uruchamiania pracy.
    func setPreview(_ turns: [Turn], consent: (Int, String, String)? = nil) {
        abort(nil)
        resetChat(id: UUID())
        suppressSaves = true
        self.turns = turns
        self.consent = consent.map { (meetings: $0.0, provider: $0.1, model: $0.2) }
        previewBusy = consent == nil && turns.contains { if case .working = $0.state { true } else { false } }
    }

    /// Czeka na zakończenie zapisów indeksu (testy i końcowy zapis).
    func flushWrites() async { await writes.value }

    // MARK: Operacja

    private func execute(_ run: Run, token: UUID, consented: Bool) async {
        do {
            try await perform(run, token: token, consented: consented)
        } catch {
            // Anulowana, zastąpiona albo unieważniona zmianą ustawień: stan tury jest już ustawiony.
            guard operation?.token == token else { return }
            operation = nil
            if Self.isCancellation(error) {
                setState(run.turnID, .cancelled)
            } else if let failure = error as? Failure {
                setState(run.turnID, .failed(failure.message, opensSettings: failure.opensSettings))
            } else {
                setState(run.turnID, .failed(error.localizedDescription, opensSettings: false))
            }
            return
        }
        if operation?.token == token { operation = nil }
    }

    private func perform(_ run: Run, token: UUID, consented: Bool) async throws {
        guard !isMoving() else { throw Failure(message: "Meetings are being moved to a new folder. Ask again when that finishes.") }
        try await loadIndex(run, token: token)

        // Świeżość: zmienione i usunięte spotkania (także niezapisane My notes) znikają z indeksu przed czymkolwiek.
        let firstBuild = index.fingerprints.isEmpty
        let before = index
        let pending = index.reconcile(sources())
        if index != before { persist(index) }
        let toEmbed = pending.filter { !$0.pending.isEmpty }
        if !toEmbed.isEmpty, firstBuild, !consented, !run.embedClient.provider.isLocal {
            consent = (toEmbed.count, run.embedClient.provider.name, run.embedAssignment.model)
            awaitingConsent = run
            setState(run.turnID, .working("Waiting for your OK to index \(toEmbed.count) meetings…"))
            operation = nil
            return
        }

        try await buildIndex(pending, total: toEmbed.count, run: run, token: token)

        // Rozmowa: tylko poprzednie odpowiedzi z tego samego zakresu, których spotkania nadal mają ten sam odcisk
        // (po zestawieniu i po zakończeniu indeksowania — sama obecność spotkania nie wystarcza).
        let fingerprints = index.fingerprints
        let history = turns.filter { turn in
            guard turn.id != run.turnID, case .answered = turn.state, turn.scopeIDs == run.scopeIDs,
                  let cited = answeredFingerprints[turn.id], !cited.isEmpty else { return false }
            return cited.allSatisfy { run.scopeIDs.contains($0.key) && fingerprints[$0.key] == $0.value }
        }.suffix(ArchiveAsk.historyTurns)
        let pairs: [(question: String, answer: String)] = history.compactMap { turn in
            if case .answered(let answer) = turn.state { return (turn.question, answer.text) }
            return nil
        }

        let emptyMessage = "No meetings with transcripts or notes in \(run.scopeLabel)."
        guard index.chunks.contains(where: { run.scopeIDs.contains($0.sessionID) }) else { return publishNoAnswer(emptyMessage, run, token) }
        setState(run.turnID, .working("Searching your meetings…"))
        let snapshot = index
        let queryText = (pairs.last.map { "\($0.question)\n" } ?? "") + run.question
        let vector = try await wrap("Couldn't search with", provider: run.embedClient.provider, model: run.embedAssignment.model) {
            try await snapshot.embedQuery(queryText, client: run.embedClient, model: run.embedAssignment.model)
        }
        try check(token)
        let evidence = index.search(vector: vector, terms: run.question, in: run.scopeIDs)
        guard !evidence.isEmpty else { return publishNoAnswer(emptyMessage, run, token) }

        let model = run.askAssignment.model
        let limits = ChatLimits.for(run.askProvider, call: .note)
        let budget = run.askProvider.isLocal
            ? ContextBudget.resolve(provider: run.askProvider, detected: await ContextProbe.detect(client: run.askClient, model: model)) : nil
        try check(token)
        setState(run.turnID, .working("Answering…"))
        let names = labels()
        let answer = try await wrap("Couldn't get an answer from", provider: run.askProvider, model: model, transport: limits.transport,
                                    maxTokens: limits.maxTokens) {
            try await ArchiveAsk.answer(question: run.question, history: pairs, evidence: evidence, labels: names, client: run.askClient,
                                        model: model, budget: budget, limits: limits)
        }

        // Publikacja: bez `await` od zestawienia do ustawienia stanu.
        try check(token)
        let beforePublish = index
        index.reconcile(sources())
        if index != beforePublish { persist(index) }
        guard currentSpace() == run.embedSpace, askUnchanged(run) else { throw Failure(message: Self.changedMessage) }
        guard let answer else { return publishNoAnswer("I couldn't find a supported answer in \(run.scopeLabel).", run, token) }
        let cited = Set(answer.sources.map(\.sessionID))
        guard cited.allSatisfy({ index.fingerprints[$0] != nil && run.scopeIDs.contains($0) }) else {
            throw Failure(message: Self.changedMessage)
        }
        answeredFingerprints[run.turnID] = cited.reduce(into: [:]) { $0[$1] = index.fingerprints[$1] }
        setState(run.turnID, .answered(answer))
        operation = nil
    }

    private func publishNoAnswer(_ message: String, _ run: Run, _ token: UUID) {
        guard operation?.token == token else { return }
        setState(run.turnID, .noAnswer(message))
        operation = nil
    }

    /// Wczytuje indeks (poza głównym wątkiem) przy pierwszym użyciu; inna przestrzeń niż w pamięci → pusty indeks i usunięty plik.
    private func loadIndex(_ run: Run, token: UUID) async throws {
        await writes.value
        try check(token)
        if !indexLoaded {
            let url = indexURL, space = run.embedSpace
            let (loaded, existed) = await Task.detached { () -> (ArchiveIndex, Bool) in
                guard let url else { return (ArchiveIndex(space: space), false) }
                return (ArchiveIndex.load(from: url, space: space), FileManager.default.fileExists(atPath: url.path))
            }.value
            try check(token)
            if !indexLoaded {
                index = loaded
                indexLoaded = true
                // Plik z inną przestrzenią albo uszkodzony nie zostaje na dysku obok nowej.
                if existed, loaded.fingerprints.isEmpty { persist(loaded) }
            }
        }
        if index.space != run.embedSpace {
            index = ArchiveIndex(space: run.embedSpace)
            persist(nil)
        }
    }

    /// Osadza brakujące spotkania. Każde wstawienie na głównym wątku, po sprawdzeniu biletu, przestrzeni i odcisku spotkania.
    private func buildIndex(_ pending: [ArchiveIndex.Source], total: Int, run: Run, token: UUID) async throws {
        var done = 0, inserted = 0
        for source in pending {
            try check(token)
            var vectors: [[Double]] = []
            if !source.pending.isEmpty {
                done += 1
                setState(run.turnID, .working("Indexing \(done) of \(total) meetings…"))
                vectors = try await wrap("Couldn't index your meetings with", provider: run.embedClient.provider,
                                         model: run.embedAssignment.model) {
                    try await ArchiveIndex.embed(source, client: run.embedClient, model: run.embedAssignment.model)
                }
            }
            try check(token)
            guard currentSpace() == run.embedSpace else {
                abort(.failed(Self.embeddingChangedMessage, opensSettings: false))
                index = ArchiveIndex(space: "")
                indexLoaded = false
                persist(nil)
                throw CancellationError()
            }
            guard current(source.sessionID)?.fingerprint == source.fingerprint else { continue } // zmienione w trakcie: następne pytanie
            do { try index.insert(source, vectors: vectors) } catch { throw Failure(message: error.localizedDescription) }
            inserted += 1
            if inserted % 10 == 0 { persist(index) }
        }
        if inserted > 0 {
            persist(index)
            await writes.value
            try check(token)
        }
    }

    /// Błąd dostawcy → jednoznaczny komunikat z jego nazwą; anulowanie zostaje anulowaniem. Bez ponowień i bez innego dostawcy.
    private func wrap<T>(_ prefix: String, provider: Provider, model: String, transport: Double? = nil, maxTokens: Int? = nil,
                         _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            if error is ArchiveError { throw Failure(message: error.localizedDescription) }
            throw Failure(message: "\(prefix) \(provider.name): \(Self.reason(error, model: model, provider: provider, transport: transport, maxTokens: maxTokens))")
        }
    }

    private static func reason(_ error: Error, model: String, provider: Provider, transport: Double?, maxTokens: Int?) -> String {
        if case ProviderError.http(let status, let body) = error, !ContextError.isContextOverflow(error) {
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
            return detail.isEmpty ? "HTTP \(status)." : "HTTP \(status) (\(detail))."
        }
        return ContextError.describe(model: model, error, provider: provider, transport: transport, maxTokens: maxTokens)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled
    }

    // MARK: Stan

    private func check(_ token: UUID) throws {
        guard operation?.token == token else { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// Przerywa trwającą operację albo czekającą zgodę; jej tura dostaje `state` (`nil` = bez zmiany).
    private func abort(_ state: TurnState?) {
        let turnID = operation?.turn ?? awaitingConsent?.turnID
        operation?.task.cancel()
        operation = nil
        awaitingConsent = nil
        consent = nil
        if let turnID, let state { setState(turnID, state) }
    }

    private func setState(_ id: UUID, _ state: TurnState) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[i].state = state
        if case .working = state { return }
        saveChat()
    }

    private static func differs(_ a: RoleAssignment?, _ b: RoleAssignment?) -> Bool {
        a?.providerID != b?.providerID || a?.model != b?.model
    }

    /// Przestrzeń bieżącego embeddingu z ustawień (bez pęku kluczy); `nil` = nie wybrano albo dostawca zniknął.
    private func currentSpace() -> String? {
        guard let assignment = embedding(), let provider = providerFor(assignment.providerID) else { return nil }
        return ArchiveIndex.space(provider: provider, model: assignment.model)
    }

    private func current(_ sessionID: String) -> ArchiveIndex.Source? {
        if let sourceFor { return sourceFor(sessionID) }
        return sources().first { $0.sessionID == sessionID }
    }

    /// Ten sam model, ten sam dostawca (id i adres) co przy starcie pytania — także gdy podmieniono tylko domknięcia.
    private func askUnchanged(_ run: Run) -> Bool {
        guard let now = askModel(), !Self.differs(now, run.askAssignment), case .success(let client) = makeClient(now.providerID) else { return false }
        return client.provider.id == run.askProvider.id && client.provider.baseURL == run.askProvider.baseURL
    }

    // MARK: Zapis

    /// Zapisy po kolei, w tle; ostatni wygrywa. `nil` = usuń plik.
    private func persist(_ snapshot: ArchiveIndex?) {
        guard let url = indexURL else { return }
        enqueue { Self.write(snapshot, to: url) }
    }

    private func enqueue(_ work: @escaping @Sendable () -> String?) {
        let previous = writes
        writes = Task {
            await previous.value
            if let problem = await Task.detached(operation: { work() }).value { report(problem) }
        }
    }

    nonisolated private static func write(_ snapshot: ArchiveIndex?, to url: URL) -> String? {
        do {
            if let snapshot {
                try snapshot.save(to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return nil
        } catch {
            return "Couldn't save the archive index: \(error.localizedDescription)"
        }
    }
}
