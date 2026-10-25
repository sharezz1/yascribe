import Foundation

/// Wynik importu (F21 D9): co dodano i co pominięto, żeby żadna decyzja nie zapadła po cichu. Zero we wszystkich polach = nic się nie zmieniło.
public struct DictionaryImportReport: Equatable, Sendable {
    public var termsAdded: Int
    public var aliasesAdded: Int
    /// Nowe Aliasy risky, które weszły wyłączone (zawierają się też w `aliasesAdded`).
    public var riskyLeftOff: Int
    public var conflicts: [Conflict]
    /// Pozycje z zarezerwowanymi znakami (zaczynają się od `#` albo mają tabulator / koniec linii w środku): `upsert` je odrzuca.
    public var rejected: Int

    public struct Conflict: Equatable, Sendable {
        /// Alias z pliku, który nie wszedł.
        public var alias: String
        /// Term, który go już ma (albo którego tekst jest równy Aliasowi, albo który zajmuje ten tekst jako Alias).
        public var keptBy: String
        /// Term, któremu plik chciał dać ten Alias.
        public var skippedFor: String

        public init(alias: String, keptBy: String, skippedFor: String) {
            self.alias = alias
            self.keptBy = keptBy
            self.skippedFor = skippedFor
        }
    }

    public init(termsAdded: Int = 0, aliasesAdded: Int = 0, riskyLeftOff: Int = 0, conflicts: [Conflict] = [], rejected: Int = 0) {
        self.termsAdded = termsAdded
        self.aliasesAdded = aliasesAdded
        self.riskyLeftOff = riskyLeftOff
        self.conflicts = conflicts
        self.rejected = rejected
    }

    public var summary: String {
        "\(termsAdded) terms, \(aliasesAdded) aliases, \(riskyLeftOff) risky left off, \(conflicts.count) conflicts, \(rejected) rejected"
    }
}

/// Import i eksport słownika w formatach `vocab_core.txt` (jeden Term w linii, tiery T1/T2/T3) i `replacements.tsv` (`fraza<TAB>zapis`).
/// Import przechodzi przez `UserDictionary.upsert`, więc inwarianty słownika (unikalność Aliasów, Alias ≠ Term) obowiązują tak jak przy ręcznej edycji.
public enum DictionaryTransfer {
    private enum Mode {
        case normal, riskyOff, riskyOn, disabled

        var flags: (risky: Bool, enabled: Bool) {
            switch self {
            case .normal: (false, true)
            case .riskyOff: (true, false)
            case .riskyOn: (true, true)
            case .disabled: (false, false)
            }
        }
    }

    private struct Row {
        var phrase: String
        var target: String
        var mode: Mode
        /// Niepusta trzecia (lub dalsza) kolumna: plik nie jest w formacie `fraza<TAB>zapis`, więc wiersz idzie do `rejected` (R15b).
        var extraColumns = false
    }

    public static func importFiles(vocabulary: String?, replacements: String?, into d: UserDictionary)
        -> (dictionary: UserDictionary, report: DictionaryImportReport) {
        importFiles(vocabularies: vocabulary.map { [$0] } ?? [], replacements: replacements.map { [$0] } ?? [], into: d)
    }

    /// Wiele plików naraz (R22): każdy parsowany osobno (stan sekcji `#!`/tier i BOM nie przechodzą z pliku do pliku), potem jeden przebieg
    /// scalania jak dla pojedynczych plików, więc wynik i raport nie zależą od tego, jak pliki podzielono.
    public static func importFiles(vocabularies: [String], replacements: [String], into d: UserDictionary)
        -> (dictionary: UserDictionary, report: DictionaryImportReport) {
        var dict = d
        var report = DictionaryImportReport()
        let vocab = vocabularies.flatMap(parseVocabulary)
        let parsed = replacements.flatMap(parseReplacements)
        let rows = parsed.filter { !$0.extraColumns }
        report.rejected += parsed.count - rows.count

        // Przebieg 1: wszystkie Termy (najpierw z vocab, potem cele spoza niego jako Low), żeby wynik nie zależał od kolejności linii.
        // Cele z replacements, które odrzuca `isReserved`, liczy przebieg 2 (raz na wiersz), z vocab liczymy tu.
        let candidates = vocab.map { ($0.0, $0.1, true) } + rows.map { ($0.target, TermPriority.low, false) }
        for (text, priority, fromVocab) in candidates {
            if UserDictionary.isReserved(text) {
                if fromVocab { report.rejected += 1 }
                continue
            }
            let k = UserDictionary.key(text)
            if dict.terms.contains(where: { UserDictionary.key($0.text) == k }) { continue }
            do {
                try dict.upsert(DictionaryTerm(text, priority: priority))
                report.termsAdded += 1
            } catch {
                // Tekst Terma jest już cudzym Aliasem: nie dodajemy, a dalsze linie tego celu zgłosi przebieg 2.
                if let owner = dict.owner(ofAlias: text) {
                    report.conflicts.append(.init(alias: text, keptBy: owner.text, skippedFor: text))
                }
            }
        }

        // Przebieg 2: Aliasy. Istniejący Alias tego samego Terma zostaje nietknięty (flagi użytkownika wygrywają).
        for row in rows {
            if UserDictionary.isReserved(row.phrase) || UserDictionary.isReserved(row.target) {
                report.rejected += 1
                continue
            }
            let k = UserDictionary.key(row.target)
            guard var term = dict.terms.first(where: { UserDictionary.key($0.text) == k }) else {
                report.conflicts.append(.init(alias: row.phrase, keptBy: dict.owner(ofAlias: row.target)?.text ?? row.target, skippedFor: row.target))
                continue
            }
            let ak = UserDictionary.key(row.phrase)
            if term.aliases.contains(where: { UserDictionary.key($0.text) == ak }) { continue }
            if row.phrase == term.text { continue } // upsert i tak by go zgubił; to nie konflikt
            if let other = dict.terms.first(where: { $0.id != term.id && UserDictionary.key($0.text) == ak }) {
                report.conflicts.append(.init(alias: row.phrase, keptBy: other.text, skippedFor: term.text))
                continue
            }
            if let owner = dict.owner(ofAlias: row.phrase, excluding: term.id) {
                report.conflicts.append(.init(alias: row.phrase, keptBy: owner.text, skippedFor: term.text))
                continue
            }
            let flags = row.mode.flags
            term.aliases.append(DictionaryAlias(row.phrase, risky: flags.risky, enabled: flags.enabled))
            do {
                try dict.upsert(term)
                report.aliasesAdded += 1
                if flags.risky && !flags.enabled { report.riskyLeftOff += 1 }
            } catch DictionaryError.invalidCharacters {
                report.rejected += 1
            } catch {
                report.conflicts.append(.init(alias: row.phrase, keptBy: "?", skippedFor: term.text))
            }
        }
        return (dict, report)
    }

    // MARK: Parsery

    /// Pojedynczy BOM na początku pliku (Excel, Notatnik) nie jest tekstem: inaczej gubi pierwszy nagłówek.
    private static func lines(_ text: String) -> [String] {
        var text = text
        if text.unicodeScalars.first == "\u{FEFF}" { text = String(text.unicodeScalars.dropFirst()) }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Nagłówek `# ==` z `T1`/`T2`/`T3` ustawia priorytet kolejnych linii; przed pierwszym Normal.
    private static func parseVocabulary(_ text: String) -> [(String, TermPriority)] {
        var priority = TermPriority.normal
        var out: [(String, TermPriority)] = []
        for line in lines(text) {
            if line.hasPrefix("# ==") {
                if line.contains("T1") { priority = .high } else if line.contains("T2") { priority = .normal } else if line.contains("T3") { priority = .low }
            } else if !line.isEmpty, !line.hasPrefix("#") {
                out.append((UserDictionary.clean(line), priority))
            }
        }
        return out
    }

    /// Markery sekcji `#!` (risky, wyłączone), `#+` (risky, włączone), `#-` (zwykłe, wyłączone) trwają do następnego nagłówka `# ---`.
    /// Linia bez tabulatora jest pomijana (nie ma jej jak zgłosić w raporcie).
    private static func parseReplacements(_ text: String) -> [Row] {
        var mode = Mode.normal
        var out: [Row] = []
        for line in lines(text) {
            if line.hasPrefix("#!") { mode = .riskyOff } else if line.hasPrefix("#+") { mode = .riskyOn } else if line.hasPrefix("#-") { mode = .disabled } else if line.hasPrefix("# ---") { mode = .normal } else if line.hasPrefix("#") || line.isEmpty { continue } else {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { continue }
                let phrase = UserDictionary.clean(parts[0]), target = UserDictionary.clean(parts[1])
                let extra = parts.dropFirst(2).contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if !phrase.isEmpty, !target.isEmpty { out.append(Row(phrase: phrase, target: target, mode: mode, extraColumns: extra)) }
            }
        }
        return out
    }

    // MARK: Eksport

    public static func exportReplacements(_ d: UserDictionary) -> String {
        let sections: [(header: String, risky: Bool, enabled: Bool)] = [
            ("# ---------- Replacements ----------", false, true),
            ("#! ---------- RISKY (disabled) ----------", true, false),
            ("#+ ---------- RISKY (enabled) ----------", true, true),
            ("#- ---------- DISABLED ----------", false, false),
        ]
        var out: [String] = []
        for s in sections {
            var body: [String] = []
            for t in d.terms {
                for a in t.aliases where a.risky == s.risky && a.enabled == s.enabled { body.append("\(a.text)\t\(t.text)") }
            }
            if !body.isEmpty { out += [s.header] + body + [""] }
        }
        return out.joined(separator: "\n")
    }

    public static func exportVocabulary(_ d: UserDictionary) -> String {
        let tiers: [(TermPriority, String)] = [
            (.high, "# ====== T1 — high ======"),
            (.normal, "# ====== T2 — normal ======"),
            (.low, "# ====== T3 — low ======"),
        ]
        var out: [String] = []
        for (priority, header) in tiers {
            let terms = d.terms.filter { $0.priority == priority }
            if !terms.isEmpty { out += [header] + terms.map { $0.text } + [""] }
        }
        return out.joined(separator: "\n")
    }
}
