import CryptoKit
import Foundation
import YascribeProviders
import YascribeTranscription

public enum ArchiveError: Error, Equatable, LocalizedError {
    case dimensionMismatch, invalidVector, contextTooSmall

    public var errorDescription: String? {
        switch self {
        case .dimensionMismatch: "The embedding model returned vectors of a different size than the archive index uses."
        case .invalidVector: "The embedding model returned an unusable vector."
        case .contextTooSmall: "The model's Context window is too small to answer from your meetings."
        }
    }
}

/// Lokalny indeks archiwum (pochodna kopia danych, nie źródło): fragmenty spotkań z wektorami JEDNEGO modelu embeddingu.
/// Plik jest nieczytelny albo niespójny → indeks pusty i budowany od nowa; nic z nagrań i notatek nie jest tu zapisywane.
public struct ArchiveIndex: Codable, Equatable, Sendable {
    public struct Chunk: Codable, Equatable, Sendable {
        public var sessionID: String
        /// Sekundy w transkrypcie; `nil` = My notes albo tekst notatki.
        public var start: Double?
        public var text: String
        /// Float32, długość 1; pusty w `Source.pending` i w `Answer.sources`.
        public var vector: Data

        public init(sessionID: String, start: Double?, text: String, vector: Data = Data()) {
            self.sessionID = sessionID
            self.start = start
            self.text = text
            self.vector = vector
        }
    }

    /// Spotkanie podzielone na fragmenty do osadzenia, z odciskiem treści (tytuł + wszystkie fragmenty).
    public struct Source: Equatable, Sendable {
        public var sessionID: String
        public var title: String
        public var pending: [Chunk]
        public var fingerprint: String

        public init(sessionID: String, title: String, myNotes: String, summary: String?, transcript: Transcript?) {
            self.sessionID = sessionID
            self.title = title
            // Wypowiedzi w formacie linii notatki (`[m:ss] Me: …`), z początkiem pierwszej wypowiedzi we fragmencie.
            var lines: [(start: Double?, text: String)] = []
            if let transcript {
                let spoken = transcript.utterances
                    .filter { !$0.excludedFromNotes && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted { $0.start < $1.start }
                lines = zip(spoken, NotePromptBuilder.transcriptLines(transcript)).map { (start: $0.start, text: $1) }
            }
            let paragraphs = [myNotes, summary ?? ""].flatMap { text in
                text.components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { (start: Double?.none, text: $0) }
            }
            let packed = ArchiveIndex.pack(lines, separator: "\n") + ArchiveIndex.pack(paragraphs, separator: "\n\n")
            pending = packed.map { Chunk(sessionID: sessionID, start: $0.start, text: $0.text) }
            var hasher = SHA256()
            hasher.update(data: Data(title.utf8))
            for chunk in pending {
                hasher.update(data: Data("\u{0}\(chunk.start.map { String($0) } ?? "-")\u{0}\(chunk.text)".utf8))
            }
            fingerprint = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    public static let chunkChars = 1_200
    /// Waga trafienia słownego w wyniku (cosinus + waga × odsetek słów zapytania w fragmencie).
    static let lexicalWeight = 0.15

    public var space: String
    /// Długość wektora, ustalona przez pierwszy wektor i egzekwowana potem; `nil`, dopóki indeks nie ma fragmentów.
    public var dimensions: Int?
    public var fingerprints: [String: String]
    public var chunks: [Chunk]

    public init(space: String) {
        self.space = space
        dimensions = nil
        fingerprints = [:]
        chunks = []
    }

    /// Przestrzeń wektorów: dostawca, adres i model. Wektory z różnych przestrzeni nigdy się nie mieszają.
    public static func space(provider: Provider, model: String) -> String {
        "\(provider.id.uuidString)|\(provider.baseURL.absoluteString)|\(model)"
    }

    // MARK: Plik

    /// Brak pliku, plik nieczytelny, inna przestrzeń albo JAKIKOLWIEK zły fragment (długość ≠ wymiary×4, NaN/∞, norma ≠ 1,
    /// sesja bez odcisku) → pusty indeks tej przestrzeni.
    public static func load(from url: URL, space: String) -> ArchiveIndex {
        let empty = ArchiveIndex(space: space)
        guard let loaded = try? JSONFile.load(ArchiveIndex.self, from: url, default: empty), loaded.space == space,
              loaded.isConsistent else { return empty }
        return loaded
    }

    public func save(to url: URL) throws { try JSONFile.save(self, to: url) }

    private var isConsistent: Bool {
        if chunks.isEmpty { return true }
        guard let dimensions, dimensions > 0 else { return false }
        return chunks.allSatisfy { fingerprints[$0.sessionID] != nil && Self.isUnit($0.vector, dimensions: dimensions) }
    }

    private static func isUnit(_ data: Data, dimensions: Int) -> Bool {
        guard data.count == dimensions * 4 else { return false }
        let norm = data.withUnsafeBytes { raw -> Double in
            var sum = 0.0
            for i in 0..<dimensions {
                let x = Double(raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self))
                if !x.isFinite { return .nan }
                sum += x * x
            }
            return sum.squareRoot()
        }
        return norm.isFinite && abs(norm - 1) <= 1e-3
    }

    // MARK: Świeżość

    /// Bez sieci: usuwa spotkania, których nie ma w `sources` albo których odcisk się zmienił; zwraca to, co trzeba osadzić.
    @discardableResult
    public mutating func reconcile(_ sources: [Source]) -> [Source] {
        let current = Dictionary(sources.map { ($0.sessionID, $0.fingerprint) }, uniquingKeysWith: { _, last in last })
        for (id, fingerprint) in fingerprints where current[id] != fingerprint { remove(id) }
        return sources.filter { fingerprints[$0.sessionID] == nil }
    }

    public mutating func remove(_ sessionID: String) {
        fingerprints[sessionID] = nil
        chunks.removeAll { $0.sessionID == sessionID }
        if chunks.isEmpty { dimensions = nil } // bez wektorów nie ma czego mieszać
    }

    /// Sprawdza liczbę, wymiar, skończoność i niezerową normę (cały zestaw albo nic), normalizuje i zastępuje fragmenty sesji.
    public mutating func insert(_ source: Source, vectors: [[Double]]) throws {
        guard vectors.count == source.pending.count else { throw ArchiveError.invalidVector }
        let units = try vectors.map(Self.unit)
        let size = dimensions ?? units.first?.count
        guard units.allSatisfy({ $0.count == size }) else { throw ArchiveError.dimensionMismatch }
        remove(source.sessionID)
        fingerprints[source.sessionID] = source.fingerprint
        guard let size else { return } // spotkanie bez fragmentów: sam odcisk
        dimensions = size
        chunks += zip(source.pending, units).map { chunk, unit in
            var stored = chunk
            stored.vector = unit.map { Float($0) }.withUnsafeBytes { Data($0) }
            return stored
        }
    }

    // MARK: Embeddingi

    /// Osadza „tytuł\ntekst" fragment po fragmencie; anulowanie sprawdzane między wywołaniami.
    public static func embed(_ source: Source, client: OpenAICompatibleClient, model: String) async throws -> [[Double]] {
        var out: [[Double]] = []
        for chunk in source.pending {
            try Task.checkCancellation()
            out.append(try await client.embed(model: model, text: "\(source.title)\n\(chunk.text)"))
        }
        return out
    }

    public func embedQuery(_ text: String, client: OpenAICompatibleClient, model: String) async throws -> [Double] {
        let unit = try Self.unit(try await client.embed(model: model, text: text))
        if let dimensions, unit.count != dimensions { throw ArchiveError.dimensionMismatch }
        return unit
    }

    /// Wektor jednostkowy; pusty, z NaN/∞ albo o zerowej normie jest odrzucany.
    static func unit(_ v: [Double]) throws -> [Double] {
        guard !v.isEmpty, v.allSatisfy(\.isFinite) else { throw ArchiveError.invalidVector }
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm.isFinite, norm > 1e-12 else { throw ArchiveError.invalidVector }
        return v.map { $0 / norm }
    }

    // MARK: Wyszukiwanie

    /// Cosinus (iloczyn skalarny wektorów jednostkowych) + 0,15 × odsetek słów `terms` (≥ 3 znaki, bez wielkości liter
    /// i diakrytyków) znalezionych we fragmencie. Remis: sesja, potem początek. Tylko `sessions`, do `perSession` na spotkanie.
    public func search(vector: [Double], terms: String, in sessions: Set<String>, limit: Int = 8, perSession: Int = 3) -> [Chunk] {
        guard let dimensions, vector.count == dimensions, limit > 0, perSession > 0, let query = try? Self.unit(vector) else { return [] }
        let q = query.map { Float($0) }
        let words = Self.words(in: terms)
        var scored: [(chunk: Chunk, score: Double)] = []
        for chunk in chunks where sessions.contains(chunk.sessionID) && chunk.vector.count == dimensions * 4 {
            let dot = chunk.vector.withUnsafeBytes { raw -> Float in
                var sum: Float = 0
                for i in 0..<dimensions { sum += raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self) * q[i] }
                return sum
            }
            var score = Double(dot)
            if !words.isEmpty {
                let text = Self.fold(chunk.text)
                score += Self.lexicalWeight * Double(words.filter { text.contains($0) }.count) / Double(words.count)
            }
            scored.append((chunk, score))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.chunk.sessionID != $1.chunk.sessionID { return $0.chunk.sessionID < $1.chunk.sessionID }
            return ($0.chunk.start ?? -1) < ($1.chunk.start ?? -1)
        }
        var perMeeting: [String: Int] = [:]
        var out: [Chunk] = []
        for (chunk, _) in scored where out.count < limit && perMeeting[chunk.sessionID, default: 0] < perSession {
            perMeeting[chunk.sessionID, default: 0] += 1
            out.append(chunk)
        }
        return out
    }

    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static func words(in text: String) -> [String] {
        let parts = fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
        return Array(Set(parts)).sorted()
    }

    // MARK: Dzielenie

    /// Pakuje kawałki w fragmenty do `chunkChars` znaków; `start` fragmentu = start pierwszego kawałka. Zbyt długi kawałek tnie na twardo.
    static func pack(_ items: [(start: Double?, text: String)], separator: String) -> [(start: Double?, text: String)] {
        var out: [(start: Double?, text: String)] = []
        var current: (start: Double?, text: String)?
        for item in items {
            let characters = Array(item.text)
            let pieces = stride(from: 0, to: max(characters.count, 1), by: chunkChars).map {
                String(characters[$0..<min($0 + chunkChars, characters.count)])
            }
            for piece in pieces {
                if let c = current, c.text.count + separator.count + piece.count <= chunkChars {
                    current = (c.start, c.text + separator + piece)
                } else {
                    if let c = current { out.append(c) }
                    current = (item.start, piece)
                }
            }
        }
        if let current { out.append(current) }
        return out
    }
}
