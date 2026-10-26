import Foundation
import Testing
@testable import YascribeProviders

/// Atrapa pęku: liczy odczyty i potrafi rzucać. Kod błędu jest umowny (nie zmierzony odmowy „Deny" z T0).
private final class ScriptedStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String]
    var getError: Int32?
    var setError: Int32?
    private(set) var getCalls = 0

    init(_ values: [UUID: String] = [:], getError: Int32? = nil, setError: Int32? = nil) {
        self.values = values
        self.getError = getError
        self.setError = setError
    }

    func get(_ id: UUID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        getCalls += 1
        if let e = getError { throw SecretStoreError.keychain(e) }
        return values[id]
    }

    func set(_ id: UUID, _ value: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let e = setError { throw SecretStoreError.keychain(e) }
        values[id] = value
    }

    func delete(_ id: UUID) throws { lock.lock(); values[id] = nil; lock.unlock() }
}

private let denied: Int32 = -25293

private func tempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func copiesOldKeyWhenNewIsMissing() throws {
    let id = UUID()
    let old = ScriptedStore([id: "test-fake-old"]), new = ScriptedStore()
    let out = KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: [])
    #expect(out == [id: .copied])
    #expect(try new.get(id) == "test-fake-old")
}

@Test func keepsExistingNewKey() throws {
    let id = UUID()
    let old = ScriptedStore([id: "test-fake-old"]), new = ScriptedStore([id: "test-fake-new"])
    let out = KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: [])
    #expect(out == [id: .alreadyPresent])
    #expect(try new.get(id) == "test-fake-new")
    #expect(old.getCalls == 0) // klucz już w nowej usłudze nie pyta systemu o starą pozycję
}

@Test func unreadableOldKeyIsReportedNotTreatedAsMissing() {
    let id = UUID()
    let old = ScriptedStore([id: "test-fake-old"], getError: denied), new = ScriptedStore()
    let out = KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: [])
    #expect(out == [id: .unreadable(denied)])
}

@Test func neverDeletesTheOldKey() throws {
    let id = UUID()
    let old = ScriptedStore([id: "test-fake-old"]), new = ScriptedStore()
    #expect(KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: []) == [id: .copied])
    #expect(try old.get(id) == "test-fake-old")
}

@Test func newKeyWriteFailureIsReportedSeparately() throws {
    let id = UUID()
    let old = ScriptedStore([id: "test-fake-old"]), new = ScriptedStore(setError: denied)
    let out = KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: [])
    #expect(out == [id: .newStoreFailed(denied)])
    #expect(try old.get(id) == "test-fake-old")
    let unreadableNew = ScriptedStore(getError: denied)
    #expect(KeyMigration(old: old, new: unreadableNew).run(providerIDs: [id], resolved: []) == [id: .newStoreFailed(denied)])
}

@Test func resolvedKeysAreNotRechecked() throws {
    let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let id = UUID(), other = UUID()
    let old = ScriptedStore([id: "test-fake-old"]), new = ScriptedStore()
    KeyMigrationLedger.record(KeyMigration(old: old, new: new).run(providerIDs: [id], resolved: []), root: root)
    #expect(KeyMigrationLedger.resolved(root: root) == [id])
    let again = ScriptedStore([id: "test-fake-old"])
    _ = KeyMigration(old: again, new: new).run(providerIDs: [id], resolved: KeyMigrationLedger.resolved(root: root))
    #expect(again.getCalls == 0)
    // Kolejny zapis dopisuje, nie nadpisuje: wcześniejszy sukces nie wraca do sprawdzania.
    KeyMigrationLedger.record([other: .noOldKey], root: root)
    #expect(KeyMigrationLedger.resolved(root: root) == [id, other])
}

@Test func unresolvedKeysAreRetriedOnNextRun() throws {
    let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    KeyMigrationLedger.record([UUID(): .unreadable(denied), UUID(): .newStoreFailed(denied)], root: root)
    #expect(KeyMigrationLedger.resolved(root: root).isEmpty)
    #expect(KeyMigrationLedger.resolved(root: root.appendingPathComponent("missing")).isEmpty)
    try Data("not json".utf8).write(to: root.appendingPathComponent("legacy-migration.json"))
    #expect(KeyMigrationLedger.resolved(root: root).isEmpty)
}
