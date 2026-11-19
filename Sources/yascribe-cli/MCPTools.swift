import Foundation
import YascribeLocalASR
import YascribeNotes
import YascribeProviders
import YascribeSessionFormat
import YascribeTranscription

/// Błąd narzędzia: wynik `isError: true` z czytelnym tekstem (nie błąd JSON-RPC).
struct ToolFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Jedno spotkanie złożone tak samo jak w `AppModel.reloadSessions`: bieżący przebieg, korekta, mówcy, notatka, folder.
struct MeetingRecord {
    let id: String
    let url: URL
    let summary: SessionSummary?
    let startedAt: Date
    let runID: String?
    let rawTranscript: Transcript?
    let corrected: CorrectedTranscript?
    let speakers: SpeakerDiarization?
    let meta: NoteMeta
    let myNotes: String
    let noteSummary: NoteSummary?
    let folderName: String?

    var title: String { NoteTitle.display(meta: meta, noteTitle: noteSummary?.title) }
    var duration: Double? { MeetingArchive.duration(summary) }

    /// Jak panel Overview w UI: tylko wynik policzony dla bieżącego przebiegu i bieżących odcisków.
    var overview: String? {
        Overview.cached(meta, runID: runID, transcript: rawTranscript, correctedTranscript: corrected?.transcript)
    }

    var transcriptVersion: String? {
        guard rawTranscript != nil else { return nil }
        return corrected != nil ? "corrected" : "original"
    }

    func displayTranscript(useCorrected: Bool, rules: ReplacementRules) -> Transcript? {
        MeetingArchive.displayTranscript(raw: rawTranscript, corrected: corrected, useCorrected: useCorrected,
                                         rules: rules, speakers: speakers)
    }

    var speakerMarkers: SpeakerMarkers {
        MeetingArchive.speakerMarkers(summary: noteSummary, speakers: speakers, rawTranscript: rawTranscript)
    }
}

/// Składanie spotkań dla serwera MCP. Tylko odczyt: żadna metoda `NotesStore` nie zapisuje.
enum MeetingLoader {
    static func directory(_ paths: YascribePaths, _ settings: GlobalSettings) -> URL {
        MeetingArchive.sessionsDirectory(paths: paths, settings: settings)
    }

    /// Granica zaufania dla `id` z zewnątrz (§13.3): jeden bezpieczny komponent nazwy.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".." && !id.hasPrefix(".")
            && !id.contains("/") && !id.contains("\\") && !id.contains("\0")
    }

    /// Istniejący podkatalog spotkań, nie dowiązanie, z dziennikiem nagrania.
    static func url(id: String, in directory: URL) -> URL? {
        guard isValidID(id) else { return nil }
        let url = directory.appendingPathComponent(id)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else { return nil }
        guard MeetingArchive.isSession(url) else { return nil }
        return url
    }

    /// shortcut: dowiązania wewnątrz sesji są poza zakresem — serwer nic nie tworzy, więc agent nie może ich podłożyć,
    /// a aplikacja czyta te same pliki.
    static func record(url: URL, folders: FoldersFile) -> MeetingRecord {
        let summary = try? SessionDirectory(url: url).summarize()
        let run = RunSelection.of(session: url)
        let store = NotesStore(session: url)
        let speakers: SpeakerDiarization?
        if let runID = run.currentID {
            speakers = SpeakerDiarization.load(
                run: RunDirectory(session: url, runID: runID),
                acceptedPins: SpeakerDiarization.knownPins(localPin: DiarizerManifest.pin),
                currentAudioFingerprint: SpeakerDiarization.audioFingerprint(session: url))
        } else {
            speakers = nil
        }
        let meta = store.readMeta()
        return MeetingRecord(
            id: url.lastPathComponent, url: url, summary: summary,
            startedAt: summary?.wallClock ?? .distantPast, runID: run.currentID,
            rawTranscript: run.transcript?.echoMarked(),
            corrected: CorrectedTranscript.load(session: url, runID: run.currentID),
            speakers: speakers, meta: meta, myNotes: store.readMyNotes(),
            noteSummary: (try? store.readSummary()) ?? nil,
            folderName: folders.folder(meta.folderID)?.name)
    }

    static func all(paths: YascribePaths, settings: GlobalSettings, folders: FoldersFile) -> [MeetingRecord] {
        let directory = self.directory(paths, settings)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            url(id: name, in: directory).map { record(url: $0, folders: folders) }
        }
    }
}

/// Definicje i obsługa trzech narzędzi read-only (§5).
enum MCPTools {
    static let accessOff = "Agent access is off. Turn it on in Yascribe → Settings → Agent access (MCP)."

    static var definitions: [[String: Any]] { [
        [
            "name": "list_meetings",
            "title": "List meetings",
            "description": "List and search meetings, newest first.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Case-insensitive text to look for in titles, notes, summaries and transcripts."],
                    "folder": ["type": "string", "description": "Folder name from Yascribe."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "default": 20],
                    "offset": ["type": "integer", "minimum": 0, "default": 0],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_meeting",
            "title": "Get meeting",
            "description": "Get one meeting as markdown: details, overview, summary, my notes; optionally the transcript.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Meeting id from list_meetings."],
                    "include_transcript": ["type": "boolean", "default": false],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_transcript",
            "title": "Get transcript",
            "description": "Get the transcript lines of one meeting, paged.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Meeting id from list_meetings."],
                    "version": ["type": "string", "enum": ["corrected", "original"]],
                    "offset": ["type": "integer", "minimum": 0, "default": 0],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 2000, "default": 500],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
    ] }

    static func call(_ name: String, arguments: [String: Any], paths: YascribePaths) -> (text: String, isError: Bool) {
        do {
            // Zgoda i ścieżki czytane świeżo przy każdym wywołaniu; nieczytelny plik = wyłączone.
            guard let settings = try? JSONFile.load(GlobalSettings.self, from: paths.settings, default: GlobalSettings()),
                  settings.agentAccessEnabled else {
                return (accessOff, true)
            }
            let folders = (try? JSONFile.load(FoldersFile.self, from: paths.folders, default: FoldersFile())) ?? FoldersFile()
            switch name {
            case "list_meetings": return (try listMeetings(arguments, paths: paths, settings: settings, folders: folders), false)
            case "get_meeting": return (try getMeeting(arguments, paths: paths, settings: settings, folders: folders), false)
            case "get_transcript": return (try getTranscript(arguments, paths: paths, settings: settings, folders: folders), false)
            default: return ("Unknown tool: \(name)", true)
            }
        } catch let failure as ToolFailure {
            return (failure.message, true)
        } catch {
            return ("Couldn't read the archive: \(error.localizedDescription)", true)
        }
    }

    // MARK: Narzędzia

    static func listMeetings(_ arguments: [String: Any], paths: YascribePaths, settings: GlobalSettings,
                             folders: FoldersFile) throws -> String {
        let query = try string(arguments, "query") ?? ""
        let folderName = try string(arguments, "folder")
        let limit = try integer(arguments, "limit", default: 20, range: 1...100)
        let offset = try integer(arguments, "offset", default: 0, range: 0...Int.max)

        var folderID: String?
        if let folderName {
            guard let folder = folders.folders.first(where: { $0.name == folderName })
                ?? folders.folders.first(where: { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) else {
                throw ToolFailure("No folder named \(folderName)")
            }
            folderID = folder.id
        }

        let rules = replacementRules(paths)
        var records = MeetingLoader.all(paths: paths, settings: settings, folders: folders)
        if let folderID { records = records.filter { $0.meta.folderID == folderID } }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            records = records.filter { record in
                SessionSearch.matches(query, title: record.title, myNotes: record.myNotes,
                                      summary: record.noteSummary?.markdown,
                                      transcript: record.displayTranscript(useCorrected: true, rules: rules))
            }
        }
        records.sort { $0.startedAt == $1.startedAt ? $0.id > $1.id : $0.startedAt > $1.startedAt }

        let page = records.dropFirst(min(offset, records.count)).prefix(limit)
        let meetings: [[String: Any]] = page.map { record in
            [
                "id": record.id,
                "title": record.title,
                "startedAt": iso(record.startedAt),
                "durationMinutes": record.duration.map { Int(($0 / 60).rounded()) } ?? NSNull(),
                "folder": record.folderName ?? NSNull(),
                "hasTranscript": record.rawTranscript != nil,
                "transcriptVersion": record.transcriptVersion ?? NSNull(),
                "hasSummary": record.noteSummary != nil,
                "overview": record.overview ?? NSNull(),
            ]
        }
        let payload: [String: Any] = ["total": records.count, "offset": offset, "meetings": meetings]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func getMeeting(_ arguments: [String: Any], paths: YascribePaths, settings: GlobalSettings,
                           folders: FoldersFile) throws -> String {
        guard let id = try string(arguments, "id") else { throw ToolFailure("`id` is required") }
        let includeTranscript = try boolean(arguments, "include_transcript") ?? false
        let record = try load(id: id, paths: paths, settings: settings, folders: folders)

        var lines = ["# \(record.title)"]
        let duration = record.duration.map { "\(Int(($0 / 60).rounded())) min" } ?? "—"
        lines.append("- Date: \(iso(record.startedAt)) · Duration: \(duration) · Folder: \(record.folderName ?? "—")")
        lines.append("- Transcript: \(record.transcriptVersion ?? "none") · Summary model: \(record.noteSummary?.model ?? "—")")
        var sections: [String] = []
        if let overview = record.overview { sections.append("## Overview\n\(overview)") }
        if let summary = record.noteSummary {
            sections.append("## Summary\n\(record.speakerMarkers.resolved(summary.markdown))")
        }
        let notes = record.myNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { sections.append("## My notes\n\(notes)") }
        if includeTranscript {
            let rules = replacementRules(paths)
            if let transcript = record.displayTranscript(useCorrected: true, rules: rules) {
                var copy = MeetingArchive.copyLines(transcript, summary: record.summary)
                if copy.count > 2000 {
                    copy = Array(copy.prefix(2000))
                    copy.append("… transcript truncated, use get_transcript with offset 2000")
                }
                sections.append("## Transcript\n\(copy.joined(separator: "\n"))")
            }
        }
        return (lines + [""] + sections).joined(separator: "\n\n")
    }

    static func getTranscript(_ arguments: [String: Any], paths: YascribePaths, settings: GlobalSettings,
                              folders: FoldersFile) throws -> String {
        guard let id = try string(arguments, "id") else { throw ToolFailure("`id` is required") }
        let version = try string(arguments, "version")
        if let version, version != "corrected", version != "original" {
            throw ToolFailure("`version` must be corrected or original")
        }
        let offset = try integer(arguments, "offset", default: 0, range: 0...Int.max)
        let limit = try integer(arguments, "limit", default: 500, range: 1...2000)
        let record = try load(id: id, paths: paths, settings: settings, folders: folders)

        let useCorrected = version != "original"
        let rules = replacementRules(paths)
        guard let transcript = record.displayTranscript(useCorrected: useCorrected, rules: rules) else {
            throw ToolFailure("No transcript yet")
        }
        let label = useCorrected && record.corrected != nil ? "corrected" : "original"
        let all = MeetingArchive.copyLines(transcript, summary: record.summary)
        guard !all.isEmpty else { return "Lines 0 of 0" }
        guard offset < all.count else { throw ToolFailure("No lines at offset \(offset) (total \(all.count))") }
        let end = offset > all.count ? all.count : min(all.count, offset + limit)
        var out = "Lines \(offset + 1)–\(end) of \(all.count) · version: \(label)"
        out += "\n" + all[offset..<end].joined(separator: "\n")
        if end < all.count { out += "\nNext: offset \(end)" }
        return out
    }

    // MARK: Pomocnicze

    static func load(id: String, paths: YascribePaths, settings: GlobalSettings, folders: FoldersFile) throws -> MeetingRecord {
        let directory = MeetingLoader.directory(paths, settings)
        guard let url = MeetingLoader.url(id: id, in: directory) else {
            throw ToolFailure("No meeting with id \(id)")
        }
        return MeetingLoader.record(url: url, folders: folders)
    }

    /// Reguły słownika jak w aplikacji (`AppModel`): `dictionary.json` → `ReplacementRules`.
    static func replacementRules(_ paths: YascribePaths) -> ReplacementRules {
        let dictionary = (try? JSONFile.load(UserDictionary.self, from: paths.dictionary, default: UserDictionary()))
            ?? UserDictionary()
        return ReplacementRules(dictionary)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func string(_ arguments: [String: Any], _ key: String) throws -> String? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw ToolFailure("`\(key)` must be a string") }
        return text
    }

    static func boolean(_ arguments: [String: Any], _ key: String) throws -> Bool? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let flag = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
            throw ToolFailure("`\(key)` must be a boolean")
        }
        return flag
    }

    static func integer(_ arguments: [String: Any], _ key: String, default value: Int,
                        range: ClosedRange<Int>) throws -> Int {
        guard let raw = arguments[key], !(raw is NSNull) else { return value }
        guard let number = raw as? NSNumber, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded() else {
            throw ToolFailure("`\(key)` must be an integer")
        }
        let int = number.intValue
        guard range.contains(int) else {
            throw ToolFailure("`\(key)` must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return int
    }
}
