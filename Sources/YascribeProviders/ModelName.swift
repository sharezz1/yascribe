import Foundation

/// Nazwa modelu do wyświetlania (faza 2.1 minimalizm). OpenRouter podaje `name` jako „Dostawca: Nazwa";
/// przedrostek dostawcy jest zbędny, bo ikona i menu już pokazują, skąd model pochodzi.
public enum ModelName {
    /// Bez `apiName` (lub pustego) bierze ogon `id` po ostatnim `/`, np. `nvidia/parakeet-tdt` → `parakeet-tdt`.
    public static func display(id: String, apiName: String?) -> String {
        let name = apiName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            return String(id.split(separator: "/").last ?? Substring(id))
        }
        // Ucinamy tylko pierwszy przedrostek i tylko gdy reszta niepusta, żeby „Qwen: Qwen3: 8B" dało „Qwen3: 8B".
        if let sep = name.range(of: ": ") {
            let rest = name[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        return name
    }
}

/// Tabela nazw po `id` modelu. Klucz to samo `id`: ta sama nazwa u różnych dostawców jest taka sama.
public struct ModelNameCache: Codable, Equatable, Sendable {
    public var names: [String: String] = [:]

    public init() {}

    /// Zwraca `true`, gdy tabela się zmieniła. Modele bez nazwy są pomijane.
    @discardableResult
    public mutating func record(_ models: [ModelInfo]) -> Bool {
        var changed = false
        for m in models {
            guard let name = m.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            if names[m.id] != name {
                names[m.id] = name
                changed = true
            }
        }
        return changed
    }

    public func display(_ id: String) -> String {
        ModelName.display(id: id, apiName: names[id])
    }
}
