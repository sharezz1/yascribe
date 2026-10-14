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

    public init(client: OpenAICompatibleClient, model: String) {
        self.client = client
        self.model = model
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
            reply = try await client.chat(model: model, system: prompt.system, user: prompt.user)
        } catch {
            throw NoteGenerationError.failed(ContextError.describe(model: model, error))
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
