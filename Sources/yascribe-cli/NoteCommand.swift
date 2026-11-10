import Foundation
import YascribeNotes
import YascribeProviders
import YascribeTranscription

extension CLI {
    /// Summary przebiegu tą samą ścieżką co aplikacja (`NoteGenerator`), bez zapisu do sesji. Narzędzie do porównywania modeli.
    /// `note <przebieg> <baseURL> <model> --language pl --out plik.json [--source raw|corrected] [--thinking on|off] [--vocabulary vocabulary.txt]`
    static func note(_ args: [String]) async throws {
        let runURL = URL(fileURLWithPath: try positional(args, 0))
        guard let langRaw = value(args, "--language"), let outPath = value(args, "--out") else {
            FileHandle.standardError.write(Data("--language i --out są obowiązkowe\n".utf8)); exit(64)
        }
        let raw = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: runURL.appendingPathComponent("transcript.json")))
        var transcript = raw
        if value(args, "--source") != "raw" {
            transcript = try JSONDecoder().decode(CorrectedTranscript.self,
                                                  from: Data(contentsOf: runURL.appendingPathComponent("corrected.json"))).transcript
        }
        var vocabulary: PromptVocabulary?
        if let path = value(args, "--vocabulary") {
            vocabulary = noteVocabulary(try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8))
        }
        let client = try client(try positional(args, 1))
        let limits = ChatLimits.for(client.provider, call: .note)
        var generator = NoteGenerator(client: client, model: try positional(args, 2), timeout: limits.soft,
                                      chatTimeout: limits.transport, maxTokens: limits.maxTokens)
        generator.thinking = value(args, "--thinking") != "off"
        let budget = client.provider.isLocal
            ? ContextBudget(tokens: value(args, "--context").flatMap(Int.init) ?? 16384) : nil // jak „Context window" dostawcy w aplikacji
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("note-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let summary = try await generator.generate(session: session, template: .standard, transcript: transcript, context: "",
                                                   notesLanguage: try LanguageCode(langRaw), budget: budget, vocabulary: vocabulary,
                                                   onProblem: { FileHandle.standardError.write(Data("problem: \($0)\n".utf8)) })
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(summary).write(to: URL(fileURLWithPath: outPath))
        print("model \(summary.model) znaków \(summary.markdown.count) części \(summary.condensedParts.map(String.init) ?? "-")")
    }

    /// Odwrotność `PromptVocabulary.promptLines` (wartości po `): ` do końcowej kropki, rozdzielone `; `).
    static func noteVocabulary(_ text: String) -> PromptVocabulary {
        func items(_ prefix: String) -> [String] {
            guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }),
                  let r = line.range(of: "): ") else { return [] }
            return line[r.upperBound...].dropLast().components(separatedBy: "; ")
        }
        return PromptVocabulary(terms: items("Known names and terms"), attendees: items("Meeting attendees"))
    }
}
