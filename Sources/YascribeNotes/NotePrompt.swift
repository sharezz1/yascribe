import Foundation
import YascribeProviders
import YascribeTranscription

public struct NotePrompt: Equatable, Sendable {
    public var system: String
    public var user: String
    public init(system: String, user: String) { self.system = system; self.user = user }
    /// Znaki całego promptu — to, co liczy `ContextBudget.promptChars`.
    public var chars: Int { system.count + user.count }
}

/// Czysta funkcja: szablon + transkrypt + My notes + kontekst → prompt. `nil`, gdy nie ma czego streszczać
/// (pusta albo w całości wykluczona transkrypcja) — wtedy model nie jest wołany (Review Focus #1).
public enum NotePromptBuilder {
    /// `condensed`: wejście to wynik etapu map (map-reduce), nie pełny zapis — jedno dopisane zdanie (spec fazy 2.0 §11.4).
    public static func build(template: Template, transcript: Transcript, myNotes: String, context: String,
                             notesLanguage: LanguageCode?, condensed: Bool = false,
                             vocabulary: PromptVocabulary? = nil) -> NotePrompt? {
        let lines = transcriptLines(transcript)
        guard !lines.isEmpty else { return nil }
        return prompt(template: template, lines: lines, myNotes: myNotes, context: context, notesLanguage: notesLanguage,
                      condensed: condensed, vocabulary: vocabulary)
    }

    /// Ten sam prompt z gotowych linii `[m:ss] Me|Them: …` (reduce dostaje wyjście mapy, nie `Transcript`); bez bramki „pusto".
    /// `vocabulary` (F21): linie Termów i uczestników w `system`, po regułach i zdaniu o języku, przed „Structure"; w `user` ich nie ma.
    static func prompt(template: Template, lines: [String], myNotes: String, context: String, notesLanguage: LanguageCode?,
                       condensed: Bool = false, vocabulary: PromptVocabulary? = nil) -> NotePrompt {
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
        come before it. \(NoteTitle.rule)
        \(language)\(condensed ? "\n\(condensedSentence)" : "")\(vocabulary?.promptLines.map { "\n\($0)" } ?? "")

        Structure:
        \(template.promptText)
        """
        // Pole kontekstu bywa wstępnie wypełnione My notes: to samo nie idzie do modelu dwa razy (przegląd T13).
        let sameAsNotes = !myNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && context.trimmingCharacters(in: .whitespacesAndNewlines) == myNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = """
        Context from the user:
        \(orNone(sameAsNotes ? "" : context))

        The user's own notes:
        \(orNone(myNotes))

        Transcript:
        \(lines.joined(separator: "\n"))
        """
        return NotePrompt(system: system, user: user)
    }

    static let condensedSentence = "The transcript below is a condensed version of the full recording."

    /// Etap map: skondensuj część transkryptu do TEGO SAMEGO formatu linii. Bez My notes, kontekstu i szablonu — one trafiają tylko
    /// do reduce. Cel długości (S2 §6a: bez niego wyjście 0,26–1,0 wejścia, ministral do 2,0). `notesLanguage` nie jest użyty:
    /// części zostają w języku wypowiedzi, język notatki ustawia dopiero reduce.
    /// `vocabulary` (F21): te same linie co w prompcie notatki, raz w `system` każdego wywołania mapy (każde jest osobnym żądaniem).
    public static func mapPrompt(part: [String], index: Int, count: Int, notesLanguage: LanguageCode?,
                                 vocabulary: PromptVocabulary? = nil) -> NotePrompt {
        let system = """
        You condense part \(index) of \(count) of a meeting transcript. Every line has the form "[m:ss] Me: text" or \
        "[m:ss] Them: text" (after the first hour "[h:mm:ss] Me: text"); "Me" is the user's microphone, "Them" is \
        everyone else on the call.

        Rules:
        - Reply with condensed lines in the same format: each line starts with its [m:ss] or [h:mm:ss] and its speaker, in \
        the same order. You may merge consecutive lines of the same speaker into one, keeping the first timestamp.
        - Keep names, numbers, dates, decisions and tasks exactly as spoken. Drop filler and repetition.
        - Do not interpret, do not add anything that is not in the input, do not translate.
        - Keep the result to at most 40% of the input length.
        - Output only the lines, nothing else.
        """ + (vocabulary?.promptLines.map { "\n\n\($0)" } ?? "")
        return NotePrompt(system: system, user: part.joined(separator: "\n"))
    }

    /// Długość promptu systemowego mapy z zapasem na numer części — do liczenia `pairedInputChars` przed podziałem. Liczona z prawdziwego
    /// `mapPrompt`: `DictionaryPrompt.maxChars` nie obejmuje stałych nagłówków linii, więc koszt linii słownika trzeba mierzyć, nie szacować.
    static func mapSystemChars(vocabulary: PromptVocabulary?) -> Int {
        mapPrompt(part: [], index: 99_999, count: 99_999, notesLanguage: nil, vocabulary: vocabulary).system.count
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
