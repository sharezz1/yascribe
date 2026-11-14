import Foundation
import Testing
@testable import YascribeProviders

// Atrapy agenta CLI (TASK-86): skrypty `#!/bin/sh` w katalogu `mn-<UUID>` (sprząta je scripts/test.sh). Bez prawdziwych CLI.

private let okCodex = """
    echo '{"type":"thread.started","thread_id":"t"}'
    echo '{"type":"turn.started"}'
    echo '{"type":"item.completed","item":{"id":"i0","type":"agent_message","text":"[1] Dobrze."}}'
    echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":2}}'
    """

private func dir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Skrypt-atrapa. Codex odpowiada na `--version` wersją `version` (bramka D7).
private func fake(_ kind: ProviderKind, _ body: String, version: String = "0.167.2", in d: URL? = nil) throws -> Provider {
    let d = try d ?? dir()
    let url = d.appendingPathComponent(kind == .claudeCLI ? "claude" : "codex")
    let head = kind == .codexCLI ? "if [ \"$1\" = \"--version\" ]; then echo \"codex-cli \(version)\"; exit 0; fi\n" : ""
    try ("#!/bin/sh\n" + head + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return Provider(name: "agent", baseURL: url, kind: kind)
}

private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

private func pid(at url: URL) -> pid_t? {
    (try? String(contentsOf: url, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

private func chat(_ p: Provider, limit: Double? = nil) async throws -> String {
    try await AgentCLI.chat(provider: p, model: "m", system: "S", user: "U", effort: "low", limit: limit)
}

private func line(_ s: String) -> Data { Data(s.utf8) }

// MARK: parser Codex

@Test func codexParserTakesTheLastAgentMessage() throws {
    let out = line("""
        {"type":"turn.started"}
        {"type":"item.completed","item":{"type":"agent_message","text":"I'll do it."}}
        {"type":"item.completed","item":{"type":"agent_message","text":"[1] A"}}
        {"type":"turn.completed"}
        """)
    #expect(try AgentCLI.parseCodex(out, exitCode: 0) == "[1] A")
}

@Test func codexParserRejectsAnyToolItem() {
    for type in ["command_execution", "file_change", "web_search", "mcp_tool_call"] {
        let out = line("""
            {"type":"item.started","item":{"type":"\(type)"}}
            {"type":"item.completed","item":{"type":"agent_message","text":"[1] A"}}
            {"type":"turn.completed"}
            """)
        #expect(throws: ProviderError.agentUsedTool(type)) { try AgentCLI.parseCodex(out, exitCode: 0) }
    }
}

@Test func codexParserNeedsACompletedTurnAndExitZero() {
    let noEnd = line(#"{"type":"item.completed","item":{"type":"agent_message","text":"[1] A"}}"#)
    #expect(throws: ProviderError.agentFailed("Codex didn't finish its turn.")) { try AgentCLI.parseCodex(noEnd, exitCode: 0) }
    let ok = line(okCodex.replacingOccurrences(of: "echo '", with: "").replacingOccurrences(of: "'", with: ""))
    #expect(throws: (any Error).self) { try AgentCLI.parseCodex(ok, exitCode: 1) }
    #expect(throws: ProviderError.badResponse("Codex sent output that isn't JSON.")) {
        try AgentCLI.parseCodex(line("{\"type\":\"turn.completed\"}\nnot json"), exitCode: 0)
    }
    #expect(throws: (any Error).self) {
        try AgentCLI.parseCodex(line(#"{"type":"turn.failed","error":{"message":"boom"}}"#), exitCode: 0)
    }
}

// MARK: parser Claude

private func claudeJSON(isError: Bool = false, result: String = "[1] A", turns: Int = 1, stop: String = "end_turn",
                        denials: String = "[]") -> Data {
    line(#"{"type":"result","is_error":\#(isError),"result":"\#(result)","num_turns":\#(turns),"stop_reason":"\#(stop)","permission_denials":\#(denials)}"#)
}

@Test func claudeParserAcceptsOnlyAOneTurnEndTurnResult() throws {
    #expect(try AgentCLI.parseClaude(claudeJSON(), exitCode: 0) == "[1] A")
    #expect(throws: ProviderError.agentUsedTool("turns: 2")) { try AgentCLI.parseClaude(claudeJSON(turns: 2), exitCode: 0) }
    #expect(throws: ProviderError.agentUsedTool("turns: 1")) {
        try AgentCLI.parseClaude(claudeJSON(denials: #"[{"tool_name":"Bash"}]"#), exitCode: 0)
    }
    #expect(throws: ProviderError.replyCutOff) { try AgentCLI.parseClaude(claudeJSON(stop: "max_tokens"), exitCode: 0) }
    #expect(throws: (any Error).self) { try AgentCLI.parseClaude(claudeJSON(), exitCode: 1) } // poprawny JSON, zły kod wyjścia
}

@Test func claudeParserMapsNotLoggedIn() {
    #expect(throws: ProviderError.agentNotSignedIn(AgentCLI.signInHint(.claudeCLI))) {
        try AgentCLI.parseClaude(claudeJSON(isError: true, result: "Not logged in · Please run /login"), exitCode: 1)
    }
}

// MARK: argumenty i środowisko

@Test func environmentDropsAppVariablesAndKeys() {
    let env = AgentCLI.environment(["HOME": "/h", "USER": "u", "YASCRIBE_DATA_DIR": "/x", "OPENAI_API_KEY": "k", "ANTHROPIC_BASE_URL": "x"])
    #expect(Set(env.keys) == ["HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG"])
    #expect(env["HOME"] == "/h" && env["USER"] == "u" && env["LOGNAME"] == "u")
}

@Test func invocationLocksToolsDown() {
    let w = URL(fileURLWithPath: "/tmp/w")
    let codex = AgentCLI.invocation(kind: .codexCLI, model: "m", system: "S", user: "U", effort: "low", workdir: w)
    for f in ["shell_tool", "unified_exec", "apps", "plugins", "computer_use", "browser_use"] {
        #expect(codex.arguments.contains(f), "\(f)")
    }
    #expect(codex.arguments.contains(#"web_search="disabled""#) && codex.arguments.contains("read-only") && codex.arguments.last == "-")
    #expect(codex.input == "S\n\nU")
    let claude = AgentCLI.invocation(kind: .claudeCLI, model: "m", system: "S", user: "U", effort: nil, workdir: w)
    let i = claude.arguments.firstIndex(of: "--tools")!
    #expect(claude.arguments[i + 1] == "" && !claude.arguments.contains("--bare") && !claude.arguments.contains("--effort"))
    #expect(claude.input == "U")
}

// MARK: proces

@Test func chatRunsTheAgentWithLockedArgumentsAndCleanEnvironment() async throws {
    let d = try dir()
    let p = try fake(.codexCLI, "printf '%s\\n' \"$@\" > \(d.path)/args\nenv > \(d.path)/env\ncat > /dev/null\n" + okCodex, in: d)
    #expect(try await chat(p) == "[1] Dobrze.")
    let args = try String(contentsOf: d.appendingPathComponent("args"), encoding: .utf8)
    #expect(args.contains("shell_tool\n") && args.contains("--ephemeral\n"))
    let env = try String(contentsOf: d.appendingPathComponent("env"), encoding: .utf8)
    #expect(!env.contains("YASCRIBE_") && env.contains("PATH=/opt/homebrew/bin"))
}

@Test func largeOutputOnBothStreamsDoesNotDeadlock() async throws {
    // 1 MB na stderr i 1 MB w odpowiedzi na stdout naraz — więcej niż bufor potoku (64 KB).
    let body = """
        cat > /dev/null
        yes x | head -c 1048576 >&2
        printf '{"type":"result","is_error":false,"num_turns":1,"stop_reason":"end_turn","result":"'
        yes y | tr -d '\\n' | head -c 1048576
        printf '"}'
        """
    let p = try fake(.claudeCLI, body)
    #expect(try await chat(p, limit: 30).count == 1_048_576)
}

@Test func cancellingKillsTheAgentQuickly() async throws {
    let d = try dir()
    // Potomek trzyma stdout i nie ignoruje TERM: SIGTERM musi iść do całej grupy, nie czekać na SIGKILL po killGrace.
    let p = try fake(.codexCLI, "echo $$ > \(d.path)/pid\nsh -c 'echo $$ > \(d.path)/child; sleep 60' &\nsleep 60", in: d)
    let task = Task { try await chat(p) }
    try await Task.sleep(for: .seconds(1))
    let started = ContinuousClock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - started < .seconds(1.5))
    let agent = try #require(pid(at: d.appendingPathComponent("pid")))
    #expect(!alive(agent))
    #expect(!alive(try #require(pid(at: d.appendingPathComponent("child")))))
}

@Test func cancellingKillsAChildThatIgnoresTermAndHoldsStdout() async throws {
    let d = try dir()
    // Rodzic kończy się sam, potomek ignoruje SIGTERM i trzyma stdout.
    let p = try fake(.codexCLI, "sh -c 'echo $$ > \(d.path)/child; trap \"\" TERM; sleep 60' &\nsleep 60", in: d)
    let task = Task { try await chat(p) }
    try await Task.sleep(for: .seconds(1))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    let child = try #require(pid(at: d.appendingPathComponent("child")))
    try await Task.sleep(for: .milliseconds(300))
    #expect(!alive(child))
}

@Test func parentExitWhileChildHoldsStdoutStillFinishes() async throws {
    let d = try dir()
    let p = try fake(.codexCLI, "cat > /dev/null\n" + okCodex + "\nsh -c 'echo $$ > \(d.path)/child; trap \"\" TERM; sleep 60' &\nexit 0", in: d)
    let started = ContinuousClock.now
    #expect(try await chat(p) == "[1] Dobrze.")
    #expect(ContinuousClock.now - started < .seconds(6))
    let child = try #require(pid(at: d.appendingPathComponent("child")))
    try await Task.sleep(for: .milliseconds(300))
    #expect(!alive(child))
}

@Test func cancelBeforeStartNeverLaunches() async throws {
    let d = try dir()
    let p = try fake(.claudeCLI, "touch \(d.path)/ran", in: d)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await chat(p)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: d.appendingPathComponent("ran").path))
}

@Test func limitKillsAHungAgent() async throws {
    let d = try dir()
    let p = try fake(.claudeCLI, "echo $$ > \(d.path)/pid\nsleep 60", in: d)
    let started = ContinuousClock.now
    await #expect(throws: ProviderError.agentFailed("Claude Code didn't answer within 1 s.")) { try await chat(p, limit: 1) }
    #expect(ContinuousClock.now - started < .seconds(4))
    #expect(!alive(try #require(pid(at: d.appendingPathComponent("pid")))))
}

@Test func codexSignedOutStopsAtTheFirst401() async throws {
    let loop = "while true; do echo '{\"type\":\"error\",\"message\":\"unexpected status 401 Unauthorized\"}'; sleep 1; done"
    let p = try fake(.codexCLI, loop)
    let started = ContinuousClock.now
    await #expect(throws: ProviderError.agentNotSignedIn(AgentCLI.signInHint(.codexCLI))) { try await chat(p) }
    #expect(ContinuousClock.now - started < .seconds(2))
}

@Test func missingBinaryIsAnExplicitError() async {
    let p = Provider(name: "x", baseURL: URL(fileURLWithPath: "/nonexistent/claude"), kind: .claudeCLI)
    await #expect(throws: (any Error).self) { try await chat(p) }
}

@Test func unverifiedCodexVersionNeverGetsTheTranscript() async throws {
    let d = try dir()
    let p = try fake(.codexCLI, "touch \(d.path)/ran\n" + okCodex, version: "0.0.1", in: d)
    await #expect(throws: ProviderError.agentFailed("Codex 0.0.1 isn't verified with Yascribe yet. Verified: 0.167.2.")) { try await chat(p) }
    #expect(!FileManager.default.fileExists(atPath: d.appendingPathComponent("ran").path))
    #expect(AgentCLI.codexVersion("codex-cli 0.167.2\n") == "0.167.2")
}

// MARK: Check (logowanie)

@Test func verifyAcceptsAnySignInMethodAndHidesTheStatusText() async throws {
    let chatGPT = try fake(.codexCLI, "echo 'Logged in using ChatGPT (jan@example.com)'")
    #expect(await AgentCLI.verify(provider: chatGPT) == .verified(models: 3))
    let apiKey = try fake(.codexCLI, "echo 'Logged in using an API key - sk-***'")
    #expect(await AgentCLI.verify(provider: apiKey) == .verified(models: 3))
    let out = try fake(.codexCLI, "echo 'Not logged in jan@example.com'; exit 1")
    let failed = await AgentCLI.verify(provider: out)
    #expect(failed == .failed(AgentCLI.signInHint(.codexCLI)))
    let claudeKey = try fake(.claudeCLI, #"echo '{"loggedIn":true,"authMethod":"api_key","email":"jan@example.com"}'"#)
    #expect(await AgentCLI.verify(provider: claudeKey) == .verified(models: 3))
    let claudeOut = try fake(.claudeCLI, #"echo '{"loggedIn":false}'"#)
    #expect(await AgentCLI.verify(provider: claudeOut) == .failed(AgentCLI.signInHint(.claudeCLI)))
}

@Test func binaryPathMustBeAnExecutableFile() throws {
    let p = try fake(.claudeCLI, "exit 0")
    #expect((try? AgentCLI.binaryURL(from: p.baseURL.path).get()) == p.baseURL)
    #expect((try? AgentCLI.binaryURL(from: "claude").get()) == nil)
    #expect((try? AgentCLI.binaryURL(from: "/nonexistent/claude").get()) == nil)
    #expect((try? AgentCLI.binaryURL(from: p.baseURL.deletingLastPathComponent().path).get()) == nil) // katalog
}

// MARK: klient, sonda, pęk kluczy (T3)

@Test func clientChatRunsTheAgentAndNeverTouchesHTTP() async throws {
    let p = try fake(.codexCLI, "cat > /dev/null\n" + okCodex)
    let http = StubHTTP { _, _ in fail(500) }
    let c = OpenAICompatibleClient(provider: p, key: nil, http: http)
    #expect(try await c.chat(model: "m", system: "S", user: "U", thinking: false) == "[1] Dobrze.")
    #expect(try await c.listModels().map(\.id) == AgentCLI.models(for: .codexCLI).map(\.id))
    #expect(try await c.listModels(output: "transcription").isEmpty)
    #expect(http.calls.isEmpty)
}

@Test func probeOfAnAgentWorksAndExplainsSignInPlainly() async throws {
    let ok = OpenAICompatibleClient(provider: try fake(.claudeCLI, "cat > /dev/null\necho '\(String(decoding: claudeJSON(), as: UTF8.self))'"), key: nil)
    #expect(await ProbeRunner(client: ok).probe(model: "sonnet", role: .correction, language: nil).works)
    let out = OpenAICompatibleClient(provider: try fake(.claudeCLI, "cat > /dev/null\necho '\(String(decoding: claudeJSON(isError: true, result: "Not logged in · Please run /login"), as: UTF8.self))'"), key: nil)
    let r = await ProbeRunner(client: out).probe(model: "sonnet", role: .summary, language: nil)
    #expect(!r.works && r.failure == AgentCLI.signInHint(.claudeCLI))
}

/// Pęk kluczy, który zawodzi przy każdym dostępie: agent CLI nie może go dotknąć (R5).
private struct ExplodingStore: SecretStore {
    struct Touched: Error {}
    func get(_ id: UUID) throws -> String? { throw Touched() }
    func set(_ id: UUID, _ value: String) throws { throw Touched() }
    func delete(_ id: UUID) throws { throw Touched() }
}

@Test func agentProvidersNeverTouchTheKeychain() throws {
    let agent = Provider(name: "Codex", baseURL: URL(fileURLWithPath: "/opt/homebrew/bin/codex"), kind: .codexCLI)
    #expect(try agent.storedKey(in: ExplodingStore()) == nil)
    try agent.forgetKey(in: ExplodingStore())
    #expect(throws: ExplodingStore.Touched.self) { try openRouter.storedKey(in: ExplodingStore()) }
    #expect(throws: ExplodingStore.Touched.self) { try openRouter.forgetKey(in: ExplodingStore()) }
}
