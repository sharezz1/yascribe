import Foundation

public enum KeyMigrationOutcome: Equatable, Sendable {
    case copied
    case alreadyPresent
    case noOldKey
    /// Błąd odczytu starego klucza (np. odmowa dostępu po zmianie bundle ID) — to nie „brak klucza".
    case unreadable(Int32)
    /// Błąd odczytu albo zapisu nowej usługi.
    case newStoreFailed(Int32)
}

/// Kopiuje klucze dostawców ze starej usługi pęku do nowej. Stara pozycja nigdy nie jest usuwana:
/// usunięcie to krok użytkownika, po sprawdzeniu, że klucze działają w nowej usłudze.
public struct KeyMigration: Sendable {
    public let old: any SecretStore
    public let new: any SecretStore

    public init(old: any SecretStore, new: any SecretStore) {
        self.old = old
        self.new = new
    }

    private static func code(_ error: Error) -> Int32 {
        if case SecretStoreError.keychain(let c) = error { return c }
        return -1
    }

    /// `resolved` pomijamy bez odczytu pęku. Nowa usługa jest czytana pierwsza: klucz już skopiowany nie wywołuje
    /// pytania systemu o dostęp do starej pozycji.
    public func run(providerIDs: [UUID], resolved: Set<UUID>) -> [UUID: KeyMigrationOutcome] {
        var out: [UUID: KeyMigrationOutcome] = [:]
        for id in providerIDs where !resolved.contains(id) {
            do {
                if try new.get(id) != nil { out[id] = .alreadyPresent; continue }
            } catch { out[id] = .newStoreFailed(Self.code(error)); continue }
            let oldKey: String?
            do { oldKey = try old.get(id) } catch { out[id] = .unreadable(Self.code(error)); continue }
            guard let value = oldKey else { out[id] = .noOldKey; continue }
            do { try new.set(id, value); out[id] = .copied } catch { out[id] = .newStoreFailed(Self.code(error)) }
        }
        return out
    }
}

/// Zapis, które klucze są już rozstrzygnięte (`legacy-migration.json`), żeby kolejne starty nie czytały starej usługi.
/// Nieudane (`unreadable`, `newStoreFailed`) wracają przy następnym starcie.
public enum KeyMigrationLedger {
    private struct File: Codable { var resolved: [UUID] }

    static func url(_ root: URL) -> URL { root.appendingPathComponent("legacy-migration.json") }

    /// Brak lub nieczytelny plik = pusty zbiór.
    public static func resolved(root: URL) -> Set<UUID> {
        guard let data = try? Data(contentsOf: url(root)), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(file.resolved)
    }

    /// Dopisuje do już zapisanych (nie nadpisuje): wcześniejsze sukcesy nie wracają do sprawdzania.
    public static func record(_ outcomes: [UUID: KeyMigrationOutcome], root: URL) {
        var all = resolved(root: root)
        for (id, outcome) in outcomes {
            switch outcome {
            case .copied, .alreadyPresent, .noOldKey: all.insert(id)
            case .unreadable, .newStoreFailed: break
            }
        }
        guard !all.isEmpty else { return }
        let file = File(resolved: all.sorted { $0.uuidString < $1.uuidString })
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(file).write(to: url(root), options: .atomic)
    }
}
