import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import yascribe_cli
@testable import YascribeNotes

// MARK: - Fikstury

private let runID = "2026-11-19T10-00-00Z-abcd"
private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

private func dataDir() throws -> YascribePaths {
    let root = tempDir()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return YascribePaths(root: root)
}

private func saveSettings(_ paths: YascribePaths, _ change: (inout GlobalSettings) -> Void = { _ in }) throws {
    var settings = GlobalSettings()
    change(&settings)
    try JSONFile.save(settings, to: paths.settings)
}

private func writeJournal(_ session: URL, wallClock: Date, seconds: Double, mutes: [(Double, Double)] = []) throws {
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let journal = try SessionJournal(url: SessionDirectory(url: session).journalURL)
    try journal.append(.sessionStarted(hostTime: 0, timebase: Timebase(numer: 1, denom: 1), wallClock: wallClock))
    try journal.append(.trackOpened("system", hostTime: 0, sampleRate: 48_000, channels: 2, deviceUID: "spk"))
    try journal.append(.trackFirstSample("system", hostTime: 1_000_000_000))
    for (start, end) in mutes {
        try journal.append(.trackMute("system", muted: true, frameIndex: Int(start * 48_000), hostTime: 2_000_000_000))
        try journal.append(.trackMute("system", muted: false, frameIndex: Int(end * 48_000), hostTime: 3_000_000_000))
    }
    try journal.append(.trackClosed("system", frames: Int(seconds * 48_000), hostTime: 4_000_000_000))
    try journal.append(.sessionEnded(reason: "stopped", hostTime: 5_000_000_000))
    try journal.close()
}

@discardableResult
private func makeSession(_ paths: YascribePaths, id: String, wallClock: Date = startedAt, seconds: Double = 600,
                         raw: [Utterance] = [], corrected: [Utterance]? = nil,
                         myNotes: String = "", noteSummary: NoteSummary? = nil, meta: NoteMeta? = nil,
                         mutes: [(Double, Double)] = [], speakers: SpeakerDiarization? = nil,
                         run: String = runID) throws -> URL {
    let session = paths.sessions.appendingPathComponent(id)
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    try writeJournal(session, wallClock: wallClock, seconds: seconds, mutes: mutes)
    let dir = RunDirectory(session: session, runID: run)
    try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
    if !raw.isEmpty { try JSONFile.save(transcript(raw), to: dir.transcript) }
    if let corrected {
        try JSONFile.save(CorrectedTranscript(transcript: transcript(corrected), model: "m", batches: 1,
                                              failedBatches: 0, rejectedLines: 0), to: dir.corrected)
    }
    if let speakers { try JSONFile.save(speakers, to: dir.speakers) }
    let store = NotesStore(session: session)
    if !myNotes.isEmpty { _ = try store.writeMyNotes(myNotes) }
    if let noteSummary { _ = try store.writeSummary(noteSummary) }
    if let meta { _ = try store.updateMeta { $0 = meta } }
    return session
}

private func speakersFixture(names: [String: String]? = ["voice": "Anna"], fingerprint: String? = nil) -> SpeakerDiarization {
    var speakers = SpeakerDiarization(version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil,
                                      threshold: nil, minClusterSeconds: nil, audioFingerprint: fingerprint, createdAt: nil,
                                      segments: [.init(speaker: "voice", start: 0, end: 20)])
    speakers.names = names
    return speakers
}

private func noteSummary(_ markdown: String, speakers: [String: String]? = nil,
                         digest: String? = nil, model: String = "test-model") -> NoteSummary {
    var summary = NoteSummary(title: nil, markdown: markdown, templateID: "t", model: model, context: "c",
                              generatedAt: Date(timeIntervalSince1970: 0))
    summary.speakers = speakers
    summary.speakersDigest = digest
    return summary
}

// MARK: - Ramki

private func modernMeta() -> [String: Any] {
    ["io.modelcontextprotocol/protocolVersion": "2026-07-28",
     "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any]]
}

private func send(_ server: MCPServer, _ object: [String: Any]) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: object)
    let line = try #require(server.handle(String(decoding: data, as: UTF8.self)))
    return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
}

private func sendRaw(_ server: MCPServer, _ line: String) throws -> [String: Any] {
    let out = try #require(server.handle(line))
    return try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
}

private func request(_ server: MCPServer, _ method: String, params: [String: Any]? = nil,
                     id: Any = 1) throws -> [String: Any] {
    var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
    if let params { object["params"] = params }
    return try send(server, object)
}

private func toolCall(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:],
                      id: Any = 1, modern: Bool = false) throws -> [String: Any] {
    var params: [String: Any] = ["name": tool, "arguments": arguments]
    if modern { params["_meta"] = modernMeta() }
    return try request(server, "tools/call", params: params, id: id)
}

private func call(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:],
                  modern: Bool = false) throws -> (text: String, isError: Bool) {
    let response = try toolCall(server, tool, arguments, modern: modern)
    let result = try #require(response["result"] as? [String: Any])
    let content = try #require(result["content"] as? [[String: Any]])
    let text = try #require(content.first?["text"] as? String)
    let isError = try #require(result["isError"] as? Bool)
    return (text, isError)
}

private func json(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func errorCode(_ response: [String: Any]) -> Int? {
    (response["error"] as? [String: Any])?["code"] as? Int
}

/// Rekurencyjna migawka katalogu: ścieżka → „dir” albo bajty pliku (base64).
private func snapshot(_ url: URL) throws -> [String: String] {
    var out: [String: String] = [:]
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return out }
    for case let item as URL in walker {
        let key = item.path.replacingOccurrences(of: url.path, with: "")
        if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            out[key] = "dir"
        } else {
            out[key] = (try Data(contentsOf: item)).base64EncodedString()
        }
    }
    return out
}

// MARK: - Protokół

@Test func initializeEchoesSupportedLegacyVersionsAndFallsBack() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "9.9.9")
    for version in ["2025-11-25", "2025-06-18"] {
        let response = try request(server, "initialize",
                                   params: ["protocolVersion": version, "capabilities": [:] as [String: Any],
                                            "clientInfo": ["name": "c", "version": "1"]])
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == version)
        #expect(result["instructions"] as? String != nil)
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        #expect((capabilities["tools"] as? [String: Any])?["listChanged"] as? Bool == false)
        let info = try #require(result["serverInfo"] as? [String: Any])
        #expect(info["name"] as? String == "yascribe")
        #expect(info["version"] as? String == "9.9.9")
        // Legacy: bez koperty nowej ery.
        #expect(result["resultType"] == nil)
        #expect(result["_meta"] == nil)
    }
    // Wersja spoza obsługiwanych (także wycofane 2024-11-05) → 2025-11-25.
    for version in ["2024-11-05", "1900-01-01"] {
        let response = try request(server, "initialize", params: ["protocolVersion": version])
        #expect((response["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25")
    }
}

@Test func notificationGetsNoResponse() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#) == nil)
    #expect(server.handle("") == nil)
}

@Test func pingReturnsEmptyResult() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    let response = try request(server, "ping")
    let result = try #require(response["result"] as? [String: Any])
    #expect(result.isEmpty)
    #expect(response["id"] as? Int == 1)
    #expect(response["jsonrpc"] as? String == "2.0")
}

@Test func discoverAdvertisesVersionsAndCacheHints() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "9.9.9")
    let response = try request(server, "server/discover", params: ["_meta": modernMeta()])
    let result = try #require(response["result"] as? [String: Any])
    #expect(result["resultType"] as? String == "complete")
    #expect(result["supportedVersions"] as? [String] == ["2026-07-28", "2025-11-25", "2025-06-18"])
    #expect(result["ttlMs"] as? Int == 3_600_000)
    #expect(result["cacheScope"] as? String == "private")
    #expect(result["instructions"] as? String != nil)
    let meta = try #require(result["_meta"] as? [String: Any])
    let info = try #require(meta["io.modelcontextprotocol/serverInfo"] as? [String: Any])
    #expect(info["name"] as? String == "yascribe")
    #expect(info["version"] as? String == "9.9.9")
    // Modern tools/list niesie te same wskazówki pamięci podręcznej.
    let list = try request(server, "tools/list", params: ["_meta": modernMeta()])
    let listed = try #require(list["result"] as? [String: Any])
    #expect(listed["ttlMs"] as? Int == 3_600_000)
    #expect(listed["cacheScope"] as? String == "private")
    #expect((listed["tools"] as? [[String: Any]])?.count == 3)
    // Legacy tools/list bez koperty nowej ery.
    let legacy = try request(server, "tools/list")
    #expect((legacy["result"] as? [String: Any])?["resultType"] == nil)
    #expect((legacy["result"] as? [String: Any])?["ttlMs"] == nil)
}

@Test func modernUnknownVersionIsRejected() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    var meta = modernMeta()
    meta["io.modelcontextprotocol/protocolVersion"] = "1900-01-01"
    let response = try request(server, "tools/list", params: ["_meta": meta])
    #expect(errorCode(response) == -32022)
    let error = try #require(response["error"] as? [String: Any])
    #expect(error["message"] as? String == "Unsupported protocol version")
    let data = try #require(error["data"] as? [String: Any])
    #expect(data["supported"] as? [String] == ["2026-07-28", "2025-11-25", "2025-06-18"])
    #expect(data["requested"] as? String == "1900-01-01")
}

@Test func modernRequestNeedsClientCapabilities() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    let response = try request(server, "tools/list",
                               params: ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]])
    #expect(errorCode(response) == -32602)
}

@Test func modernPingIsGone() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    let response = try request(server, "ping", params: ["_meta": modernMeta()])
    #expect(errorCode(response) == -32601)
}

@Test func unknownMethodBadJSONAndBatchAreProtocolErrors() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let server = MCPServer(paths: paths, version: "test")
    #expect(errorCode(try request(server, "no/such/method", id: 7)) == -32601)
    #expect((try request(server, "no/such/method", id: 7))["id"] as? Int == 7)

    let broken = try sendRaw(server, "{not json")
    #expect(errorCode(broken) == -32700)
    #expect(broken["id"] is NSNull)

    let batch = try sendRaw(server, #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
    #expect(errorCode(batch) == -32600)
    #expect(batch["id"] is NSNull)

    // Koperta: brak `method` albo złe `jsonrpc` → -32600 z `id` koperty, gdy jest.
    let noMethod = try send(server, ["jsonrpc": "2.0", "id": 3])
    #expect(errorCode(noMethod) == -32600)
    #expect(noMethod["id"] as? Int == 3)
    let badEnvelope = try send(server, ["jsonrpc": "1.0", "id": "x", "method": "ping"])
    #expect(errorCode(badEnvelope) == -32600)
    #expect(badEnvelope["id"] as? String == "x")
    // `id` wraca bez zmiany typu.
    #expect((try request(server, "ping", id: "tekst"))["id"] as? String == "tekst")
}

@Test func unknownToolAndMalformedCallAreInvalidParams() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let server = MCPServer(paths: paths, version: "test")
    #expect(errorCode(try toolCall(server, "no_such_tool")) == -32602)
    #expect(errorCode(try request(server, "tools/call", params: ["arguments": [:] as [String: Any]])) == -32602)
    #expect(errorCode(try request(server, "tools/call",
                                  params: ["name": "list_meetings", "arguments": "nie-obiekt"])) == -32602)
    // Zły argument znanego narzędzia to wynik `isError`, nie błąd protokołu.
    let bad = try call(server, "list_meetings", ["limit": 500])
    #expect(bad.isError)
    let badVersion = try call(server, "get_transcript", ["id": "x", "version": "inna"])
    #expect(badVersion.isError)
}

@Test func outputIsOneLinePerMessage() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    try makeSession(paths, id: "s1", raw: [utt("pierwsza", .me, at: 0), utt("druga", .them, at: 5)])
    let server = MCPServer(paths: paths, version: "test")
    let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                           "params": ["name": "get_meeting",
                                                                      "arguments": ["id": "s1", "include_transcript": true]]])
    let line = try #require(server.handle(String(decoding: data, as: UTF8.self)))
    #expect(!line.contains("\n"))
    #expect(!line.contains("\r"))
}

// MARK: - Bramka zgody

@Test func accessGateCoversAllThreeToolsOnOneServer() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try makeSession(paths, id: "s1", raw: [utt("zwykły tekst", .me, at: 0)], myNotes: "control-value-123")
    let server = MCPServer(paths: paths, version: "test")
    let tools: [(String, [String: Any])] = [
        ("list_meetings", ["query": "control-value-123"]),
        ("get_meeting", ["id": "s1"]),
        ("get_transcript", ["id": "s1"]),
    ]
    func expectOff(_ label: String) throws {
        for (name, arguments) in tools {
            let response = try call(server, name, arguments)
            #expect(response.isError, "\(label): \(name)")
            #expect(response.text == MCPTools.accessOff, "\(label): \(name)")
            #expect(!response.text.contains("control-value-123"), "\(label): \(name)")
        }
    }
    // Brak pliku ustawień = brak zgody.
    try expectOff("brak settings.json")
    try saveSettings(paths) { $0.agentAccess = nil }
    try expectOff("nil")
    try saveSettings(paths) { $0.agentAccess = false }
    try expectOff("false")

    try saveSettings(paths) { $0.agentAccess = true }
    let meeting = try call(server, "get_meeting", ["id": "s1"])
    #expect(!meeting.isError)
    #expect(meeting.text.contains("control-value-123"))
    let listed = try call(server, "list_meetings", ["query": "control-value-123"])
    #expect(!listed.isError)
    #expect(try json(listed.text)["total"] as? Int == 1)
    let lines = try call(server, "get_transcript", ["id": "s1"])
    #expect(!lines.isError)

    // Ta sama instancja: wyłączenie zgody odcina dane od razu.
    try saveSettings(paths) { $0.agentAccess = false }
    try expectOff("po wyłączeniu")
    // Usunięty i uszkodzony plik też znaczą „wyłączone”.
    try FileManager.default.removeItem(at: paths.settings)
    try expectOff("po usunięciu")
    try "nie json".write(to: paths.settings, atomically: true, encoding: .utf8)
    try expectOff("po uszkodzeniu")
}

// MARK: - list_meetings

@Test func listMeetingsNewestFirstWithPagingAndFolder() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    try JSONFile.save(FoldersFile(folders: [MeetingFolder(id: "f1", name: "Zespół")]), to: paths.folders)
    try makeSession(paths, id: "starsze", wallClock: startedAt, raw: [utt("a", .me, at: 0)])
    try makeSession(paths, id: "nowsze", wallClock: startedAt.addingTimeInterval(3_600), raw: [utt("b", .me, at: 0)],
                    noteSummary: noteSummary("notatka"), meta: {
                        var meta = NoteMeta()
                        meta.folderID = "f1"
                        return meta
                    }())
    let server = MCPServer(paths: paths, version: "test")

    let all = try json(try call(server, "list_meetings").text)
    let meetings = try #require(all["meetings"] as? [[String: Any]])
    #expect(meetings.map { $0["id"] as? String } == ["nowsze", "starsze"])
    #expect(all["total"] as? Int == 2)
    #expect(meetings.first?["folder"] as? String == "Zespół")
    #expect(meetings.first?["hasSummary"] as? Bool == true)
    #expect(meetings.first?["transcriptVersion"] as? String == "original")
    #expect(meetings.first?["durationMinutes"] as? Int == 10)

    // Stronicowanie: limit/offset liczą się od pełnej listy.
    let page = try json(try call(server, "list_meetings", ["limit": 1, "offset": 1]).text)
    #expect(page["total"] as? Int == 2)
    #expect((page["meetings"] as? [[String: Any]])?.first?["id"] as? String == "starsze")

    // Folder po nazwie (także inna wielkość liter); nieznany folder = isError.
    let folder = try call(server, "list_meetings", ["folder": "zespół"])
    #expect(!folder.isError)
    #expect(try json(folder.text)["total"] as? Int == 1)
    #expect(try call(server, "list_meetings", ["folder": "nie ma"]).isError)
    // Pusta strona za końcem listy nie jest błędem.
    let beyond = try json(try call(server, "list_meetings", ["offset": 10]).text)
    #expect((beyond["meetings"] as? [[String: Any]])?.isEmpty == true)
}

@Test func listMeetingsSearchesCorrectedTranscriptThroughReplacement() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    try JSONFile.save(UserDictionary(terms: [DictionaryTerm("Jan Kowalski", aliases: [DictionaryAlias("jasiu")])]),
                      to: paths.dictionary)
    try makeSession(paths, id: "s1", raw: [utt("jasiu mówił o budżecie", .them, at: 0)],
                    corrected: [utt("jasiu mówił o budżecie", .them, at: 0)])
    let server = MCPServer(paths: paths, version: "test")
    // „Kowalski” jest tylko po Replacement (słownik: jasiu → Jan Kowalski), nie w surowym tekście.
    let hit = try json(try call(server, "list_meetings", ["query": "Kowalski"]).text)
    #expect(hit["total"] as? Int == 1)
    let miss = try json(try call(server, "list_meetings", ["query": "Kowalski nie ma"]).text)
    #expect(miss["total"] as? Int == 0)
    // Trafienie po notatkach (s2) i po transkrypcie (s1) — każde z osobna.
    try makeSession(paths, id: "s2", raw: [utt("x", .me, at: 0)], myNotes: "ważne: budżet")
    let notesOnly = try json(try call(server, "list_meetings", ["query": "budżet"]).text)
    #expect(notesOnly["total"] as? Int == 1)
    #expect((notesOnly["meetings"] as? [[String: Any]])?.first?["id"] as? String == "s2")
    let transcriptHit = try json(try call(server, "list_meetings", ["query": "mówił"]).text)
    #expect(transcriptHit["total"] as? Int == 1)
    #expect((transcriptHit["meetings"] as? [[String: Any]])?.first?["id"] as? String == "s1")
}

@Test func listMeetingsSkipsNonSessionsAndSymlinksAndHonoursRecordingsPath() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let elsewhere = tempDir()
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try saveSettings(paths) {
        $0.agentAccess = true
        $0.recordingsPath = elsewhere.path
    }
    try makeSession(paths, id: "w-domyslnym", raw: [utt("a", .me, at: 0)])
    // Katalog bez journal.jsonl nie jest spotkaniem.
    let notASession = paths.sessions.appendingPathComponent("smieci")
    try FileManager.default.createDirectory(at: notASession, withIntermediateDirectories: true)
    // Nagrania z recordingsPath są widoczne, a domyślny katalog przy recordingsPath jest ignorowany.
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    try writeJournal(elsewhere.appendingPathComponent("poza"), wallClock: startedAt, seconds: 60)
    try JSONFile.save(transcript([utt("b", .me, at: 0)]),
                      to: RunDirectory(session: elsewhere.appendingPathComponent("poza"), runID: runID).transcript)
    let server = MCPServer(paths: paths, version: "test")
    let listed = try json(try call(server, "list_meetings").text)
    #expect(listed["total"] as? Int == 1)
    #expect((listed["meetings"] as? [[String: Any]])?.first?["id"] as? String == "poza")

    // Dowiązanie do spotkania jest pomijane na liście i odrzucane jako `id`.
    try saveSettings(paths) { $0.agentAccess = true }
    let linked = paths.sessions.appendingPathComponent("dowiazanie")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: paths.sessions.appendingPathComponent("w-domyslnym"))
    let local = try json(try call(server, "list_meetings").text)
    #expect(local["total"] as? Int == 1)
    #expect((local["meetings"] as? [[String: Any]])?.first?["id"] as? String == "w-domyslnym")
    #expect(try call(server, "get_meeting", ["id": "dowiazanie"]).isError)
    #expect(try call(server, "get_transcript", ["id": "dowiazanie"]).isError)
}

// MARK: - get_transcript

@Test func getTranscriptPagesCorrectedWithFallbackAndSpeakerNames() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let session = try makeSession(paths, id: "s1",
                                  raw: [utt("surowa", .them, at: 0), utt("druga", .them, at: 10)],
                                  corrected: [utt("poprawiona", .them, at: 0), utt("druga", .them, at: 10)])
    // Odczyt mówców jak w aplikacji: dziennik + rozmiar system.caf.
    try Data(repeating: 1, count: 128).write(to: session.appendingPathComponent("system.caf"))
    let fingerprint = try #require(SpeakerDiarization.audioFingerprint(session: session))
    let run = RunDirectory(session: session, runID: runID)
    try JSONFile.save(speakersFixture(fingerprint: fingerprint), to: run.speakers)

    let server = MCPServer(paths: paths, version: "test")
    let first = try call(server, "get_transcript", ["id": "s1", "limit": 1])
    #expect(!first.isError)
    #expect(first.text == "Lines 1–1 of 2 · version: corrected\n[0:00:00] Anna: poprawiona\nNext: offset 1")
    let second = try call(server, "get_transcript", ["id": "s1", "offset": 1])
    #expect(second.text == "Lines 2–2 of 2 · version: corrected\n[0:00:10] Anna: druga")
    // `version: original` i brak poprawionego dają surowy transkrypt.
    let original = try call(server, "get_transcript", ["id": "s1", "version": "original", "limit": 1])
    #expect(original.text.contains("version: original") && original.text.contains("surowa"))
    try makeSession(paths, id: "bez-korekty", raw: [utt("tylko surowa", .me, at: 0)])
    let fallback = try call(server, "get_transcript", ["id": "bez-korekty"])
    #expect(fallback.text.contains("version: original") && fallback.text.contains("tylko surowa"))

    // Inny odcisk audio (zmieniony system.caf) = brak imion, jak w UI po podmianie nagrania.
    try Data(repeating: 2, count: 200).write(to: session.appendingPathComponent("system.caf"))
    let renamed = try call(server, "get_transcript", ["id": "s1", "limit": 1])
    #expect(renamed.text.contains("Them: poprawiona"))

    // Granice stron: poza zakresem = isError, brak transkryptu = isError.
    #expect(try call(server, "get_transcript", ["id": "s1", "offset": 2]).isError)
    #expect(try call(server, "get_transcript", ["id": "s1", "offset": -1]).isError)
    #expect(try call(server, "get_transcript", ["id": "s1", "limit": 0]).isError)
    #expect(try call(server, "get_transcript", ["id": "s1", "limit": 2001]).isError)
    #expect(try call(server, "get_transcript", ["id": "s1", "offset": 1e300]).text.contains("must be between"))
    try makeSession(paths, id: "bez-transkryptu")
    #expect(try call(server, "get_transcript", ["id": "bez-transkryptu"]).text == "No transcript yet")
}

@Test func getTranscriptEmptyTranscriptReportsZeroLines() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let session = try makeSession(paths, id: "puste")
    try JSONFile.save(transcript([]), to: RunDirectory(session: session, runID: runID).transcript)
    let server = MCPServer(paths: paths, version: "test")
    let empty = try call(server, "get_transcript", ["id": "puste"])
    #expect(empty.text == "Lines 0 of 0")
    // offset ≥ total przy niepustym transkrypcie: czytelny komunikat.
    try makeSession(paths, id: "jedna", raw: [utt("x", .me, at: 0)])
    #expect(try call(server, "get_transcript", ["id": "jedna", "offset": 1]).text == "No lines at offset 1 (total 1)")
}

@Test func getTranscriptShowsManualEditsLikeTheApp() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let session = try makeSession(paths, id: "edycja", raw: [utt("zle slowo", .them, at: 2)], corrected: [utt("złe słowo", .them, at: 2)])
    try TranscriptEdits(edits: [.init(index: 0, speaker: .them, start: 2, text: "dobre słowo")])
        .save(run: RunDirectory(session: session, runID: runID))
    let server = MCPServer(paths: paths, version: "test")
    #expect(try call(server, "get_transcript", ["id": "edycja"]).text.contains("Them: dobre słowo"))
    #expect(try call(server, "get_transcript", ["id": "edycja", "version": "original"]).text.contains("Them: dobre słowo"))
}

// TASK-119: ukryta wypowiedź (rozmowa z tła) nie wychodzi przez MCP — ani w transkrypcie, ani w wyszukiwaniu.
@Test func hiddenUtterancesNeverLeaveThroughMCP() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let session = try makeSession(paths, id: "tlo", raw: [utt("hintergrund gerede", .me, at: 1), utt("właściwa treść", .them, at: 3)],
                                  corrected: [utt("Hintergrund Gerede.", .me, at: 1), utt("Właściwa treść.", .them, at: 3)])
    try TranscriptEdits(hidden: [.init(speaker: .me, start: 1)]).save(run: RunDirectory(session: session, runID: runID))
    let server = MCPServer(paths: paths, version: "test")
    for version in ["corrected", "original"] {
        let text = try call(server, "get_transcript", ["id": "tlo", "version": version]).text
        #expect(!text.lowercased().contains("hintergrund"))
        #expect(text.lowercased().contains("właściwa treść"))
        #expect(text.contains("Lines 1–1 of 1"))
    }
    let meeting = try call(server, "get_meeting", ["id": "tlo", "include_transcript": true]).text
    #expect(!meeting.lowercased().contains("hintergrund"))
    #expect(meeting.contains("Właściwa treść."))
    let hit = try json(try call(server, "list_meetings", ["query": "Gerede"]).text)
    #expect(hit["total"] as? Int == 0)
    #expect(try json(try call(server, "list_meetings", ["query": "Właściwa"]).text)["total"] as? Int == 1)
}

// MARK: - get_meeting

@Test func getMeetingRendersMarkdownWithResolvedSpeakersAndTruncates() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    try JSONFile.save(FoldersFile(folders: [MeetingFolder(id: "f1", name: "Zespół")]), to: paths.folders)
    let speakers = speakersFixture()
    var meta = NoteMeta(manualTitle: "Budżet")
    meta.folderID = "f1"
    try makeSession(paths, id: "s1",
                    raw: [utt("surowa", .them, at: 0)],
                    corrected: [utt("poprawiona", .them, at: 0)],
                    myNotes: "moja notatka",
                    noteSummary: noteSummary("## Wnioski\n[[S1]] mówi", speakers: ["1": "voice"],
                                             digest: speakers.segmentsDigest),
                    meta: meta, mutes: [(1, 3)],
                    speakers: speakers)
    let server = MCPServer(paths: paths, version: "test")
    let meeting = try call(server, "get_meeting", ["id": "s1"])
    #expect(!meeting.isError)
    #expect(meeting.text.hasPrefix("# Budżet\n"))
    #expect(meeting.text.contains("- Date: 2023-11-14T22:13:20Z · Duration: 10 min · Folder: Zespół"))
    #expect(meeting.text.contains("- Transcript: corrected · Summary model: test-model"))
    #expect(meeting.text.contains("## Summary\n## Wnioski\nAnna mówi"))
    #expect(meeting.text.contains("## My notes\nmoja notatka"))
    #expect(!meeting.text.contains("## Transcript"))
    let withTranscript = try call(server, "get_meeting", ["id": "s1", "include_transcript": true])
    #expect(withTranscript.text.contains("## Transcript\n[0:00:00] Anna: poprawiona"))
    // Linie wyciszenia pochodzą z dziennika, jak w „Copy” w UI.
    #expect(withTranscript.text.contains("[0:00:01] System audio muted 0:01–0:03"))

    // Ponad 2000 linii: obcięcie z podpowiedzią o stronach.
    let many = (0..<2001).map { utt("linia \($0)", .me, at: Double($0)) }
    try makeSession(paths, id: "dlugie", raw: many)
    let long = try call(server, "get_meeting", ["id": "dlugie", "include_transcript": true])
    #expect(long.text.contains("… transcript truncated, use get_transcript with offset 2000"))
    #expect(long.text.contains("linia 1999"))
    #expect(!long.text.contains("linia 2000"))
}

@Test func getMeetingShowsOverviewOnlyForTheCurrentRun() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let raw = transcript([utt("surowa", .them, at: 0)]).echoMarked()
    let corrected = CorrectedTranscript(transcript: transcript([utt("poprawiona", .them, at: 0)]),
                                        model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    var meta = NoteMeta()
    meta.overview = "Krótki przegląd"
    meta.overviewRunID = runID
    meta.overviewTranscriptFingerprint = Overview.fingerprint(raw)
    meta.overviewCorrectionFingerprint = Overview.fingerprint(corrected.transcript)
    try makeSession(paths, id: "s1", raw: [utt("surowa", .them, at: 0)], corrected: [utt("poprawiona", .them, at: 0)],
                    meta: meta)
    let server = MCPServer(paths: paths, version: "test")
    let meeting = try call(server, "get_meeting", ["id": "s1"])
    #expect(meeting.text.contains("## Overview\nKrótki przegląd"))
    // Inny przebieg niż bieżący = przegląd nieaktualny, więc go nie ma.
    meta.overviewRunID = "2026-11-19T09-00-00Z-ffff"
    try makeSession(paths, id: "s2", raw: [utt("surowa", .them, at: 0)], corrected: [utt("poprawiona", .them, at: 0)],
                    meta: meta)
    #expect(!(try call(server, "get_meeting", ["id": "s2"]).text.contains("## Overview")))
}

// MARK: - Granica archiwum i tylko-odczyt

@Test func meetingIdCannotEscapeTheArchive() throws {
    let paths = try dataDir()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    try saveSettings(paths) { $0.agentAccess = true }
    let beside = paths.root.appendingPathComponent("obok").appendingPathComponent("sesja")
    try writeJournal(beside, wallClock: startedAt, seconds: 60)
    try JSONFile.save(transcript([utt("obok", .me, at: 0)]),
                      to: RunDirectory(session: beside, runID: runID).transcript)
    try makeSession(paths, id: "w-srodku", raw: [utt("w środku", .me, at: 0)])
    let server = MCPServer(paths: paths, version: "test")
    for id in ["../obok/sesja", "..", ".", "", "w-srodku/../w-srodku", ".ukryte", "w-srodku\u{0}", "w-srodku\\x"] {
        let response = try call(server, "get_meeting", ["id": id])
        #expect(response.isError, "id: \(id)")
    }
    #expect(try call(server, "get_meeting", ["id": "nie-ma"]).isError)
    #expect(try call(server, "get_meeting", [:]).isError)
    #expect(!(try call(server, "get_meeting", ["id": "w-srodku"]).isError))
}

@Test func serverNeverWritesToTheDataDirectory() throws {
    let paths = try dataDir()
    let recordings = tempDir()
    defer {
        try? FileManager.default.removeItem(at: paths.root)
        try? FileManager.default.removeItem(at: recordings)
    }
    try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
    try saveSettings(paths) {
        $0.agentAccess = true
        $0.recordingsPath = recordings.path
    }
    try JSONFile.save(FoldersFile(folders: [MeetingFolder(id: "f1", name: "Zespół")]), to: paths.folders)
    let inside = try makeSession(paths, id: "s1", raw: [utt("w danych", .me, at: 0)], myNotes: "notatka")
    try makeSession(paths, id: "w-nagraniach", raw: [utt("w nagraniach", .me, at: 0)])
    // Przenieś sesję z katalogu danych do recordingsPath, żeby oba drzewa były niepuste.
    let moved = recordings.appendingPathComponent("s1")
    try FileManager.default.moveItem(at: inside, to: moved)

    let before = try snapshot(paths.root)
    let beforeRecordings = try snapshot(recordings)
    let server = MCPServer(paths: paths, version: "test")
    for (tool, arguments) in [("list_meetings", [:] as [String: Any]),
                              ("get_meeting", ["id": "s1", "include_transcript": true]),
                              ("get_transcript", ["id": "s1"])] {
        let response = try call(server, tool, arguments)
        #expect(!response.isError, "\(tool)")
    }
    #expect(try snapshot(paths.root) == before)
    #expect(try snapshot(recordings) == beforeRecordings)
}
