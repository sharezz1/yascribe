import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

// TASK-96: domyślne polecenia nie mogą się zmienić ani o bajt po wydzieleniu edytowalnej podstawy.
// Literały zrzucone z kodu sprzed refaktoru; gdy świadomie zmieniamy brzmienie domyślnych (rebase na `korekta-historia`),
// aktualizujemy je razem z `defaultBody`.

private func corrector(fillers: [String] = [], prompt: String? = nil) -> Corrector {
    Corrector(client: chatClient(ChatStub { $0.user }), assignment: RoleAssignment(providerID: testProvider.id, model: "m", prompt: prompt),
              fillerWords: fillers)
}

@Test func defaultCorrectionSystemIsUnchanged() {
    let core = "You correct speech-to-text transcripts line by line. Fix recognition errors, punctuation and casing. "
        + "Do not add, remove, merge or reorder content, and do not summarize or translate.\n"
        + "The input is numbered lines like \"[12] text\". Reply with exactly the same numbers, one corrected line per "
        + "input line, in the same order, and nothing else."
    #expect(corrector().system(language: nil) == core)
    #expect(corrector(fillers: ["yyy", "eee"], prompt: "keep names").system(language: .polish) == core
        + "\nException: remove filler sounds and hesitations (for example: yyy, eee). Keep every word that carries meaning."
        + "\nThe transcript language is Polish.\nExtra instructions from the user: keep names")
}

@Test func defaultSummarySystemIsUnchanged() {
    func expected(language: String, condensed: String) -> String {
        """
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
        \(language) Keep the section titles under Structure exactly as written (do not translate them); write "(owner unclear)" in the notes language.\(condensed)

        Structure:
        \(Template.standard.promptText)
        """
    }
    let lines = ["[0:01] Them: hej"]
    let polish = NotePromptBuilder.prompt(template: .standard, lines: lines, myNotes: "", context: "", notesLanguage: .polish)
    #expect(polish.system == expected(language: "Write the notes in Polish.", condensed: ""))
    let auto = NotePromptBuilder.prompt(template: .standard, lines: lines, myNotes: "", context: "", notesLanguage: nil, condensed: true)
    #expect(auto.system == expected(language: "Write the notes in the language that predominates in the transcript.",
                                    condensed: "\n" + NotePromptBuilder.condensedSentence))
}

@Test func customCorrectionBodyKeepsTheFormatRuleAfterIt() {
    var c = corrector()
    c.body = "  Only fix commas.\n"
    let s = c.system(language: nil)
    #expect(s.hasPrefix("Only fix commas.\nThe input is numbered lines like \"[12] text\"."))
    #expect(!s.contains("You correct speech-to-text"))
}

@Test func customSummaryBodyKeepsOutputRulesLanguageAndStructureAfterIt() throws {
    let p = NotePromptBuilder.prompt(template: .standard, lines: ["[0:01] Them: hej"], myNotes: "", context: "", notesLanguage: .polish,
                                     rulesBody: "- Write like a pirate.")
    let s = p.system
    let body = try #require(s.range(of: "- Write like a pirate.")), title = try #require(s.range(of: "# <short descriptive title>"))
    #expect(body.upperBound <= title.lowerBound) // stałe reguły po podstawie: mają ostatnie słowo
    #expect(s.contains("\n- Write like a pirate.\n- Output Markdown. The FIRST line must be the title"))
    #expect(s.contains(NoteTitle.rule) && s.contains("Write the notes in Polish.") && s.contains("\n\nStructure:\n"))
    #expect(s.contains("\"Me\" is the user's microphone") && !s.contains("Be concrete"))
}
