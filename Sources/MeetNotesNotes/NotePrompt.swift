import Foundation
import MeetNotesProviders
import MeetNotesTranscription

public struct NotePrompt: Equatable, Sendable {
    public var system: String
    public var user: String
    public init(system: String, user: String) { self.system = system; self.user = user }
}

/// Czysta funkcja: szablon + transkrypt + My notes + kontekst → prompt. `nil`, gdy nie ma czego streszczać
/// (pusta albo w całości wykluczona transkrypcja) — wtedy model nie jest wołany (Review Focus #1).
public enum NotePromptBuilder {
    public static func build(template: Template, transcript: Transcript, myNotes: String, context: String,
                             notesLanguage: LanguageCode?) -> NotePrompt? {
        let lines = transcriptLines(transcript)
        guard !lines.isEmpty else { return nil }
        let language = notesLanguage.map { "Write the notes in \($0.englishName)." }
            ?? "Write the notes in the language that predominates in the transcript."
        let system = """
        You write meeting notes from the transcript of a two-channel recording. "Me" is the user's microphone, "Them" is \
        everyone else on the call.

        Rules:
        - Use only what is in the transcript, the user's own notes and the user's context. Never invent facts, names, \
        numbers or decisions.
        - If the transcript is inconsistent, fragmentary or garbled, say so plainly in the notes (for example: "The \
        transcript is too fragmented to extract reliable notes") and list only what is clearly supported. Do not guess.
        - Be concrete: keep numbers, names, dates and the options that were discussed. No generic filler.
        - The user's own notes are priority: weave them into the result.
        - Output Markdown. The FIRST line must be the title, written as "# <short descriptive title>". Nothing may \
        come before it.
        \(language)

        Structure:
        \(template.instructions)
        """
        let user = """
        Context from the user:
        \(orNone(context))

        The user's own notes:
        \(orNone(myNotes))

        Transcript:
        \(lines.joined(separator: "\n"))
        """
        return NotePrompt(system: system, user: user)
    }

    /// `[m:ss] Me|Them: tekst` — bez wypowiedzi pustych i oznaczonych strażnikiem języka.
    public static func transcriptLines(_ t: Transcript) -> [String] {
        t.utterances
            .filter { !$0.excludedFromNotes && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
            .map { "[\(clock($0.start))] \($0.speaker == .me ? "Me" : "Them"): \($0.text)" }
    }

    static func clock(_ seconds: Double) -> String {
        let i = Int(seconds)
        return i >= 3600 ? String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60) : String(format: "%d:%02d", i / 60, i % 60)
    }

    private static func orNone(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "(none)" : t
    }
}
