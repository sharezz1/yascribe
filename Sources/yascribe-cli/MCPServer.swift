import Foundation
import YascribeProviders

/// Serwer MCP na stdio (TASK-31): jedna wiadomość JSON-RPC 2.0 w linii wejścia, jedna linia odpowiedzi.
/// Ręczny protokół bez zależności: `handle` jest czystą funkcją (linia → linia albo `nil`), `run` czyta stdin.
/// Nic poza JSON-RPC nie idzie na stdout — logi tylko na stderr.
struct MCPServer {
    let paths: YascribePaths
    let version: String

    static let legacyVersions = ["2025-11-25", "2025-06-18"]
    static let supportedVersions = ["2026-07-28", "2025-11-25", "2025-06-18"]
    static let versionKey = "io.modelcontextprotocol/protocolVersion"
    static let capabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
    static let serverInfoKey = "io.modelcontextprotocol/serverInfo"

    static let instructions = """
    Yascribe meetings, read-only. Tools: list_meetings (search and page through meetings), get_meeting (one meeting \
    as markdown, optionally with the transcript), get_transcript (transcript lines, paged with offset/limit). \
    The user must enable Agent access in Yascribe → Settings; without it every tool returns an error. \
    Nothing is written: the server only reads local files. Transcripts are paged with offset/limit. \
    Dates are ISO 8601 in UTC.
    """

    init(paths: YascribePaths, version: String? = nil) {
        self.paths = paths
        self.version = version ?? Self.bundleVersion()
    }

    /// Wersja serwera: `CFBundleShortVersionString` paczki, gdy CLI leży w `.app`; inaczej `dev`.
    static func bundleVersion() -> String {
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()
        let macos = exe.deletingLastPathComponent()
        let contents = macos.deletingLastPathComponent()
        guard macos.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents" else { return "dev" }
        let plist = contents.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any],
              let version = dict["CFBundleShortVersionString"] as? String, !version.isEmpty else { return "dev" }
        return version
    }

    /// Pętla stdio: EOF kończy pracę kodem 0.
    func run() {
        while let line = readLine(strippingNewline: true) {
            guard let out = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((out + "\n").utf8))
        }
    }

    /// Linia wejścia → linia wyjścia albo `nil` (notyfikacja, pusta linia).
    func handle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else {
            return Self.encode(Self.errorResponse(id: nil, code: -32700, message: "Parse error"))
        }
        // Batch (tablica) nie jest obsługiwany: -32600 z `id: null`.
        guard let object = any as? [String: Any] else {
            return Self.encode(Self.errorResponse(id: nil, code: -32600, message: "Invalid Request"))
        }
        let id = object["id"]
        guard let method = object["method"] as? String else {
            return Self.encode(Self.errorResponse(id: id, code: -32600, message: "Invalid Request"))
        }
        guard object["jsonrpc"] as? String == "2.0" else {
            return Self.encode(Self.errorResponse(id: id, code: -32600, message: "Invalid Request"))
        }
        // Notyfikacja: ma `method`, nie ma klucza `id` (także `notifications/cancelled`) — bez odpowiedzi.
        guard object.keys.contains("id") else { return nil }

        let params = object["params"] as? [String: Any] ?? [:]
        let meta = params["_meta"] as? [String: Any] ?? [:]
        let discover = method == "server/discover"
        // Modern: `_meta` z wersją protokołu; `server/discover` zawsze modern (§13.4).
        let modern = discover || meta[Self.versionKey] != nil

        if modern {
            let requested = meta[Self.versionKey] as? String
            guard requested == "2026-07-28" else {
                return Self.encode(Self.errorResponse(
                    id: id, code: -32022, message: "Unsupported protocol version",
                    data: ["supported": Self.supportedVersions, "requested": requested.map { $0 as Any } ?? NSNull()]))
            }
            guard meta[Self.capabilitiesKey] != nil else {
                return Self.encode(Self.errorResponse(id: id, code: -32602, message: "Invalid params"))
            }
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.legacyVersions.contains(requested) ? requested : "2025-11-25"
            return Self.encode(Self.resultResponse(id: id, result: [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "yascribe", "version": self.version],
                "instructions": Self.instructions,
            ]))
        case "ping":
            // W erze 2026-07-28 `ping` nie istnieje.
            if modern { return Self.encode(Self.errorResponse(id: id, code: -32601, message: "Method not found")) }
            return Self.encode(Self.resultResponse(id: id, result: [:]))
        case "server/discover":
            return Self.encode(Self.resultResponse(id: id, result: Self.modernFields([
                "supportedVersions": Self.supportedVersions,
                "capabilities": ["tools": [:] as [String: Any]],
                "instructions": Self.instructions,
            ], version: self.version, caching: true)))
        case "tools/list":
            let tools = MCPTools.definitions
            var result: [String: Any] = ["tools": tools]
            if modern { result = Self.modernFields(result, version: self.version, caching: true) }
            return Self.encode(Self.resultResponse(id: id, result: result))
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.encode(Self.errorResponse(id: id, code: -32602, message: "Invalid params"))
            }
            if let raw = params["arguments"], !(raw is [String: Any]) {
                return Self.encode(Self.errorResponse(id: id, code: -32602, message: "Invalid params"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard MCPTools.definitions.contains(where: { ($0["name"] as? String) == name }) else {
                return Self.encode(Self.errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)"))
            }
            let outcome = MCPTools.call(name, arguments: arguments, paths: self.paths)
            var result: [String: Any] = [
                "content": [["type": "text", "text": outcome.text]],
                "isError": outcome.isError,
            ]
            if modern { result = Self.modernFields(result, version: self.version, caching: false) }
            return Self.encode(Self.resultResponse(id: id, result: result))
        default:
            return Self.encode(Self.errorResponse(id: id, code: -32601, message: "Method not found"))
        }
    }

    // MARK: Koperta

    static func resultResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    static func errorResponse(id: Any?, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        return ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": error]
    }

    /// Pola wspólne wyników ery 2026-07-28: `resultType`, `_meta.serverInfo`, a dla list — cache.
    static func modernFields(_ result: [String: Any], version: String, caching: Bool) -> [String: Any] {
        var out = result
        out["resultType"] = "complete"
        out["_meta"] = [serverInfoKey: ["name": "yascribe", "version": version]]
        if caching {
            out["ttlMs"] = 3_600_000
            out["cacheScope"] = "private"
        }
        return out
    }

    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
