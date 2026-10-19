import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat
import MeetNotesTranscription

/// Znacznik `<sesja>/audio-deleted.json`: retencja usunęła audio tej sesji (macos.md §11.5, Recordings).
public struct AudioDeletion: Codable, Equatable, Sendable {
    public var afterDays: Int
    public var deletedAt: Date

    public init(afterDays: Int, deletedAt: Date) { self.afterDays = afterDays; self.deletedAt = deletedAt }

    public static func url(_ session: URL) -> URL { session.appendingPathComponent("audio-deleted.json") }
    public static func read(_ session: URL) -> AudioDeletion? {
        (try? JSONFile.load(AudioDeletion?.self, from: url(session), default: nil)) ?? nil
    }
}

/// Retencja audio (decyzja użytkownika 2026-10-16): po N dniach kasujemy TYLKO `*.caf` z katalogu sesji;
/// transkrypt, notatki, My notes, dziennik i meta zostają. Audio sesji bez ukończonej transkrypcji zostaje.
public enum AudioRetention {
    /// Ścieżki audio sesji: `*.caf` na najwyższym poziomie katalogu (bez rekurencji — `runs/`, `notes/` nie są audio).
    public static func audioFiles(_ session: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: session, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "caf" }
    }

    /// Ukończona = NAJNOWSZY przebieg ma transkrypt bez luk. Przebieg w toku albo przerwany (bez transkryptu)
    /// i transkrypt z lukami (do ponowienia okien trzeba audio) to „nieukończona”.
    public static func transcriptionFinished(_ session: URL) -> Bool {
        guard let id = RunDirectory.latestRunID(in: session),
              let t = (try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil)) ?? nil
        else { return false }
        return t.failedChunks.isEmpty
    }

    /// Wiek liczony od `sessionStarted.wallClock` z dziennika: to jedyny zegar ścienny w dzienniku (koniec ma tylko
    /// czas hosta, sesja po awarii końca nie ma), a błąd to długość spotkania wobec minimum 7 dni.
    public static func isExpired(_ session: URL, days: Int, now: Date) -> Bool {
        guard let started = (try? SessionDirectory(url: session).summarize())?.wallClock else { return false }
        return now.timeIntervalSince(started) > Double(days) * 86_400
    }

    /// Co retencja skasowałaby teraz (decyzja R1, 2026-10-16): te same reguły co `apply`, bez kasowania. `days == nil`
    /// (Forever) = nic. `skip` = nazwy katalogów w użyciu (nagrywana, transkrybowana, korekta/tytuł/notatka w toku).
    /// `bytes` = suma rozmiarów `*.caf` tych sesji — do pytania „Delete audio from N meetings (X)?”.
    public static func plan(sessions: URL, days: Int?, now: Date = Date(), skip: Set<String>) -> (sessions: [URL], bytes: Int64) {
        guard let days else { return ([], 0) }
        var out: [URL] = [], bytes: Int64 = 0
        let dirs = (try? FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)) ?? []
        for session in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !skip.contains(session.lastPathComponent) {
            let audio = audioFiles(session)
            guard !audio.isEmpty, isExpired(session, days: days, now: now), transcriptionFinished(session) else { continue }
            out.append(session)
            bytes += audio.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return (out, bytes)
    }

    /// Kasuje audio sesji z `plan`. Zwraca nazwy sesji, z których usunięto audio, i błędy.
    /// Znacznik zapisujemy PRZED kasowaniem: nieudane kasowanie ponowi następny przebieg (sesja wciąż ma `*.caf`).
    public static func apply(sessions: URL, days: Int?, now: Date = Date(), skip: Set<String>) -> (purged: [String], errors: [String]) {
        guard let days else { return ([], []) }
        var purged: [String] = [], errors: [String] = []
        for session in plan(sessions: sessions, days: days, now: now, skip: skip).sessions {
            do {
                if AudioDeletion.read(session) == nil {
                    try JSONFile.save(AudioDeletion(afterDays: days, deletedAt: now), to: AudioDeletion.url(session))
                }
                for f in audioFiles(session) { try FileManager.default.removeItem(at: f) }
                purged.append(session.lastPathComponent)
            } catch {
                errors.append("\(session.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (purged, errors)
    }
}

/// Przeniesienie folderu nagrań (decyzja użytkownika 2026-10-16): kopia wszystkiego → weryfikacja (lista plików
/// i rozmiary) → przełączenie na nowe miejsce → dopiero wtedy usunięcie starych. Błąd kopii albo weryfikacji = nic
/// nie jest usuwane, stare miejsce zostaje aktywne.
public enum RecordingsMove {
    public struct Progress: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case copying, verifying, removing }
        public var phase: Phase
        public var done: Int
        public var total: Int
        public init(phase: Phase, done: Int, total: Int) { self.phase = phase; self.done = done; self.total = total }
        public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let reason: String
        public var description: String { reason }
    }

    public typealias Copy = @Sendable (URL, URL) throws -> Void
    public static let fileManagerCopy: Copy = { try FileManager.default.copyItem(at: $0, to: $1) }

    /// Powód, dla którego teraz nie wolno przenosić; `nil` = wolno.
    public static func blocked(recording: Bool, busy: Bool, moving: Bool) -> String? {
        if moving { return "Meetings are being moved." }
        if recording { return "Can't change the location while recording." }
        if busy { return "Can't change the location while a meeting is being transcribed or summarized." }
        return nil
    }

    /// Powód odmowy dla folderu docelowego; `nil` = można przenieść.
    public static func destinationRefusal(from old: URL, to new: URL) -> String? {
        let o = resolved(old).pathComponents, n = resolved(new).pathComponents
        if o == n { return "That's already the recordings folder." }
        if n.starts(with: o) { return "Choose a folder outside the current recordings folder." }
        if o.starts(with: n) { return "Choose a folder that doesn't contain the current recordings folder." }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: new.path, isDirectory: &isDir) {
            if !isDir.boolValue { return "That's a file, not a folder." }
            if !topLevel(new).isEmpty { return "Choose an empty folder." }
        }
        return nil
    }

    /// Cały przebieg. `commit` przełącza aktywną lokalizację (i zapisuje ustawienia) po udanej weryfikacji — jeśli
    /// rzuci, nic nie usuwamy ze starego miejsca. Rzuca `Failure` z powodem przed `commit`; po nim zwraca nazwy, których
    /// nie udało się usunąć ze starego miejsca (kopia jest już kompletna i zweryfikowana, więc to tylko resztki).
    /// Przy błędzie sprzątamy WŁASNĄ częściową kopię (decyzja R2, 2026-10-16): tylko wpisy, których przed kopiowaniem
    /// w celu nie było, i folder docelowy, jeśli to my go utworzyliśmy i jest całkiem pusty. Nic innego w celu.
    public static func run(from old: URL, to new: URL, copy: Copy = fileManagerCopy,
                           progress: @Sendable (Progress) -> Void = { _ in },
                           commit: @Sendable () async throws -> Void) async throws -> [String] {
        if let r = destinationRefusal(from: old, to: new) { throw Failure(reason: r) }
        let fm = FileManager.default
        let kept = "Nothing was deleted; meetings stay in \(old.path)."
        let createdFolder = !fm.fileExists(atPath: new.path)
        do { try fm.createDirectory(at: new, withIntermediateDirectories: true) } catch {
            throw Failure(reason: "Couldn't create \(new.path): \(error.localizedDescription). \(kept)")
        }
        var ours: [String] = []
        func fail(_ why: String) -> Failure {
            let left = removeOwnCopy(ours, in: new, removeFolder: createdFolder)
            let tail = left.isEmpty ? "The partial copy was removed."
                : "Couldn't remove the partial copy (\(left.joined(separator: ", "))) from \(new.path)."
            return Failure(reason: "\(why). \(kept) \(tail)")
        }
        let items = topLevel(old)
        for (i, name) in items.enumerated() {
            progress(Progress(phase: .copying, done: i, total: items.count))
            let target = new.appendingPathComponent(name)
            // Własność ustalamy PRZED kopią: urwana kopia też jest nasza, a wpis, który już był, nie jest.
            if !fm.fileExists(atPath: target.path) { ours.append(name) }
            do { try copy(old.appendingPathComponent(name), target) } catch {
                throw fail("Couldn't copy \(name): \(error.localizedDescription)")
            }
        }
        progress(Progress(phase: .verifying, done: 0, total: items.count))
        let source: [String: Int], copied: [String: Int]
        do { source = try listing(old, items); copied = try listing(new, items) } catch {
            throw fail("Couldn't check the copy: \(error.localizedDescription)")
        }
        if let bad = source.keys.sorted().first(where: { copied[$0] != source[$0] }) ?? copied.keys.sorted().first(where: { source[$0] == nil }) {
            throw fail("The copy doesn't match the original (\(bad))")
        }
        do { try await commit() } catch {
            throw fail("Couldn't switch to the new folder: \(error.localizedDescription)")
        }
        var leftovers: [String] = []
        for (i, name) in items.enumerated() {
            progress(Progress(phase: .removing, done: i, total: items.count))
            if (try? FileManager.default.removeItem(at: old.appendingPathComponent(name))) == nil { leftovers.append(name) }
        }
        progress(Progress(phase: .removing, done: items.count, total: items.count))
        return leftovers
    }

    /// Usuwa z `dir` tylko wpisy `names` (nasza kopia); `removeFolder` = `dir` utworzył ten przebieg — usuwamy go,
    /// gdy jest całkiem pusty (także bez ukrytych plików). Zwraca nazwy, których nie udało się usunąć.
    static func removeOwnCopy(_ names: [String], in dir: URL, removeFolder: Bool) -> [String] {
        let fm = FileManager.default
        let left = names.filter { name in
            let url = dir.appendingPathComponent(name)
            return fm.fileExists(atPath: url.path) && (try? fm.removeItem(at: url)) == nil
        }
        if removeFolder, ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["?"]).isEmpty { try? fm.removeItem(at: dir) }
        return left
    }

    /// Rozmiar folderu w bajtach (suma plików) — nagłówek „4.2 GB on disk”.
    public static func size(of dir: URL) -> Int64 {
        Int64(((try? listing(dir, topLevel(dir))) ?? [:]).values.reduce(0) { $0 + max($1, 0) })
    }

    /// Widoczne wpisy na najwyższym poziomie (`.DS_Store` i inne ukryte pomijamy).
    static func topLevel(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Ścieżka względna → rozmiar (katalog: -1) dla `items` w `root`, rekurencyjnie, z ukrytymi plikami w środku.
    static func listing(_ root: URL, _ items: [String]) throws -> [String: Int] {
        var out: [String: Int] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        func record(_ url: URL, _ rel: String) throws {
            let v = try url.resourceValues(forKeys: Set(keys))
            out[rel] = v.isDirectory == true ? -1 : (v.fileSize ?? 0)
        }
        for name in items {
            let top = root.appendingPathComponent(name)
            try record(top, name)
            guard (try top.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
            var failure: Error?
            let e = FileManager.default.enumerator(at: top, includingPropertiesForKeys: keys) { _, err in failure = err; return false }
            let base = top.resolvingSymlinksInPath().pathComponents.count
            while let url = e?.nextObject() as? URL {
                try record(url, ([name] + url.resolvingSymlinksInPath().pathComponents.dropFirst(base)).joined(separator: "/"))
            }
            if let failure { throw failure }
        }
        return out
    }

    /// Ścieżka z rozwiązanymi dowiązaniami; dla nieistniejącej — przez najbliższego istniejącego przodka
    /// (`/var` → `/private/var` musi wyjść tak samo dla starego i nowego folderu).
    static func resolved(_ url: URL) -> URL {
        var existing = url.standardizedFileURL, rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return rest.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }
}
