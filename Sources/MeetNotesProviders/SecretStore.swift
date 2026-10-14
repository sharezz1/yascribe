import Foundation
import Security

/// Klucze API: w pęku kluczy, nigdy w pliku ustawień ani w logu (spec fazy 1, §7, P8).
public protocol SecretStore: Sendable {
    func get(_ id: UUID) throws -> String?
    func set(_ id: UUID, _ value: String) throws
    func delete(_ id: UUID) throws
}

public enum SecretStoreError: Error, Equatable {
    case keychain(Int32)
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "meetnotes.provider") { self.service = service }

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func get(_ id: UUID) throws -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return nil }
        guard st == errSecSuccess, let d = out as? Data else { throw SecretStoreError.keychain(st) }
        return String(decoding: d, as: UTF8.self)
    }

    public func set(_ id: UUID, _ value: String) throws {
        let data = Data(value.utf8)
        let st = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var q = query(id)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let st2 = SecItemAdd(q as CFDictionary, nil)
            guard st2 == errSecSuccess else { throw SecretStoreError.keychain(st2) }
        } else if st != errSecSuccess {
            throw SecretStoreError.keychain(st)
        }
    }

    public func delete(_ id: UUID) throws {
        let st = SecItemDelete(query(id) as CFDictionary)
        guard st == errSecSuccess || st == errSecItemNotFound else { throw SecretStoreError.keychain(st) }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    public init() {}
    public func get(_ id: UUID) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[id] }
    public func set(_ id: UUID, _ value: String) throws { lock.lock(); values[id] = value; lock.unlock() }
    public func delete(_ id: UUID) throws { lock.lock(); values[id] = nil; lock.unlock() }
}

/// Ostatnie cztery znaki klucza — jedyne, co interfejs pokazuje po zapisie.
public func maskedKey(_ key: String) -> String {
    key.count <= 4 ? "••••" : "••••" + key.suffix(4)
}

/// Stan klucza dostawcy dla interfejsu. Błąd pęku kluczy to NIE „brak klucza" — inaczej użytkownik
/// dodałby dostawcę ponownie albo wpisał klucz nad działającym (S18 §2.4).
public enum KeyStatus: Equatable, Sendable {
    case set(String)        // zamaskowany klucz
    case missing
    case unreadable(String) // opis błędu

    public static func of(_ read: () throws -> String?) -> KeyStatus {
        do { return try read().map { .set(maskedKey($0)) } ?? .missing } catch { return .unreadable("\(error)") }
    }
}
