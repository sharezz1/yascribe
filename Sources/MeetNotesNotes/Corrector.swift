import Foundation
import MeetNotesProviders
import MeetNotesTranscription

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
    /// Linie `[n] tekst`, pakowane po kolei w partie do `maxChars` znaków (jedna wypowiedź nigdy nie jest dzielona).
    public static func split(_ lines: [(n: Int, text: String)], maxChars: Int) -> [[(n: Int, text: String)]] {
        var out: [[(n: Int, text: String)]] = []
        var cur: [(n: Int, text: String)] = []
        var size = 0
        for l in lines {
            if !cur.isEmpty && size + l.text.count > maxChars { out.append(cur); cur = []; size = 0 }
            cur.append(l)
            size += l.text.count
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

    public init(client: OpenAICompatibleClient, assignment: RoleAssignment, maxBatchChars: Int = 6_000, batchTimeout: Double = 120) {
        self.client = client
        self.assignment = assignment
        self.maxBatchChars = maxBatchChars
        self.batchTimeout = batchTimeout
    }

    public func system(language: LanguageCode?) -> String {
        var s = """
        You correct speech-to-text transcripts line by line. Fix recognition errors, punctuation and casing. \
        Do not add, remove, merge or reorder content, and do not summarize or translate.
        The input is numbered lines like "[12] text". Reply with exactly the same numbers, one corrected line per \
        input line, in the same order, and nothing else.
        """
        if let language { s += "\nThe transcript language is \(language.englishName)." }
        if let extra = assignment.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            s += "\nExtra instructions from the user: \(extra)"
        }
        return s
    }

    public func correct(_ original: Transcript, language: LanguageCode?) async -> CorrectedTranscript {
        var out = original
        // Numer linii = indeks wypowiedzi + 1; tylko niepuste i niezaflagowane.
        let lines: [(n: Int, text: String)] = original.utterances.enumerated().compactMap { i, u in
            u.excludedFromNotes || u.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (i + 1, u.text)
        }
        let batches = CorrectionBatches.split(lines, maxChars: maxBatchChars)
        let system = system(language: language)
        var failed = 0
        var rejected = 0
        var firstError: String?
        for batch in batches {
            if Task.isCancelled { break }
            do {
                let model = assignment.model
                let user = CorrectionBatches.render(batch)
                let client = client
                let reply = try await withDeadline(batchTimeout) { try await client.chat(model: model, system: system, user: user) }
                guard let fixed = CorrectionBatches.parse(reply, expected: batch.map(\.n)) else {
                    failed += 1
                    if firstError == nil { firstError = "The model's answer didn't match the numbered lines." }
                    continue
                }
                for l in batch {
                    guard let new = fixed[l.n], CorrectionRules.accepts(original: l.text, corrected: new) else { rejected += 1; continue }
                    out.utterances[l.n - 1].text = new
                }
            } catch {
                failed += 1
                if firstError == nil { firstError = "\(error)" }
            }
        }
        return CorrectedTranscript(transcript: out, model: assignment.model, batches: batches.count,
                                   failedBatches: failed, rejectedLines: rejected, firstError: firstError)
    }
}
