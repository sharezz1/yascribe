import Foundation
import MeetNotesProviders
import MeetNotesTranscription

public enum NoteGenerationError: Error, Equatable {
    case nothingToSummarize
    case failed(String)
}

/// Postęp „Generate notes" dla interfejsu: kolejny krok kondensacji (numeracja części zaczyna się od 1 w każdym przebiegu)
/// albo ostatnie wywołanie, które pisze notatkę (jedyny krok bez map-reduce).
public enum NoteProgress: Equatable, Sendable {
    case condensing(pass: Int, part: Int, of: Int)
    case writing

    public var text: String {
        switch self {
        case .condensing(let pass, let part, let count): "Condensing part \(part) of \(count) (pass \(pass))…"
        case .writing: "Writing the notes…"
        }
    }
}

/// „Generate notes": prompt → model → tytuł i treść → zapis. Nic nie jest zapisywane, gdy model zawiedzie.
/// Z budżetem kontekstu (lokalny model) zbyt długi prompt idzie przez map-reduce (spec fazy 2.0 §11.4, §14 pkt 4).
/// Anulowanie zadania przerywa kolejne wywołania i kończy się `CancellationError` — bez zapisu notatki.
public struct NoteGenerator: Sendable {
    public let client: OpenAICompatibleClient
    public let model: String
    /// Całkowity limit czasu odpowiedzi modelu (sekundy); po nim „Generate notes" kończy się błędem z nazwą modelu.
    public let timeout: Double

    /// Limit transportowy żądania (`ChatLimits.transport`) i `max_tokens` (tylko lokalnie; `nil` = bez pola).
    public let chatTimeout: Double
    public let maxTokens: Int?
    /// Limity jednej części mapy; `nil` = `ChatLimits.for(client.provider, call: .mapPart)`. Ustawiane w testach.
    public var mapLimits: ChatLimits?

    /// Poziomy kondensacji (pierwsza mapa + hierarchia), po których zbyt długie wejście reduce jest jawnym błędem.
    static let maxMapLevels = 3

    public init(client: OpenAICompatibleClient, model: String, timeout: Double = 180, chatTimeout: Double = 120, maxTokens: Int? = nil) {
        self.client = client
        self.model = model
        self.timeout = timeout
        self.chatTimeout = chatTimeout
        self.maxTokens = maxTokens
    }

    /// `budget == nil` (API) — zawsze jeden przebieg. Z budżetem: jeden przebieg, gdy CAŁY prompt (z My notes i kontekstem) mieści
    /// się w `promptChars(replyTokens: noteReplyTokens)`; inaczej map każdej części, potem reduce (hierarchiczny, gdy trzeba).
    public func generate(session: URL, template: Template, transcript: Transcript, context: String,
                         notesLanguage: LanguageCode?, budget: ContextBudget? = nil, now: Date = Date(),
                         onProblem: @Sendable (String) -> Void = { _ in },
                         progress: (@Sendable (NoteProgress) -> Void)? = nil) async throws -> NoteSummary {
        let store = NotesStore(session: session)
        let myNotes = store.readMyNotes()
        guard var prompt = NotePromptBuilder.build(template: template, transcript: transcript, myNotes: myNotes,
                                                   context: context, notesLanguage: notesLanguage) else {
            throw NoteGenerationError.nothingToSummarize
        }
        var condensedParts: Int?
        if let budget, prompt.chars > budget.promptChars(replyTokens: ContextBudget.noteReplyTokens) {
            let reduced = try await reducePrompt(template: template, lines: NotePromptBuilder.transcriptLines(transcript),
                                                 myNotes: myNotes, context: context, notesLanguage: notesLanguage,
                                                 budget: budget, progress: progress)
            prompt = reduced.0
            condensedParts = reduced.1
        }
        progress?(.writing)
        let reply = try await complete(prompt)
        // Odpowiedź mogła dojść w chwili anulowania: anulowane generowanie nie zostawia notatki na dysku.
        try Task.checkCancellation()
        let (title, body) = NoteTitle.parse(reply)
        guard !body.isEmpty else { throw NoteGenerationError.failed("\(model) returned an empty reply.") }
        let summary = NoteSummary(title: title, markdown: body, templateID: template.id, model: model,
                                  context: context, generatedAt: now, condensedParts: condensedParts)
        do {
            // Nieczytelny stary summary.json został odłożony na bok przed zapisem — powiedz to użytkownikowi.
            if let problem = try store.writeSummary(summary, now: now) { onProblem(problem) }
        } catch {
            throw NoteGenerationError.failed("Couldn't save the notes: \(error)")
        }
        return summary
    }

    /// Wywołanie notatki/reduce: limity notatki (`timeout`, `chatTimeout`, `maxTokens`).
    private func complete(_ prompt: NotePrompt) async throws -> String {
        do {
            let client = client, model = model, chatTimeout = chatTimeout, maxTokens = maxTokens
            return try await withDeadline(timeout) {
                try await client.chat(model: model, system: prompt.system, user: prompt.user, timeout: chatTimeout, maxTokens: maxTokens)
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() } // anulowanie to nie błąd modelu
            throw NoteGenerationError.failed(ContextError.describe(model: model, error, provider: client.provider, transport: chatTimeout,
                                                                maxTokens: maxTokens))
        }
    }

    // MARK: map-reduce

    /// Prompt reduce, który MIEŚCI się w budżecie (nigdy nie wysyłamy więcej). Map wszystkich części, a gdy suma wyjść nie
    /// wchodzi — ponowna kondensacja wyjść (do `maxMapLevels` poziomów); inaczej jawny błąd.
    /// Zwraca też liczbę części pierwszego przebiegu (znacznik „Long meeting" w notatce).
    private func reducePrompt(template: Template, lines: [String], myNotes: String, context: String, notesLanguage: LanguageCode?,
                              budget: ContextBudget, progress: (@Sendable (NoteProgress) -> Void)?) async throws -> (NotePrompt, Int) {
        let limit = budget.promptChars(replyTokens: ContextBudget.noteReplyTokens)
        func reduce(_ lines: [String]) -> NotePrompt {
            NotePromptBuilder.prompt(template: template, lines: lines, myNotes: myNotes, context: context,
                                     notesLanguage: notesLanguage, condensed: true)
        }
        guard limit > 0 else {
            throw NoteGenerationError.failed("\(model)'s Context window (\(budget.tokens) tokens) is too small for notes.")
        }
        // Sam prompt szablonu (bez My notes i kontekstu) ponad budżetem: okno za małe na notatki — nie wina użytkownika.
        let bare = NotePromptBuilder.prompt(template: template, lines: [], myNotes: "", context: "", notesLanguage: notesLanguage,
                                            condensed: true).chars
        guard bare <= limit else {
            throw NoteGenerationError.failed("\(model)'s Context window (\(budget.tokens) tokens) is too small for notes.")
        }
        // My notes + kontekst + prompt szablonu same ponad budżetem — mapa niczego nie naprawi, więc nie marnujemy wywołań.
        let room = limit - reduce([]).chars // miejsce na linie transkryptu w prompcie reduce
        guard room >= 0 else {
            throw NoteGenerationError.failed("Your notes and context are too long for this model's Context window.")
        }
        let partChars = min(ContextBudget.mapPartCap,
                            budget.pairedInputChars(fixedChars: NotePromptBuilder.mapSystemChars, replyFactor: ContextBudget.mapReplyFactor))
        guard partChars > 0 else {
            throw NoteGenerationError.failed("\(model)'s Context window (\(budget.tokens) tokens) is too small for notes.")
        }
        var current = lines
        var firstPassParts = 0
        for level in 1...Self.maxMapLevels {
            let before = current.joined(separator: "\n").count
            let (condensed, partCount) = try await map(current, maxChars: partChars, notesLanguage: notesLanguage, budget: budget,
                                                       pass: level, progress: progress)
            current = condensed
            if level == 1 { firstPassParts = partCount }
            let prompt = reduce(current)
            // Warunek, na którym stoi cała gwarancja: reduce nigdy nie przekracza budżetu.
            if prompt.chars <= limit { return (prompt, firstPassParts) }
            // Wczesne przerwanie: gdyby kolejne poziomy kondensowały TAK SAMO jak ten (optymistycznie — skondensowane
            // linie kurczą się słabiej), a i tak nie zmieszczą się w prompcie, to dalsze wywołania są stracone.
            let after = current.joined(separator: "\n").count
            let ratio = Double(after) / Double(max(before, 1))
            if Double(after) * pow(ratio, Double(Self.maxMapLevels - level)) > Double(room) { break }
        }
        throw NoteGenerationError.failed(
            "The transcript is too long for this model's Context window. Raise the server's context length "
                + "(for Ollama: OLLAMA_CONTEXT_LENGTH=16384 or more) and the Context window field in Settings, or use a model with a longer context.")
    }

    /// Linie wyjścia mapy w formacie transkryptu (`[m:ss]` / `[h:mm:ss]` na początku); wstęp, punktory i płoty kodu odpadają.
    /// `nil`, gdy model nie zachował formatu (mniej niż połowa niepustych linii ma znacznik) — wtedy część się nie udała.
    static func transcriptLines(inReply reply: String) -> [String]? {
        func hasClock(_ line: String) -> Bool {
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return false }
            let fields = line[line.index(after: line.startIndex)..<close].split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2 || fields.count == 3 else { return false }
            return fields.enumerated().allSatisfy { i, f in
                f.allSatisfy(\.isASCII) && f.allSatisfy(\.isNumber) && (i == 0 ? !f.isEmpty : f.count == 2)
            }
        }
        let all = reply.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let kept = all.filter(hasClock)
        return !kept.isEmpty && kept.count * 2 >= all.count ? kept : nil
    }

    /// Jeden poziom: podział na części, map każdej po kolei (limit czasu NA WYWOŁANIE). Błąd części = błąd całości („Part n of m failed").
    /// Zwraca też liczbę części tego poziomu.
    private func map(_ lines: [String], maxChars: Int, notesLanguage: LanguageCode?, budget: ContextBudget, pass: Int,
                     progress: (@Sendable (NoteProgress) -> Void)?) async throws -> ([String], Int) {
        let parts = try TranscriptSplitter.parts(lines, maxChars: maxChars)
        let limits = mapLimits ?? ChatLimits.for(client.provider, call: .mapPart)
        var out: [String] = []
        for (i, part) in parts.enumerated() {
            try Task.checkCancellation()
            progress?(.condensing(pass: pass, part: i + 1, of: parts.count))
            let prompt = NotePromptBuilder.mapPrompt(part: part, index: i + 1, count: parts.count, notesLanguage: notesLanguage)
            // Odpowiedź dostaje całe miejsce, które po prompcie zostaje w oknie (nie ciasną połowę wejścia), ale nie więcej niż
            // długość wejścia: dłuższa „kondensacja" to ucieczka modelu. Część ≤ `pairedInputChars`, więc miejsce jest ≥ połowie wejścia.
            let room = budget.tokens - ContextBudget.marginTokens - Int((Double(prompt.chars) / ContextBudget.charsPerToken).rounded(.up))
            let replyTokens = max(1, min(room, ContextBudget.maxTokens(inputChars: prompt.user.count, replyFactor: 1.0)))
            do {
                let client = client, model = model
                let reply = try await withDeadline(limits.soft) {
                    try await client.chat(model: model, system: prompt.system, user: prompt.user, timeout: limits.transport,
                                          maxTokens: replyTokens, temperature: limits.temperature)
                }
                guard let kept = Self.transcriptLines(inReply: reply) else {
                    throw NoteGenerationError.failed("Part \(i + 1) of \(parts.count) failed: the model didn't keep the transcript format")
                }
                out += kept
            } catch where Task.isCancelled || error is CancellationError {
                throw CancellationError() // URLSession zgłasza anulowanie jako `URLError.cancelled`, nie `CancellationError`
            } catch let e as NoteGenerationError {
                throw e
            } catch ProviderError.replyCutOff {
                // Ucięta część mapy: model nie skondensował jej dość (limit wyjścia to nasz `max_tokens`) — nie rada o „Context window".
                throw NoteGenerationError.failed("\(model) didn't condense part \(i + 1) of \(parts.count) enough. Try another model.")
            } catch {
                let why = ContextError.describe(model: model, error, provider: client.provider, transport: limits.transport, isLocal: true)
                throw NoteGenerationError.failed("Part \(i + 1) of \(parts.count) failed: \(why)")
            }
        }
        return (out, parts.count)
    }
}
