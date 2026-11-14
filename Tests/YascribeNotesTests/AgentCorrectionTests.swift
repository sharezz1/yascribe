import Darwin
import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

// Korekta i notatka z atrapą agenta CLI (TASK-86 T4): skrypty `#!/bin/sh` w `mn-<UUID>` (sprząta scripts/test.sh).

private func agentDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Atrapa Codex: `--version` = zweryfikowana wersja, potem `body`. `$D` = katalog atrapy (licznik uruchomień, pid).
private func codex(_ body: String, in d: URL) throws -> OpenAICompatibleClient {
    let url = d.appendingPathComponent("codex")
    let script = "#!/bin/sh\nD=\(d.path)\nif [ \"$1\" = \"--version\" ]; then echo \"codex-cli 0.167.2\"; exit 0; fi\n"
        + "cat > /dev/null\necho x >> $D/runs\n" + body + "\n"
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return OpenAICompatibleClient(provider: Provider(name: "Codex", baseURL: url, kind: .codexCLI), key: nil)
}

/// `printf`, nie `echo`: `echo` w macOS `/bin/sh` zamienia `\n` w nową linię i rozbija linię JSON.
private func reply(_ text: String) -> String {
    """
    echo '{"type":"turn.started"}'
    printf '%s\\n' '{"type":"item.completed","item":{"id":"i","type":"agent_message","text":"\(text)"}}'
    echo '{"type":"turn.completed"}'
    """
}

private let tool = """
    echo '{"type":"turn.started"}'
    echo '{"type":"item.started","item":{"id":"c","type":"command_execution","command":"cat /etc/hosts"}}'
    echo '{"type":"turn.completed"}'
    """

private func runs(_ d: URL) -> Int {
    ((try? String(contentsOf: d.appendingPathComponent("runs"), encoding: .utf8)) ?? "").split(separator: "\n").count
}

private let assignment = RoleAssignment(providerID: UUID(), model: "gpt-6.1-terra")

@Test func agentCorrectionKeepsTheNumberedContract() async throws {
    let d = try agentDir()
    let c = Corrector(client: try codex(reply(#"[1] No to jest test.\n[2] Tak, dokładnie tak."#), in: d), assignment: assignment)
    let r = await c.correct(transcript([utt("no to jest test"), utt("tak dokładnie tak")]), language: .polish)
    #expect(r.transcript.utterances.map(\.text) == ["No to jest test.", "Tak, dokładnie tak."])
    #expect(r.rejectedLines == 0 && r.failedBatches == 0 && r.aborted == nil)
}

@Test func agentToolUseAbortsTheWholeCorrection() async throws {
    let d = try agentDir()
    // Partia 1 przechodzi, partia 2 używa narzędzia → trzecia nie startuje, wynik to całkowita porażka z powodem narzędzia.
    let body = "if [ $(wc -l < $D/runs) -eq 1 ]; then\n" + reply("[1] Pierwsza linia tutaj.") + "\nelse\n" + tool + "\nfi"
    let c = Corrector(client: try codex(body, in: d), assignment: assignment, maxBatchChars: 30)
    let t = transcript([utt("pierwsza linia tutaj"), utt("druga linia tutaj"), utt("trzecia linia tutaj")])
    let r = await c.correct(t, language: .polish)
    #expect(runs(d) == 2)
    #expect(r.aborted == true && r.failedCompletely)
    #expect(r.firstError == "The agent tried to use a tool (command_execution), so its answer was discarded.")
}

@Test func agentFailureShowsItsOwnMessageNotTheEnum() async throws {
    let d = try agentDir()
    let c = Corrector(client: try codex(#"echo '{"type":"error","message":"model not found"}'"#, in: d), assignment: assignment)
    let r = await c.correct(transcript([utt("no to jest test")]), language: .polish)
    #expect(r.firstError == "Codex: model not found")
    #expect(r.aborted == nil && r.failedCompletely)
}

@Test func claudeNoteCutOffIsAnExplicitFailure() async throws {
    let d = try agentDir()
    let url = d.appendingPathComponent("claude")
    let json = ##"{"type":"result","is_error":false,"result":"# T","num_turns":1,"stop_reason":"max_tokens","permission_denials":[]}"##
    try "#!/bin/sh\ncat > /dev/null\necho '\(json)'\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    let client = OpenAICompatibleClient(provider: Provider(name: "Claude Code", baseURL: url, kind: .claudeCLI), key: nil)
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    await #expect(throws: NoteGenerationError.failed("sonnet's reply was cut off before the end. Try a model with a longer output limit.")) {
        _ = try await NoteGenerator(client: client, model: "sonnet").generate(session: session, template: .standard,
            transcript: transcript([utt("Prognoza na sobotę.")]), context: "", notesLanguage: .polish)
    }
}

@Test func cancellingAnAgentCorrectionKillsTheAgent() async throws {
    let d = try agentDir()
    let c = Corrector(client: try codex("echo $$ > $D/pid\nsleep 60", in: d), assignment: assignment)
    let task = Task { await c.correct(transcript([utt("no to jest test")]), language: .polish) }
    try await Task.sleep(for: .seconds(1))
    let started = ContinuousClock.now
    task.cancel()
    _ = await task.value
    #expect(ContinuousClock.now - started < .seconds(3))
    let pid = try #require(Int32((try String(contentsOf: d.appendingPathComponent("pid"), encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(pid, 0) != 0)
}
