import Foundation
import YascribeProviders
import YascribeTranscription

/// Wynik korekty obok oryginału: `runs/<runID>/corrected.json`.
public struct CorrectedTranscript: Codable, Equatable, Sendable {
    public var transcript: Transcript
    public var model: String
    public var batches: Int
    public var failedBatches: Int
    public var rejectedLines: Int
    /// Pierwszy powód niepowodzenia partii (limit czasu, błąd HTTP, zła numeracja) — do komunikatu „Correction failed".
    public var firstError: String?

    /// Żadna partia nie przeszła: nic nie zostało poprawione (to jest „Correction failed", a nie „parts kept as heard").
    public var failedCompletely: Bool { batches > 0 && failedBatches == batches }

    public init(transcript: Transcript, model: String, batches: Int, failedBatches: Int, rejectedLines: Int, firstError: String? = nil) {
        self.firstError = firstError
        self.transcript = transcript
        self.model = model
        self.batches = batches
        self.failedBatches = failedBatches
        self.rejectedLines = rejectedLines
    }

    public static func load(session: URL, runID: String?) -> CorrectedTranscript? {
        guard let runID, RunDirectory.isValid(runID: runID) else { return nil }
        guard var c = (try? JSONFile.load(CorrectedTranscript?.self, from: RunDirectory(session: session, runID: runID).corrected, default: nil)) ?? nil else { return nil }
        c.transcript = c.transcript.echoMarked()
        return c
    }
}

public extension RunDirectory {
    var corrected: URL { url.appendingPathComponent("corrected.json") }
}

public enum CorrectionRules {
    /// Poprawiona linia musi mieć 0,6–1,6× długości oryginału — model nie skraca ani nie rozwija wypowiedzi.
    public static let band: ClosedRange<Double> = 0.6...1.6

    public static func accepts(original: String, corrected: String) -> Bool {
        let o = original.trimmingCharacters(in: .whitespaces).count
        let c = corrected.trimmingCharacters(in: .whitespaces).count
        guard o > 0, c > 0 else { return false }
        return band.contains(Double(c) / Double(o))
    }
}

public enum CorrectionBatches {
    /// Linie `[n] tekst`, pakowane po kolei w partie do `maxChars` znaków RENDEROWANEJ partii (`[k] ` z numerem lokalnym `k`,
    /// tekst i `\n`; jedna wypowiedź nigdy nie jest dzielona). Liczy się to, co dostaje model, nie sam tekst (przegląd T12).
    public static func split(_ lines: [(n: Int, text: String)], maxChars: Int) -> [[(n: Int, text: String)]] {
        var out: [[(n: Int, text: String)]] = []
        var cur: [(n: Int, text: String)] = []
        var size = 0
        for l in lines {
            // `+ 1` na `\n` liczone zawsze (o jeden za dużo przy ostatniej linii: zapas, nie błąd).
            func rendered(_ k: Int) -> Int { "[\(k)] ".count + l.text.count + 1 }
            if !cur.isEmpty && size + rendered(cur.count + 1) > maxChars { out.append(cur); cur = []; size = 0 }
            cur.append(l)
            size += rendered(cur.count)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    public static func render(_ batch: [(n: Int, text: String)]) -> String {
        // Wypowiedź z `\n` musi iść jako JEDNA linia: `parse` pomija linie niezaczynające się od `[`, więc ogon
        // po `\n` zniknąłby po cichu z poprawionego transkryptu (przegląd T6, D1).
        batch.map { "[\($0.n)] " + $0.text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n")
    }

    /// Odpowiedź modelu → `numer → tekst`. `nil`, gdy numery nie są DOKŁADNIE oczekiwanymi (liczba, kolejność, brak/nadmiar).
    public static func parse(_ reply: String, expected: [Int]) -> [Int: String]? {
        var got: [(Int, String)] = []
        for raw in reply.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
                  let n = Int(line[line.index(after: line.startIndex)..<close]) else { continue }
            got.append((n, String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)))
        }
        guard got.map(\.0) == expected else { return nil }
        return Dictionary(uniqueKeysWithValues: got)
    }
}

/// Korekta po transkrypcji (spec 1.5 §4.1): model z presetu poprawia wypowiedzi partiami. Czas, mówca i flagi języka
/// zostają z oryginału (kopiujemy transkrypt i podmieniamy tylko `text`); wypowiedzi z flagą nie idą do modelu.
public struct Corrector: Sendable {
    public let client: OpenAICompatibleClient
    public let assignment: RoleAssignment
    public var maxBatchChars: Int
    /// Całkowity limit czasu na jedną partię (sekundy). Po nim partia zostaje oryginalna i liczy się jako nieudana.
    public var batchTimeout: Double
    /// Limit transportowy żądania (`ChatLimits.transport`) i `temperature` (tylko lokalnie; `nil` = bez pola).
    public var chatTimeout: Double
    public var temperature: Double?
    /// Budżet kontekstu lokalnego modelu (`nil` = API: partia `maxBatchChars`, bez `max_tokens`).
    public var budget: ContextBudget?
    /// Przerywniki do usunięcia (F20 P2): lista idzie do polecenia dla modelu (A) i do filtra po korekcie (B). Pusta = nic nie usuwamy.
    public var fillerWords: [String]
    /// Termy i uczestnicy do polecenia (F21, D6): dane dla modelu, nie instrukcje. `nil` = polecenie bajt w bajt jak dotąd.
    public var vocabulary: PromptVocabulary?

    public init(client: OpenAICompatibleClient, assignment: RoleAssignment, maxBatchChars: Int = 6_000, batchTimeout: Double = 120,
                chatTimeout: Double = 120, temperature: Double? = nil, budget: ContextBudget? = nil, fillerWords: [String] = [],
                vocabulary: PromptVocabulary? = nil) {
        self.fillerWords = fillerWords
        self.vocabulary = vocabulary
        self.budget = budget
        self.client = client
        self.assignment = assignment
        self.maxBatchChars = maxBatchChars
        self.batchTimeout = batchTimeout
        self.chatTimeout = chatTimeout
        self.temperature = temperature
    }

    public func system(language: LanguageCode?) -> String {
        var s = """
        You correct speech-to-text transcripts line by line. Fix recognition errors, punctuation and casing. \
        Do not add, remove, merge or reorder content, and do not summarize or translate.
        The input is numbered lines like "[12] text". Reply with exactly the same numbers, one corrected line per \
        input line, in the same order, and nothing else.
        """
        if !fillerWords.isEmpty {
            s += "\nException: remove filler sounds and hesitations (for example: \(fillerWords.prefix(8).joined(separator: ", "))). "
                + "Keep every word that carries meaning."
        }
        if let language { s += "\nThe transcript language is \(language.englishName)." }
        if let lines = vocabulary?.promptLines { s += "\n\(lines)" }
        if let extra = assignment.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            s += "\nExtra instructions from the user: \(extra)"
        }
        return s
    }

    /// Limit znaków tekstu w jednej partii: z budżetu (dwie reguły z `ContextBudget`, plus limit czasowy) albo `maxBatchChars`.
    public func batchLimit(language: LanguageCode?) -> Int {
        guard let budget else { return maxBatchChars }
        return min(ContextBudget.correctionBatchCap,
                   budget.pairedInputChars(fixedChars: system(language: language).count, replyFactor: ContextBudget.correctionReplyFactor))
    }

    public func correct(_ original: Transcript, language: LanguageCode?,
                        isCancelled: @Sendable () -> Bool = { Task.isCancelled }) async -> CorrectedTranscript {
        var out = original
        // Numer linii = indeks wypowiedzi + 1; tylko niepuste i niezaflagowane.
        let all: [(n: Int, text: String)] = original.utterances.enumerated().compactMap { i, u in
            u.excludedFromNotes || u.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (i + 1, u.text)
        }
        let limit = batchLimit(language: language)
        // F5: z budżetem wypowiedź, która sama nie mieści się w partii (miarą `split`; np. po dopisaniu słownika do polecenia),
        // nie idzie do modelu — zostaje oryginalna i liczy się jako odrzucona. API (bez budżetu) bez zmian.
        let lines = budget == nil ? all : all.filter { "[1] ".count + $0.text.count + 1 <= limit }
        if lines.isEmpty, !all.isEmpty, let budget {
            // Kontekst za mały nawet na prompt albo na każdą wypowiedź: jawny błąd, nigdy wysyłka.
            return CorrectedTranscript(transcript: out, model: assignment.model, batches: 1, failedBatches: 1, rejectedLines: 0,
                                       firstError: "\(assignment.model)'s Context window (\(budget.tokens) tokens) is too small for correction.")
        }
        let batches = CorrectionBatches.split(lines, maxChars: limit)
        let system = system(language: language)
        var failed = 0
        var rejected = all.count - lines.count
        var firstError: String?
        for (index, batch) in batches.enumerated() {
            if isCancelled() {
                failed += batches.count - index
                if firstError == nil { firstError = "Correction was cancelled." }
                break
            }
            do {
                let model = assignment.model
                // Numeracja 1…N w każdej partii (spec §14 pkt 3): dziury po pominiętych liniach model wypełniał i cała partia
                // przepadała. Numer lokalny `k` wraca na wypowiedź `batch[k − 1]`.
                let numbered = batch.enumerated().map { (n: $0.offset + 1, text: $0.element.text) }
                let user = CorrectionBatches.render(numbered)
                let maxTokens = budget.map { _ in ContextBudget.maxTokens(inputChars: user.count, replyFactor: ContextBudget.correctionReplyFactor) }
                let client = client, chatTimeout = chatTimeout, temperature = temperature
                let reply = try await withDeadline(batchTimeout) {
                    // Korekta tekstu nie potrzebuje myślenia; z nim model hybrydowy potrafi milczeć ponad `batchTimeout` (F20 P1).
                    try await client.chat(model: model, system: system, user: user, timeout: chatTimeout, maxTokens: maxTokens,
                                          temperature: temperature, thinking: false)
                }
                guard let fixed = CorrectionBatches.parse(reply, expected: numbered.map(\.n)) else {
                    failed += 1
                    if firstError == nil { firstError = "The model's answer didn't match the numbered lines." }
                    continue
                }
                for (k, l) in batch.enumerated() {
                    guard let new = fixed[k + 1], CorrectionRules.accepts(original: l.text, corrected: new) else { rejected += 1; continue }
                    out.utterances[l.n - 1].text = new
                }
            } catch {
                failed += 1
                if firstError == nil {
                    let hinted = ContextError.localHint(provider: client.provider, error, transport: chatTimeout) != nil
                    firstError = ContextError.isCutOff(error) || ContextError.isEmptyReply(error) || ContextError.isInputTruncated(error) || hinted
                        ? ContextError.describe(model: assignment.model, error, provider: client.provider, transport: chatTimeout) : "\(error)"
                }
            }
        }
        // Filtr po modelu (F20 P2): działa też na liniach, których model nie poprawił (odrzucone, nieudana partia). Całkowita porażka
        // zostaje bez zmian — `NotesModel` i tak wtedy zwraca oryginał.
        if !fillerWords.isEmpty, failed < batches.count {
            for l in lines { out.utterances[l.n - 1].text = FillerWords.remove(out.utterances[l.n - 1].text, words: fillerWords) }
        }
        return CorrectedTranscript(transcript: out, model: assignment.model, batches: batches.count,
                                   failedBatches: failed, rejectedLines: rejected, firstError: firstError)
    }
}
