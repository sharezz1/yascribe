import AppKit
import Foundation
import Testing
import YascribeProviders
@testable import YascribeApp

/// Pęk kluczy, który liczy każdy dostęp (TASK-86 R5): agent CLI nie może go dotknąć w żadnej ścieżce aplikacji.
private final class CountingStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var touches: Int { lock.withLock { count } }
    func get(_ id: UUID) throws -> String? { lock.withLock { count += 1 }; return nil }
    func set(_ id: UUID, _ value: String) throws { lock.withLock { count += 1 } }
    func delete(_ id: UUID) throws { lock.withLock { count += 1 } }
}

@Test @MainActor func agentProviderGoesThroughTheAppWithoutTheKeychain() async throws {
    _ = NSApplication.shared
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", data.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    defer { try? FileManager.default.removeItem(at: data) }

    // Atrapa Claude Code: każdy czat odpowiada „OK" w poprawnym formacie wyniku.
    let bin = data.appendingPathComponent("claude")
    let json = #"{"type":"result","is_error":false,"result":"OK","num_turns":1,"stop_reason":"end_turn","permission_denials":[]}"#
    try "#!/bin/sh\ncat > /dev/null\necho '\(json)'\n".write(to: bin, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

    let store = CountingStore()
    model.secrets = store
    let agent = Provider(name: "Claude Code", baseURL: bin, kind: .claudeCLI)
    model.providers.providers.append(agent)

    guard case .success = model.makeClient(for: agent.id) else { Issue.record("no client for the agent"); return }
    await model.probe(providerID: agent.id, model: "sonnet", role: .correction, language: nil) // R4: sonda czatu, nie ASR
    #expect(model.probeCache.result(provider: agent.id, model: "sonnet", role: .correction, language: nil)?.works == true)
    model.removeProvider(agent.id)
    #expect(store.touches == 0)
    #expect(model.provider(agent.id) == nil)
}
