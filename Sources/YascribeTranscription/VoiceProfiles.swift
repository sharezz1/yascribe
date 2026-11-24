import Foundation
import YascribeProviders

/// Odcisk głosu jednej potwierdzonej próbki (nazwany mówca jednego wykrycia) — dana biometryczna (TASK-117 D3):
/// tylko w `<dane>/voice-profiles.json`, nigdy w folderze spotkania ani w `speakers.json`.
public struct VoiceSample: Codable, Equatable, Sendable {
    public var id: String
    public var model: String
    public var values: [Float]
    public var seconds: Double

    public init(id: String, model: String, values: [Float], seconds: Double) {
        self.id = id; self.model = model; self.values = values; self.seconds = seconds
    }

    /// Ponowne wykrycie mówców daje nowy skrót odcinków, więc ta sama nazwa klucza (`S1`) to nowa próbka.
    public static func id(session: String, run: String, key: String, digest: String) -> String { "\(session)/\(run)/\(key)/\(digest)" }
}

public struct VoiceProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var updatedAt: Date
    public var samples: [VoiceSample]

    public init(id: UUID = UUID(), name: String, updatedAt: Date, samples: [VoiceSample]) {
        self.id = id; self.name = name; self.updatedAt = updatedAt; self.samples = samples
    }

    /// Średnia próbek modelu ważona sekundami mowy (każda znormalizowana), znormalizowana; `nil` = brak próbki tego modelu.
    public func vector(model: String) -> [Float]? {
        let own = samples.filter { $0.model == model && !$0.values.isEmpty }
        guard let first = own.first else { return nil }
        var sum = [Float](repeating: 0, count: first.values.count)
        for sample in own where sample.values.count == sum.count {
            let unit = VoiceVectors.normalized(sample.values)
            for i in sum.indices { sum[i] += unit[i] * Float(sample.seconds) }
        }
        return VoiceVectors.normalized(sum)
    }

    public func seconds(model: String) -> Double { samples.filter { $0.model == model }.reduce(0) { $0 + $1.seconds } }
}

public struct VoiceProfiles: Codable, Equatable, Sendable {
    public static let fileName = "voice-profiles.json"
    /// Starsze próbki modelu wypadają, żeby profil szedł za zmianą głosu i plik nie rósł bez końca.
    public static let maxSamplesPerModel = 20

    public var version = 1
    public var profiles: [VoiceProfile] = []

    public init(profiles: [VoiceProfile] = []) { self.profiles = profiles }

    public static func url(root: URL) -> URL { root.appendingPathComponent(fileName) }

    /// Brak pliku = brak profili; uszkodzony plik = błąd (nie nadpisujemy danych użytkownika).
    public static func load(root: URL) throws -> VoiceProfiles {
        try JSONFile.load(VoiceProfiles.self, from: url(root: root), default: VoiceProfiles())
    }

    public func save(root: URL) throws { try JSONFile.save(self, to: Self.url(root: root)) }

    public static func delete(root: URL) throws {
        let url = url(root: root)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Dopisuje próbkę do profilu o tym imieniu (bez wielkości liter) albo do nowego. Ta sama próbka tego samego modelu drugi raz
    /// nic nie zmienia; ten sam mówca liczony innym modelem to osobna próbka.
    @discardableResult
    public mutating func learn(name: String, sample: VoiceSample, now: Date) -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = profiles.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? { profiles.append(VoiceProfile(name: name, updatedAt: now, samples: [])); return profiles.count - 1 }()
        if !profiles[index].samples.contains(where: { $0.id == sample.id && $0.model == sample.model }) {
            profiles[index].samples.append(sample)
            let own = profiles[index].samples.indices.filter { profiles[index].samples[$0].model == sample.model }
            if own.count > Self.maxSamplesPerModel { profiles[index].samples.remove(at: own[0]) }
            profiles[index].updatedAt = now
        }
        return profiles[index].id
    }

    /// Cofnięcie nauki (imię zmienione albo zdjęte): próbki tego mówcy (wszystkich modeli) znikają z każdego profilu, profil bez próbek też.
    public mutating func forget(sampleID: String) {
        for i in profiles.indices { profiles[i].samples.removeAll { $0.id == sampleID } }
        profiles.removeAll { $0.samples.isEmpty }
    }

    public mutating func remove(id: UUID) { profiles.removeAll { $0.id == id } }
}

public enum VoiceVectors {
    public static func normalized(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? v.map { $0 / norm } : v
    }

    /// Cosinus; różne długości albo wektor zerowy = 0.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += Double(a[i] * b[i]); na += Double(a[i] * a[i]); nb += Double(b[i] * b[i]) }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}
