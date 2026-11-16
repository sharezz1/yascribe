import Foundation
import YascribeNotes
import YascribeProviders
import YascribeTranscription

extension CLI {
    /// Korekta transkryptu z przebiegu (jak w aplikacji: filtr przerywników, bez zapisu do przebiegu). Wynik trafia do `--out`.
    /// `--vocabulary <vocabulary.txt>` = polecenie ze słownikiem i uczestnikami z tego pliku; bez opcji `vocabulary: nil`.
    /// `--context <tokeny>` (domyślnie 16384, tylko serwer lokalny) i `--timeout <sekundy>` (domyślnie jak w aplikacji).
    static func correct(_ args: [String]) async throws {
        let runURL = URL(fileURLWithPath: try positional(args, 0))
        guard let langRaw = value(args, "--language"), let outPath = value(args, "--out") else {
            FileHandle.standardError.write(Data("--language i --out są obowiązkowe\n".utf8)); exit(64)
        }
        let transcript = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: runURL.appendingPathComponent("transcript.json")))
        var vocabulary: PromptVocabulary?
        if let path = value(args, "--vocabulary") {
            vocabulary = try parseVocabulary(String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8))
            // `--only terms|attendees`: tylko jedna lista (do izolowania wpływu na korektę).
            switch value(args, "--only") {
            case "terms": vocabulary?.attendees = []
            case "attendees": vocabulary?.terms = []
            default: break
            }
        }
        let model = try positional(args, 2)
        let client = try client(try positional(args, 1))
        // Jak w aplikacji (`NotesModel`): limity `.correctionBatch`, budżet tylko lokalnie. `--context` = „Context window" dostawcy
        // (bez wykrywania jak w aplikacji), `--timeout` = limit sekund na partię.
        let limits = ChatLimits.for(client.provider, call: .correctionBatch)
        func positive(_ name: String) -> Double? {
            guard let raw = value(args, name) else { return nil }
            guard let v = Double(raw), v > 0 else { FileHandle.standardError.write(Data("\(name): podaj liczbę dodatnią\n".utf8)); exit(64) }
            return v
        }
        let batchTimeout = positive("--timeout") ?? limits.soft
        let budget = client.provider.isLocal ? ContextBudget(tokens: positive("--context").map { Int($0) } ?? 16384) : nil
        let corrector = Corrector(client: client, assignment: RoleAssignment(providerID: UUID(), model: model),
                                  batchTimeout: batchTimeout, chatTimeout: max(limits.transport, batchTimeout + 30),
                                  temperature: limits.temperature, budget: budget, fillerWords: FillerWords.defaults, vocabulary: vocabulary)
        // Kontrola: polecenie ma być bajt w bajt tym z zapisanego `vocabulary.txt`.
        if let v = vocabulary, let lines = v.promptLines,
           value(args, "--only") == nil, let saved = value(args, "--vocabulary"), try String(contentsOf: URL(fileURLWithPath: saved), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) != lines {
            FileHandle.standardError.write(Data("ostrzeżenie: odtworzone polecenie słownika różni się od pliku\n".utf8))
        }
        let result = await corrector.correct(transcript, language: try LanguageCode(langRaw))
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(result).write(to: URL(fileURLWithPath: outPath))
        print("batches \(result.batches) failed \(result.failedBatches) rejected \(result.rejectedLines) \(result.firstError ?? "")")
    }

    /// Odwrotność `PromptVocabulary.promptLines`: wartości po `): ` do końcowej kropki, rozdzielone `; `.
    static func parseVocabulary(_ text: String) -> PromptVocabulary {
        func items(_ prefix: String) -> [String] {
            guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }),
                  let r = line.range(of: "): ") else { return [] }
            return line[r.upperBound...].dropLast().components(separatedBy: "; ")
        }
        return PromptVocabulary(terms: items("Known names and terms"), attendees: items("Meeting attendees"))
    }
}
