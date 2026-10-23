import Foundation
import Testing
@testable import MeetNotesNotes

@Suite struct DictionaryTransferTests {
    private func term(_ d: UserDictionary, _ text: String) -> DictionaryTerm? {
        d.terms.first { UserDictionary.key($0.text) == UserDictionary.key(text) }
    }

    private func import1(_ vocab: String? = nil, _ repl: String? = nil, into d: UserDictionary = UserDictionary())
        -> (dictionary: UserDictionary, report: DictionaryImportReport) {
        DictionaryTransfer.importFiles(vocabulary: vocab, replacements: repl, into: d)
    }

    @Test func vocabularyTiersMapToPriorities() {
        let vocab = "# header\n# ====== T1 — core ======\n# --- group ---\nGenesys\n\n# ====== T3 — tail ======\nZowie\n"
        let r = import1(vocab)
        #expect(term(r.dictionary, "Genesys")?.priority == .high)
        #expect(term(r.dictionary, "Zowie")?.priority == .low)
        #expect(r.report.termsAdded == 2)
    }

    @Test func replacementsAddAliasesToTerms() {
        let repl = "# ---------- 1. Names ----------\nDżenesis\tGenesys\nGenezis\tGenesys\n"
        let r = import1("# ====== T1 — core ======\nGenesys\n", repl)
        #expect(term(r.dictionary, "Genesys")?.aliases == [DictionaryAlias("Dżenesis"), DictionaryAlias("Genezis")])
        #expect(term(r.dictionary, "Genesys")?.priority == .high)
        #expect(r.report.termsAdded == 1)
        #expect(r.report.aliasesAdded == 2)
        #expect(r.report.summary == "1 terms, 2 aliases, 0 risky left off, 0 conflicts, 0 rejected")
    }

    @Test func termsOnlyInReplacementsGetLowPriority() {
        let r = import1(nil, "Zołwi\tZowie\n")
        #expect(term(r.dictionary, "Zowie")?.priority == .low)
        #expect(r.report.termsAdded == 1)
    }

    @Test func riskySectionImportsAliasesDisabled() {
        let repl = "A\tGenesys\n#! ---------- 8. RISKY ----------\n#! comment\npu do\tPudo\n"
        let r = import1(nil, repl)
        #expect(term(r.dictionary, "Pudo")?.aliases == [DictionaryAlias("pu do", risky: true, enabled: false)])
        #expect(term(r.dictionary, "Genesys")?.aliases == [DictionaryAlias("A")])
        #expect(r.report.riskyLeftOff == 1)
    }

    @Test func aliasOwnedByAnotherTermIsReportedNotMoved() {
        let r = import1(nil, "x\tAlpha\nX\tBeta\n")
        #expect(term(r.dictionary, "Alpha")?.aliases == [DictionaryAlias("x")])
        #expect(term(r.dictionary, "Beta")?.aliases.isEmpty == true)
        #expect(r.report.conflicts == [.init(alias: "X", keptBy: "Alpha", skippedFor: "Beta")])
        // Konflikt trwały: ponowny import zgłasza go znowu, ale słownika nie rusza.
        let again = import1(nil, "x\tAlpha\nX\tBeta\n", into: r.dictionary)
        #expect(again.dictionary == r.dictionary)
        #expect(again.report == DictionaryImportReport(conflicts: r.report.conflicts))
    }

    @Test func aliasEqualToAnotherTermIsReportedNotInserted() {
        // R1: „genesis" jest Termem, więc nie może być Aliasem „Genesys" (Replacement byłby nieidempotentny).
        let r = import1("Genesys\nGenesis\n", "genesis\tGenesys\n")
        #expect(term(r.dictionary, "Genesys")?.aliases.isEmpty == true)
        #expect(r.report.conflicts == [.init(alias: "genesis", keptBy: "Genesis", skippedFor: "Genesys")])
        #expect(r.report.aliasesAdded == 0)
    }

    @Test func termsMergeIgnoringCaseAndKeepExistingPriority() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("genesys", priority: .normal))
        let r = import1("# ====== T1 — core ======\nGenesys\n", nil, into: d)
        #expect(r.dictionary.terms.count == 1)
        #expect(r.dictionary.terms.first?.priority == .normal)
        #expect(r.report == DictionaryImportReport())
    }

    @Test func importIsIdempotent() {
        let vocab = "# ====== T1 — core ======\nGenesys\n# ====== T3 — tail ======\nZowie\n"
        let repl = "Dżenesis\tGenesys\nx\tAlpha\n#! ---------- risky ----------\npu do\tPudo\n"
        let first = import1(vocab, repl)
        let second = import1(vocab, repl, into: first.dictionary)
        #expect(second.dictionary == first.dictionary)
        #expect(second.report == DictionaryImportReport())
        #expect(second.report.summary == "0 terms, 0 aliases, 0 risky left off, 0 conflicts, 0 rejected")
    }

    @Test func reimportKeepsUserEdits() throws {
        let vocab = "# ====== T1 — core ======\nPudo\n"
        let repl = "#! ---------- risky ----------\npu do\tPudo\n"
        var d = import1(vocab, repl).dictionary
        d.terms[0].priority = .low
        d.terms[0].aliases[0].enabled = true
        try d.upsert(d.terms[0])
        let again = import1(vocab, repl, into: d)
        #expect(again.dictionary == d)
        #expect(again.dictionary.terms[0].priority == .low)
        #expect(again.dictionary.terms[0].aliases == [DictionaryAlias("pu do", risky: true, enabled: true)])
        #expect(again.report == DictionaryImportReport())
    }

    private struct Shape: Equatable {
        var text: String
        var priority: TermPriority
        var aliases: [DictionaryAlias]
    }

    private func shape(_ d: UserDictionary) -> [Shape] {
        d.terms.map { Shape(text: $0.text, priority: $0.priority, aliases: $0.aliases.sorted { $0.text < $1.text }) }
            .sorted { $0.text < $1.text }
    }

    @Test func exportRoundTrips() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Alpha", priority: .high, aliases: [
            DictionaryAlias("a1"),
            DictionaryAlias("a2", risky: true, enabled: false),
            DictionaryAlias("a3", risky: true, enabled: true),
            DictionaryAlias("a4", risky: false, enabled: false),
        ]))
        try d.upsert(DictionaryTerm("Charlie", priority: .normal, aliases: [DictionaryAlias("c1")]))
        try d.upsert(DictionaryTerm("Bravo", priority: .low))
        let r = import1(DictionaryTransfer.exportVocabulary(d), DictionaryTransfer.exportReplacements(d))
        #expect(shape(r.dictionary) == shape(d))
        #expect(r.report.conflicts.isEmpty)
        // Plik dla innych narzędzi: zwykły `fraza<TAB>zapis`, a markery sekcji to komentarze.
        #expect(DictionaryTransfer.exportReplacements(d).contains("a1\tAlpha\n"))
        #expect(DictionaryTransfer.exportReplacements(d).contains("#! ---------- RISKY (disabled) ----------\na2\tAlpha\n"))
    }

    @Test func utf8BOMPreservesTierAndRiskySection() {
        let vocab = "\u{FEFF}# ====== T1 — core ======\nGenesys\n"
        let repl = "\u{FEFF}#! ---------- risky ----------\npu do\tPudo\n"
        let r = import1(vocab, repl)
        #expect(term(r.dictionary, "Genesys")?.priority == .high)
        #expect(term(r.dictionary, "\u{FEFF}# ====== T1 — core ======") == nil)
        #expect(term(r.dictionary, "Pudo")?.aliases == [DictionaryAlias("pu do", risky: true, enabled: false)])
        #expect(r.report.riskyLeftOff == 1)
    }

    @Test func multiFileImportResetsSectionsAndHandlesEachBOM() {
        let r = DictionaryTransfer.importFiles(
            vocabularies: ["# ====== T3 — tail ======\nZowie\n", "\u{FEFF}Genesys\n"],
            replacements: ["#! ---------- risky ----------\npu do\tPudo\n", "\u{FEFF}Dżenesis\tGenesys\n"],
            into: UserDictionary())
        // Tier i sekcja risky z pierwszego pliku nie przechodzą do drugiego; BOM drugiego pliku nie psuje pierwszej linii.
        #expect(term(r.dictionary, "Zowie")?.priority == .low)
        #expect(term(r.dictionary, "Genesys")?.priority == .normal)
        #expect(term(r.dictionary, "Pudo")?.aliases == [DictionaryAlias("pu do", risky: true, enabled: false)])
        #expect(term(r.dictionary, "Genesys")?.aliases == [DictionaryAlias("Dżenesis")])
        #expect(r.report.riskyLeftOff == 1)
    }

    @Test func riskySectionEndsAtNextHeader() {
        let repl = "#! ---------- risky ----------\n#! note\npu do\tPudo\n# plain comment\n# ---------- 9. Names ----------\nDżenesis\tGenesys\n"
        let r = import1(nil, repl)
        #expect(term(r.dictionary, "Pudo")?.aliases == [DictionaryAlias("pu do", risky: true, enabled: false)])
        #expect(term(r.dictionary, "Genesys")?.aliases == [DictionaryAlias("Dżenesis")])
    }

    @Test func exportRoundTripsCommentPrefixes() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("C#", aliases: [DictionaryAlias("si szarp"), DictionaryAlias("F#")]))
        #expect(throws: DictionaryError.invalidCharacters("#!literal")) {
            try d.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("#!literal")]))
        }
        #expect(throws: DictionaryError.invalidCharacters("#tag")) { try d.upsert(DictionaryTerm("#tag")) }
        let r = import1(DictionaryTransfer.exportVocabulary(d), DictionaryTransfer.exportReplacements(d))
        #expect(shape(r.dictionary) == shape(d))
        #expect(r.report.rejected == 0)
    }

    @Test func exportDoesNotSilentlyFlattenDistinctTexts() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("a b"))
        #expect(throws: DictionaryError.invalidCharacters("a\tb")) { try d.upsert(DictionaryTerm("a\tb")) }
        #expect(throws: DictionaryError.invalidCharacters("x\u{2028}y")) {
            try d.upsert(DictionaryTerm("Ok", aliases: [DictionaryAlias("x\u{2028}y")]))
        }
        #expect(d.terms.map(\.text) == ["a b"])
        // Import też nie gubi ich po cichu: raport liczy odrzucone (tabulator w linii vocab, `#` jako cel).
        let r = import1("good\nbad\tterm\n", "x\t#target\n")
        #expect(r.dictionary.terms.map(\.text) == ["good"])
        #expect(r.report.rejected == 2)
        #expect(r.report.summary == "1 terms, 0 aliases, 0 risky left off, 0 conflicts, 2 rejected")
    }
}
