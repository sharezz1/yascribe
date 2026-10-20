import Foundation
import MeetNotesProviders
import MeetNotesTranscription

public enum NoteGenerationError: Error, Equatable {
    case nothingToSummarize
    case failed(String)
}

/// „Generate notes": prompt → model → tytuł i treść → zapis. Nic nie jest zapisywane, gdy model zawiedzie.
public struct NoteGenerator: Sendable {
    public let client: OpenAICompatibleClient
    public let model: String
    /// Całkowity limit czasu odpowiedzi modelu (sekundy); po nim „Generate notes" kończy się błędem z nazwą modelu.
    public let timeout: Double

    /// Limit transportowy żądania (`ChatLimits.transport`) i `max_tokens` (tylko lokalnie; `nil` = bez pola).
    public let chatTimeout: Double
    public let maxTokens: Int?

    public init(client: OpenAICompatibleClient, model: String, timeout: Double = 180, chatTimeout: Double = 120, maxTokens: Int? = nil) {
        self.client = client
        self.model = model
        self.timeout = timeout
        self.chatTimeout = chatTimeout
        self.maxTokens = maxTokens
    }

    public func generate(session: URL, template: Template, transcript: Transcript, context: String,
                         notesLanguage: LanguageCode?, now: Date = Date(),
                         onProblem: @Sendable (String) -> Void = { _ in }) async throws -> NoteSummary {
        let store = NotesStore(session: session)
        guard let prompt = NotePromptBuilder.build(template: template, transcript: transcript, myNotes: store.readMyNotes(),
                                                   context: context, notesLanguage: notesLanguage) else {
            throw NoteGenerationError.nothingToSummarize
        }
        let reply: String
        do {
            let client = client, model = model, chatTimeout = chatTimeout, maxTokens = maxTokens
            reply = try await withDeadline(timeout) {
                try await client.chat(model: model, system: prompt.system, user: prompt.user, timeout: chatTimeout, maxTokens: maxTokens)
            }
        } catch {
            throw NoteGenerationError.failed(ContextError.describe(model: model, error, isLocal: client.provider.isLocal))
        }
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
}
