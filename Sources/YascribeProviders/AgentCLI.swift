import Foundation

/// Agent CLI jako dostawca czatu (TASK-86, spec `2026-11-13-task86-agent-cli-design.md`): `codex exec` albo `claude -p`
/// z logowaniem, które użytkownik ma w CLI (subskrypcja albo klucz w CLI). Yascribe nie trzyma ani nie czyta żadnego klucza.
/// Ochrona przed narzędziami agenta: flagi + bramka wersji Codex (przed wykonaniem), parser fail-closed (drugi detektor).
public enum AgentCLI {
    /// Wersje Codex, na których test „cat /etc/hosts" z flagami `codexLockdown` nie wykonał polecenia (spike §3.3, odbiór T6).
    /// Nowa wersja = powtórz test, dopisz osobnym commitem. Bez tego nowa wersja mogłaby mieć narzędzie spoza listy `--disable`.
    public static let verifiedCodex: Set<String> = ["0.167.2"]

    /// Wyłącza narzędzia Codex (spike §3.3). `-s read-only` sam nie wystarcza: pozwala czytać cały dysk i uruchamiać polecenia.
    static let codexLockdown: [String] = ["shell_tool", "unified_exec", "multi_agent", "apps", "plugins", "image_generation", "hooks",
                                          "computer_use", "browser_use", "in_app_browser", "view_image", "sleep_tool", "tool_suggest",
                                          "skill_search"].flatMap { ["--disable", $0] } + ["-c", #"web_search="disabled""#]

    /// Odbiór procesu i limit czasu wywołania „Check" (status logowania, wersja).
    public static let statusTimeout: Double = 20

    // MARK: argumenty i środowisko

    /// Argumenty i stdin jednego wywołania. `effort` = `nil` → domyślny effort CLI (D4).
    static func invocation(kind: ProviderKind, model: String, system: String, user: String, effort: String?,
                           workdir: URL) -> (arguments: [String], input: String) {
        switch kind {
        case .claudeCLI:
            // Bez `--bare`: wtedy Claude przyjmuje tylko ANTHROPIC_API_KEY, a logowanie w CLI (subskrypcja) przestaje działać.
            var a = ["-p", "--output-format", "json", "--model", model, "--tools", "", "--system-prompt", system,
                     "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence"]
            if let effort { a += ["--effort", effort] }
            return (a, user)
        default:
            // Codex nie ma flagi promptu systemowego: system i user idą razem na stdin.
            var a = ["exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--skip-git-repo-check", "-s", "read-only",
                     "-C", workdir.path] + codexLockdown + ["--json", "-m", model]
            if let effort { a += ["-c", "model_reasoning_effort=\"\(effort)\""] }
            return (a + ["-"], system + "\n\n" + user)
        }
    }

    /// Minimalne, jawne env: bez zmiennych aplikacji (`YASCRIBE_*`, klucze). Bez `USER` Claude nie widzi logowania w pęku (spike).
    static func environment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let home = env["HOME"] ?? NSHomeDirectory()
        let user = env["USER"] ?? NSUserName()
        return ["HOME": home, "USER": user, "LOGNAME": env["LOGNAME"] ?? user, "TMPDIR": env["TMPDIR"] ?? NSTemporaryDirectory(),
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    }

    // MARK: wywołanie

    /// Jedno wywołanie czatu. Anulowanie zadania (albo `limit`) kończy całą grupę procesów agenta.
    public static func chat(provider: Provider, model: String, system: String, user: String, effort: String?,
                            limit: Double? = nil) async throws -> String {
        let kind = provider.api
        let binary = provider.baseURL
        if kind == .codexCLI { try await checkCodexVersion(binary) }
        let workdir = FileManager.default.temporaryDirectory.appendingPathComponent("yascribe-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let call = invocation(kind: kind, model: model, system: system, user: user, effort: effort, workdir: workdir)
        let watchSignIn = kind == .codexCLI
        let stop: @Sendable (String) -> Bool = { line in watchSignIn && codexSignedOut(line) }
        let out = try await AgentProcess.run(executable: binary, arguments: call.arguments, environment: environment(),
                                             directory: workdir, input: Data(call.input.utf8), limit: limit, stopEarly: stop)
        if out.timedOut { throw ProviderError.agentFailed("\(name(kind)) didn't answer within \(Int(limit ?? 0)) s.") }
        if out.stoppedEarly { throw ProviderError.agentNotSignedIn(signInHint(kind)) }
        if out.overflowed { throw ProviderError.agentFailed("\(name(kind)) sent more output than Yascribe accepts.") }
        let reply = kind == .claudeCLI ? try parseClaude(out.stdout, exitCode: out.status, stderr: out.stderrText)
                                       : try parseCodex(out.stdout, exitCode: out.status, stderr: out.stderrText)
        let clean = ThinkingStripper.clean(reply, orphanClosers: false)
        guard !clean.isEmpty else { throw ProviderError.badResponse("empty reply") }
        return clean
    }

    static func name(_ kind: ProviderKind) -> String { kind == .claudeCLI ? "Claude Code" : "Codex" }

    public static func signInHint(_ kind: ProviderKind) -> String {
        kind == .claudeCLI ? "Claude Code isn't signed in. Run `claude` in Terminal and sign in."
                           : "Codex isn't signed in. Run `codex login` in Terminal."
    }

    /// Codex bez logowania ponawia ~16 s (spike §4.3): pierwszy błąd 401 kończy proces od razu.
    static func codexSignedOut(_ line: String) -> Bool {
        line.contains(#""type":"error""#) && (line.contains("401") || line.contains("Unauthorized"))
    }

    // MARK: parsery (fail-closed)

    /// Sukces tylko przy kodzie 0, poprawnym JSONL, dokładnie jednym `turn.completed` jako ostatnim `turn.*`, bez `error`/`turn.failed`
    /// i bez elementu innego niż `agent_message`. Odpowiedź = ostatni `agent_message` (pierwszy bywa wstępem).
    static func parseCodex(_ stdout: Data, exitCode: Int32, stderr: String = "") throws -> String {
        var reply: String?
        var completed = 0
        var lastTurn: String?
        for raw in String(decoding: stdout, as: UTF8.self).split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let type = obj["type"] as? String else {
                throw ProviderError.badResponse("Codex sent output that isn't JSON.")
            }
            if type == "error" || type == "turn.failed" {
                let msg = (obj["message"] as? String) ?? ((obj["error"] as? [String: Any])?["message"] as? String) ?? type
                throw ProviderError.agentFailed("Codex: \(msg.prefix(300))")
            }
            if type.hasPrefix("turn.") { lastTurn = type }
            if type == "turn.completed" { completed += 1 }
            if type.hasPrefix("item.") {
                guard let item = obj["item"] as? [String: Any] else { throw ProviderError.badResponse("Codex sent a malformed item.") }
                guard completed == 0 else { throw ProviderError.agentFailed("Codex sent output after its turn ended.") }
                let itemType = item["type"] as? String ?? "?"
                guard itemType == "agent_message" else { throw ProviderError.agentUsedTool(itemType) }
                if type == "item.completed", let text = item["text"] as? String { reply = text }
            }
        }
        guard exitCode == 0 else { throw ProviderError.agentFailed("Codex exited with code \(exitCode). \(stderr)") }
        guard completed == 1, lastTurn == "turn.completed" else { throw ProviderError.agentFailed("Codex didn't finish its turn.") }
        guard let reply else { throw ProviderError.badResponse("empty reply") }
        return reply
    }

    /// Sukces tylko przy kodzie 0, jednym obiekcie `type: result`, `is_error == false`, `num_turns == 1`, pustych `permission_denials`
    /// i `stop_reason == end_turn` (`max_tokens` = `replyCutOff`).
    static func parseClaude(_ stdout: Data, exitCode: Int32, stderr: String = "") throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] else {
            if exitCode != 0 { throw ProviderError.agentFailed("Claude Code exited with code \(exitCode). \(stderr)") }
            throw ProviderError.badResponse("Claude Code sent output that isn't JSON.")
        }
        let result = obj["result"] as? String ?? ""
        // Odmowa narzędzia ma pierwszeństwo także w odpowiedzi z błędem: to naruszenie terminalne, nie zwykła porażka.
        if let denials = obj["permission_denials"] as? [Any], !denials.isEmpty { throw ProviderError.agentUsedTool("permission denials") }
        if obj["is_error"] as? Bool != false {
            if result.localizedCaseInsensitiveContains("not logged in") { throw ProviderError.agentNotSignedIn(signInHint(.claudeCLI)) }
            throw ProviderError.agentFailed("Claude Code: \(result.prefix(300))")
        }
        guard exitCode == 0 else { throw ProviderError.agentFailed("Claude Code exited with code \(exitCode). \(stderr)") }
        guard obj["type"] as? String == "result" else { throw ProviderError.badResponse("Claude Code sent no result.") }
        // Brak tablicy odmów to brak dowodu, że narzędzi nie było: fail-closed.
        guard let denials = obj["permission_denials"] as? [Any] else { throw ProviderError.badResponse("Claude Code sent no permission_denials.") }
        guard (obj["num_turns"] as? Int) == 1, denials.isEmpty else { throw ProviderError.agentUsedTool("turns: \(obj["num_turns"] ?? "?")") }
        switch obj["stop_reason"] as? String {
        case "end_turn": return result
        case "max_tokens": throw ProviderError.replyCutOff
        case let other: throw ProviderError.agentFailed("Claude Code stopped early (\(other ?? "no reason")).")
        }
    }

    // MARK: wersja, logowanie, modele

    private static let versions = VersionCache()

    /// Bramka D7: Codex spoza `verifiedCodex` nie dostaje transkryptu. Wynik w pamięci na ścieżkę i datę zmiany binarki.
    static func checkCodexVersion(_ binary: URL) async throws {
        let key = fileKey(binary)
        let version: String
        if let cached = versions.get(key) { version = cached } else {
            let out = try await AgentProcess.run(executable: binary, arguments: ["--version"], environment: environment(),
                                                 directory: FileManager.default.temporaryDirectory, input: Data(), limit: statusTimeout)
            guard out.status == 0, !out.timedOut else { throw ProviderError.agentFailed("Couldn't read the Codex version. \(out.stderrText)") }
            version = codexVersion(String(decoding: out.stdout, as: UTF8.self)) ?? "?"
            versions.set(key, version)
        }
        guard verifiedCodex.contains(version) else {
            throw ProviderError.agentFailed("Codex \(version) isn't verified with Yascribe yet. Verified: \(verifiedCodex.sorted().joined(separator: ", ")).")
        }
    }

    /// Klucz cache wersji: plik, który naprawdę się uruchomi (cel dowiązań), z datą, rozmiarem i i-węzłem — aktualizacja
    /// celu bez zmiany samego dowiązania (Homebrew, npm) unieważnia wynik.
    static func fileKey(_ binary: URL) -> String {
        let real = binary.resolvingSymlinksInPath().path
        let a = (try? FileManager.default.attributesOfItem(atPath: real)) ?? [:]
        let mtime = (a[.modificationDate] as? Date).map { "\($0.timeIntervalSince1970)" } ?? "-"
        return [real, mtime, "\(a[.size] ?? "-")", "\(a[.systemFileNumber] ?? "-")"].joined(separator: "|")
    }

    /// `codex-cli 0.167.2` → `0.167.2`.
    static func codexVersion(_ text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).last.map(String.init).flatMap { $0.first?.isNumber == true ? $0 : nil }
    }

    /// „Check": czy CLI jest zalogowane (metoda bez znaczenia: subskrypcja albo klucz w CLI). Treść statusu zawiera e-mail konta,
    /// więc do UI idzie wyłącznie nasz komunikat.
    public static func verify(provider: Provider, timeout: Double = statusTimeout) async -> ProviderCheck {
        let kind = provider.api
        guard FileManager.default.isExecutableFile(atPath: provider.baseURL.path) else {
            return .failed("\(name(kind)) not found at \(provider.baseURL.path).")
        }
        do {
            if kind == .codexCLI { try await checkCodexVersion(provider.baseURL) }
            let args = kind == .claudeCLI ? ["auth", "status"] : ["login", "status"]
            let out = try await AgentProcess.run(executable: provider.baseURL, arguments: args, environment: environment(),
                                                 directory: FileManager.default.temporaryDirectory, input: Data(), limit: timeout)
            guard !out.timedOut else { return .failed("\(name(kind)) didn't answer.") }
            return signedIn(kind: kind, status: out.status, stdout: out.stdout) ? .verified(models: models(for: kind).count)
                                                                              : .failed(signInHint(kind))
        } catch {
            return .failed(ProviderCheck.describe(error))
        }
    }

    /// Codex: kod 0. Claude: kod 0 i `loggedIn == true` w JSON (czytamy tylko to pole).
    static func signedIn(kind: ProviderKind, status: Int32, stdout: Data) -> Bool {
        guard status == 0 else { return false }
        guard kind == .claudeCLI else { return true }
        return ((try? JSONSerialization.jsonObject(with: stdout)) as? [String: Any])?["loggedIn"] as? Bool == true
    }

    /// Stała lista (D5), bez sieci; pierwszy = domyślny. Pole modelu w presecie przyjmie też inną nazwę.
    public static func models(for kind: ProviderKind) -> [ModelInfo] {
        let ids: [String] = switch kind {
        case .codexCLI: ["gpt-6.1-terra", "gpt-6.1-sol", "gpt-6-astra"]
        case .claudeCLI: ["sonnet", "haiku", "opus"]
        default: []
        }
        return ids.map { ModelInfo(id: $0, inputModalities: ["text"], outputModalities: ["text"]) }
    }

    /// Ścieżka z pola arkusza → `file://` binarki (istnieje i jest wykonywalna) albo powód.
    public static func binaryURL(from text: String) -> Result<URL, ProviderError> {
        let path = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return .failure(.agentFailed("Enter the full path, e.g. /opt/homebrew/bin/codex.")) }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &dir), !dir.boolValue,
              FileManager.default.isExecutableFile(atPath: path) else { return .failure(.agentFailed("No program at \(path).")) }
        return .success(URL(fileURLWithPath: path))
    }

    /// Domyślna ścieżka w arkuszu: pierwsza istniejąca.
    public static func defaultBinary(_ kind: ProviderKind, home: String = NSHomeDirectory()) -> String {
        let name = kind == .claudeCLI ? "claude" : "codex"
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"].map { $0 + "/" + name }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }
}

private final class VersionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: String] = [:]
    func get(_ k: String) -> String? { lock.withLock { map[k] } }
    func set(_ k: String, _ v: String) { lock.withLock { map[k] = v } }
}
