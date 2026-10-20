import Foundation

/// Katalog danych. Zmienna `MEETNOTES_DATA_DIR` przestawia go na katalog w repo
/// na czas prac (`.devdata/`, spec rdzenia §8 — czysto na dysku).
public struct MeetNotesPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> MeetNotesPaths {
        if let dir = env["MEETNOTES_DATA_DIR"], !dir.isEmpty { return MeetNotesPaths(root: URL(fileURLWithPath: dir)) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MeetNotesPaths(root: base.appendingPathComponent("MeetNotes"))
    }

    public var providers: URL { root.appendingPathComponent("providers.json") }
    public var presets: URL { root.appendingPathComponent("presets.json") }
    public var settings: URL { root.appendingPathComponent("settings.json") }
    public var probeCache: URL { root.appendingPathComponent("probe-cache.json") }
    public var templates: URL { root.appendingPathComponent("templates.json") }
    public var sessions: URL { root.appendingPathComponent("sessions") }
}

public enum JSONFile {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Brak pliku → wartość domyślna. Uszkodzony plik → błąd (nie kasujemy cudzych danych).
    public static func load<T: Decodable>(_ type: T.Type, from url: URL, default value: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return value }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public struct PresetsFile: Codable, Equatable, Sendable {
    public var presets: [Preset] = []
    public init(presets: [Preset] = []) { self.presets = presets }

    /// Zapis przez walidację — P7 na poziomie magazynu, nie tylko formularza.
    public mutating func upsert(_ p: Preset) throws {
        try p.validate()
        if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p } else { presets.append(p) }
    }
}

public struct ProvidersFile: Codable, Equatable, Sendable {
    public var providers: [Provider] = []
    public init(providers: [Provider] = []) { self.providers = providers }

    /// Powód odmowy dla nazwy nowego dostawcy; `nil` = można dodać. Nazwy muszą się różnić, żeby komunikaty
    /// („No API key for <nazwa>…") wskazywały jednego dostawcę.
    public func nameError(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give the provider a name." }
        if providers.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(n) == .orderedSame }) {
            return "A provider named “\(n)” already exists."
        }
        return nil
    }

    /// Model Yascribe (Parakeet w procesie) to rekord techniczny, nie dostawca na liście: presety trzymają jego `providerID`,
    /// a lista Providers go nie pokazuje (F20 P3). Dopisuje go, gdy brak — po rodzaju API, nie po nazwie. `true` = dopisano.
    @discardableResult
    public mutating func ensureOnDeviceProvider() -> Bool {
        guard !providers.contains(where: { $0.api == .fluidAudio }) else { return false }
        providers.append(Provider(name: ProviderPreset.onThisMac.name, baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio))
        return true
    }
}
