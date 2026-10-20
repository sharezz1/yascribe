import Foundation
import MeetNotesProviders
import MeetNotesTranscription

public enum NoteGenerationError: Error, Equatable {
    case nothingToSummarize
    case failed(String)
}

/// „Generate notes": prompt → model → tytuł i treść → zapis. Nic nie jest zapisywane, gdy model zawiedzie.
/// Z budżetem kontekstu (lokalny model) zbyt długi prompt idzie przez map-reduce (spec fazy 2.0 §11.4, §14 pkt 4).
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
                         onProblem: @Sendable (String) -> Void = { _ in }) async throws -> NoteSummary {
        let store = NotesStore(session: session)
        let myNotes = store.readMyNotes()
        guard var prompt = NotePromptBuilder.build(template: template, transcript: transcript, myNotes: myNotes,
                                                   context: context, notesLanguage: notesLanguage) else {
            throw NoteGenerationError.nothingToSummarize
        }
        if let budget, prompt.chars > budget.promptChars(replyTokens: ContextBudget.noteReplyTokens) {
            prompt = try await reducePrompt(template: template, lines: NotePromptBuilder.transcriptLines(transcript), myNotes: myNotes,
                                            context: context, notesLanguage: notesLanguage, budget: budget)
        }
        let reply = try await complete(prompt)
        let (title, body) = NoteTitle.parse(reply)
        guard !body.isEmpty else { throw NoteGenerationError.failed("\(model) returned an empty reply.") }
        let summary = NoteSummary(title: title, markdown: body, templateID: template.id, model: model,
                                  context: context, generatedAt: now)
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
            throw NoteGenerationError.failed(ContextError.describe(model: model, error, provider: client.provider, transport: chatTimeout))
        }
    }

    // MARK: map-reduce

    /// Prompt reduce, który MIEŚCI się w budżecie (nigdy nie wysyłamy więcej). Map wszystkich części, a gdy suma wyjść nie
    /// wchodzi — ponowna kondensacja wyjść (do `maxMapLevels` poziomów); inaczej jawny błąd.
    private func reducePrompt(template: Template, lines: [String], myNotes: String, context: String, notesLanguage: LanguageCode?,
                              budget: ContextBudget) async throws -> NotePrompt {
        let limit = budget.promptChars(replyTokens: ContextBudget.noteReplyTokens)
        func reduce(_ lines: [String]) -> NotePrompt {
            NotePromptBuilder.prompt(template: template, lines: lines, myNotes: myNotes, context: context,
                                     notesLanguage: notesLanguage, condensed: true)
        }
        guard limit > 0 else {
            throw NoteGenerationError.failed("\(model)'s Context window (\(budget.tokens) tokens) is too small for notes.")
        }
        // My notes + kontekst + prompt szablonu same ponad budżetem — mapa niczego nie naprawi, więc nie marnujemy wywołań.
        guard reduce([]).chars <= limit else {
            throw NoteGenerationError.failed("Your notes and context are too long for this model's Context window.")
        }
        let partChars = min(ContextBudget.mapPartCap,
                            budget.pairedInputChars(fixedChars: NotePromptBuilder.mapSystemChars, replyFactor: ContextBudget.mapReplyFactor))
        guard partChars > 0 else {
            throw NoteGenerationError.failed("\(model)'s Context window (\(budget.tokens) tokens) is too small for notes.")
        }
        var current = lines
        for _ in 1...Self.maxMapLevels {
            current = try await map(current, maxChars: partChars, notesLanguage: notesLanguage)
            let prompt = reduce(current)
            // Warunek, na którym stoi cała gwarancja: reduce nigdy nie przekracza budżetu.
            if prompt.chars <= limit { return prompt }
        }
        throw NoteGenerationError.failed(
            "The transcript is too long for this model's Context window. Raise it in Settings or use a model with a longer context.")
    }

    /// Jeden poziom: podział na części, map każdej po kolei (limit czasu NA WYWOŁANIE). Błąd części = błąd całości („Part n of m failed").
    private func map(_ lines: [String], maxChars: Int, notesLanguage: LanguageCode?) async throws -> [String] {
        let parts = try TranscriptSplitter.parts(lines, maxChars: maxChars)
        let limits = mapLimits ?? ChatLimits.for(client.provider, call: .mapPart)
        var out: [String] = []
        for (i, part) in parts.enumerated() {
            try Task.checkCancellation()
            let prompt = NotePromptBuilder.mapPrompt(part: part, index: i + 1, count: parts.count, notesLanguage: notesLanguage)
            let replyTokens = ContextBudget.maxTokens(inputChars: prompt.user.count, replyFactor: ContextBudget.mapReplyFactor)
            do {
                let client = client, model = model
                let reply = try await withDeadline(limits.soft) {
                    try await client.chat(model: model, system: prompt.system, user: prompt.user, timeout: limits.transport,
                                          maxTokens: replyTokens, temperature: limits.temperature)
                }
                out += reply.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let why = ContextError.describe(model: model, error, provider: client.provider, transport: limits.transport, isLocal: true)
                throw NoteGenerationError.failed("Part \(i + 1) of \(parts.count) failed: \(why)")
            }
        }
        return out
    }
}
