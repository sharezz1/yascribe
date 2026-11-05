import Foundation
import Testing
@testable import YascribeNotes

/// TASK-85: Aliasy z odmianą (`DictionaryAlias.inflects`): rdzeń + końcówka zachowana w wyniku.
@Suite struct InflectionTests {
    private func infl(_ text: String) -> DictionaryAlias { DictionaryAlias(text, inflects: true) }
    private func rules(_ terms: DictionaryTerm...) -> ReplacementRules { ReplacementRules(UserDictionary(terms: terms)) }
    private func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }

    @Test func keepsTheEndingAndReplacesTheStem() {
        let r = rules(DictionaryTerm("Genesys", aliases: [infl("Genesis")]))
        #expect(r.apply(to: "Genesis Genesisa w Genesisie z Genesisem") == "Genesys Genesysa w Genesysie z Genesysem")
        #expect(r.apply(to: "GENESISA i genesisie") == "GenesysA i Genesysie")
        #expect(r.apply(to: "Genesis-ie") == "Genesys-ie")
    }

    @Test func endingMustBeLettersAndWordMustEnd() {
        let r = rules(DictionaryTerm("Genesys", aliases: [infl("Genesis")]))
        #expect(r.apply(to: "Genesis2 Genesis_x") == "Genesis2 Genesys_x")
        #expect(r.apply(to: "xGenesisa") == "xGenesisa")
        #expect(r.apply(to: "Genesis, Genesisa.") == "Genesys, Genesysa.")
    }

    @Test func multiWordStemKeepsEndingOnLastWord() {
        let r = rules(DictionaryTerm("OD", aliases: [infl("Ola Dom")]))
        #expect(r.apply(to: "u Ola Domu") == "u ODu")
    }

    @Test func plainAliasesBehaveAsBefore() {
        let r = rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")]), DictionaryTerm("Genesys", aliases: [infl("Genesis")]))
        #expect(r.apply(to: "Rokm Rokmem") == "Nimbu Rokmem")
    }

    @Test func plainAliasWinsOverInflectingStem() {
        let r = rules(DictionaryTerm("Genesys", aliases: [infl("Genesis")]), DictionaryTerm("Poprawny", aliases: [DictionaryAlias("Genesisa")]))
        #expect(r.apply(to: "Genesisa Genesisie") == "Poprawny Genesysie")
    }

    @Test func stemThatIsPrefixOfItsTermIsIdempotent() throws {
        let r = try upserted(DictionaryTerm("OpenTofu", aliases: [infl("OpenTof")]))
        #expect(r.apply(to: "OpenTof") == "OpenTofu")
        #expect(r.apply(to: "opentofem") == "OpenTofuem")
        #expect(r.apply(to: "OpenTofu OpenTofuem") == "OpenTofu OpenTofuem")
        for x in ["OpenTofem", "OpenTofu", "opentof", "OpenTofuem x"] {
            let once = r.apply(to: x)
            #expect(scalars(r.apply(to: once)) == scalars(once), "\(x)")
        }
    }

    @Test func multiWordTermTailIsProtected() throws {
        let r = try upserted(DictionaryTerm("Projekt Genesys", aliases: [infl("Genes")]))
        #expect(r.apply(to: "Genesx") == "Projekt Genesysx")
        #expect(r.apply(to: "Projekt Genesysx") == "Projekt Genesysx")
    }

    /// ﬃ składa się do „ffi” w ICU, więc rdzeń „OFFIC” jest dłuższy znakowo niż tożsamość „Oﬃce”: kolejność nie może zależeć od długości.
    @Test func ligatureDoesNotBreakPriorityOrIdempotence() throws {
        let r = try upserted(DictionaryTerm("O\u{FB03}ce", aliases: [infl("OFFIC")]), DictionaryTerm("Z", aliases: [DictionaryAlias("OFFICEA")]))
        let once = r.apply(to: "OFFICem")
        #expect(once == "O\u{FB03}ceem")
        #expect(scalars(r.apply(to: once)) == scalars(once))
        #expect(r.apply(to: "OFFICEA") == "Z")
    }

    @Test func aliasEqualToItsTermIsKeptWhenItInflects() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Genesys", aliases: [DictionaryAlias("Genesys", inflects: true)]))
        #expect(d.terms[0].aliases.count == 1)
        #expect(ReplacementRules(d).apply(to: "genesysa") == "Genesysa")
        try d.upsert(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Nimbu")]))
        #expect(d.terms[1].aliases.isEmpty)
    }

    @Test func upsertRejectsBadStems() {
        var d = UserDictionary()
        #expect(throws: DictionaryError.invalidInflection("ab")) { try d.upsert(DictionaryTerm("Abc", aliases: [infl("ab")])) }
        #expect(throws: DictionaryError.invalidInflection("SAS-")) { try d.upsert(DictionaryTerm("SaaS", aliases: [infl("SAS-")])) }
        #expect(throws: Never.self) { try d.upsert(DictionaryTerm("Abc", aliases: [DictionaryAlias("ab")])) }
    }

    @Test func upsertRejectsStemLongerThanATermTail() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("def"))
        #expect(throws: DictionaryError.inflectionAmbiguous(alias: "defx", term: "def")) {
            try d.upsert(DictionaryTerm("abc", aliases: [infl("defx")]))
        }
        var e = UserDictionary()
        try e.upsert(DictionaryTerm("abc", aliases: [infl("defx")]))
        #expect(throws: DictionaryError.inflectionAmbiguous(alias: "defx", term: "def")) { try e.upsert(DictionaryTerm("def")) }
        try e.upsert(DictionaryTerm("Foo Zdefx")) // ogon „Zdefx” nie jest prefiksem rdzenia
        #expect(throws: DictionaryError.inflectionAmbiguous(alias: "defx", term: "Foo def")) { try e.upsert(DictionaryTerm("Foo def")) }
    }

    @Test func ambiguousStemFallsBackToWholeWord() {
        let r = rules(DictionaryTerm("def"), DictionaryTerm("abc", aliases: [infl("defx")]))
        #expect(r.apply(to: "defxy") == "defxy")
        #expect(r.apply(to: "defx") == "abc")
        let short = rules(DictionaryTerm("Abc", aliases: [infl("ab")]))
        #expect(short.apply(to: "abx ab") == "abx Abc")
    }

    @Test func codableIsBackwardCompatible() throws {
        let old = #"{"text":"Rokm","risky":false,"enabled":true}"#.data(using: .utf8)!
        let a = try JSONDecoder().decode(DictionaryAlias.self, from: old)
        #expect(a == DictionaryAlias("Rokm"))
        #expect(!a.inflecting)
        let plain = String(decoding: try JSONEncoder().encode(DictionaryAlias("Rokm")), as: UTF8.self)
        #expect(!plain.contains("inflects"))
        let back = try JSONDecoder().decode(DictionaryAlias.self, from: JSONEncoder().encode(infl("Genesis")))
        #expect(back.inflecting)
    }

    @Test func preFilterNeverChangesInflectingResults() throws {
        func t(_ text: String, _ aliases: DictionaryAlias...) -> DictionaryTerm { DictionaryTerm(text, aliases: aliases) }
        let dictionaries: [[DictionaryTerm]] = [
            [t("Genesys", infl("Genesis")), t("Nimbu", DictionaryAlias("Rokm"))],
            [t("OpenTofu", infl("OpenTof"))],
            [t("OD", infl("Ola Dom"))],
            [t("Oﬃce", infl("OFFIC"))],
            [t("Y", infl("XXJ"))],
            [t("Straße", infl("Strasse"))],
            [t("Hash", infl("#tag")), t("Genesys", infl("Genesis"))],
        ]
        let texts = ["", "Genesis Genesisa", "GENESISIE", "genesis2", "Rokm Rokmem", "OpenTofem opentof", "OpenTofuem", "u Ola Domu", "Ola Dom",
                     "OFFICem", "XXJ\u{030C}", "XXJ", "XXJ\u{030C}a", "Strassen STRASSE", "Straßen", "#taga", "nic tu nie ma", "Genesis-ie", "xGenesisa"]
        for terms in dictionaries {
            let r = ReplacementRules(UserDictionary(terms: terms))
            for x in texts {
                #expect(scalars(r.apply(to: x)) == scalars(r.apply(to: x, preFilter: false)), "\(terms.map(\.text)) \(x)")
            }
        }
        #expect(ReplacementRules(UserDictionary(terms: dictionaries[4])).apply(to: "XXJ\u{030C}") == "Y\u{030C}")
    }

    @Test func preFilterSkipsRegexForInflectingWhenNoCandidate() {
        let r = rules(DictionaryTerm("Genesys", aliases: [infl("Genesis")]))
        let runs = ReplacementRules.RegexRuns()
        ReplacementRules.$regexRuns.withValue(runs) { #expect(r.apply(to: "nic tu nie ma Genes") == "nic tu nie ma Genes") }
        #expect(runs.count == 0)
        ReplacementRules.$regexRuns.withValue(runs) { #expect(r.apply(to: "w Genesisie") == "w Genesysie") }
        #expect(runs.count == 2)
    }

    @Test func parseTypedAlias() {
        #expect(DictionaryAlias.parseTyped("Genesis*") == (text: "Genesis", inflects: true))
        #expect(DictionaryAlias.parseTyped("  Genesis * ") == (text: "Genesis", inflects: true))
        #expect(DictionaryAlias.parseTyped("Genesis") == (text: "Genesis", inflects: false))
        #expect(DictionaryAlias.parseTyped("foo**") == (text: "foo*", inflects: false))
        #expect(DictionaryAlias.parseTyped("*") == (text: "*", inflects: false))
    }

    @Test func tsvImportExportRoundTrips() throws {
        let r = DictionaryTransfer.importFiles(vocabulary: nil, replacements: "Genesis*\tGenesys\nRokm\tNimbu\nfoo**\tNimbu\nab*\tShort\n", into: UserDictionary())
        let g = try #require(r.dictionary.terms.first { $0.text == "Genesys" })
        #expect(g.aliases == [infl("Genesis")])
        #expect(r.report.rejected == 1)
        let n = try #require(r.dictionary.terms.first { $0.text == "Nimbu" })
        #expect(n.aliases == [DictionaryAlias("Rokm"), DictionaryAlias("foo*")])
        let out = DictionaryTransfer.exportReplacements(r.dictionary)
        #expect(out.contains("Genesis*\tGenesys\n"))
        #expect(out.contains("foo**\tNimbu\n"))
        let again = DictionaryTransfer.importFiles(vocabulary: DictionaryTransfer.exportVocabulary(r.dictionary), replacements: out, into: UserDictionary())
        #expect(again.dictionary.terms.map(\.aliases) == r.dictionary.terms.map(\.aliases))
    }

    @Test func tsvKeepsInflectingAliasEqualToTerm() throws {
        let r = DictionaryTransfer.importFiles(vocabulary: nil, replacements: "Genesys*\tGenesys\n", into: UserDictionary())
        #expect(r.dictionary.terms[0].aliases == [infl("Genesys")])
        #expect(r.report.aliasesAdded == 1)
    }

    @Test func tsvReportsAmbiguousStemAsConflict() {
        let r = DictionaryTransfer.importFiles(vocabulary: "def\n", replacements: "defx*\tabc\n", into: UserDictionary())
        #expect(r.report.conflicts.count == 1)
        #expect(r.report.aliasesAdded == 0)
    }

    @Test func presentationOfInflectionErrors() {
        let a = DictionaryEdit.presentation(of: .invalidInflection("ab"), draftTerm: "Abc")
        #expect(a.field == .alias)
        let b = DictionaryEdit.presentation(of: .inflectionAmbiguous(alias: "defx", term: "def"), draftTerm: "abc")
        #expect(b.field == .alias)
        let c = DictionaryEdit.presentation(of: .inflectionAmbiguous(alias: "defx", term: "def"), draftTerm: "def")
        #expect(c.field == .term)
    }

    private func upserted(_ terms: DictionaryTerm...) throws -> ReplacementRules {
        var d = UserDictionary()
        for t in terms { try d.upsert(t) }
        return ReplacementRules(d)
    }
}
