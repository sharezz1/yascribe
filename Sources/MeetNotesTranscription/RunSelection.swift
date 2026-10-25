import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat

/// Który przebieg sesji jest bieżący (R23, Task 10b). Bieżący = wyświetlany, przeszukiwany, poprawiany i streszczany:
/// najnowszy UKOŃCZONY (`run.json` z `finishedAt`), z niepustym transkryptem i bez luk. Nieudana, przerwana, częściowa
/// albo trwająca próba („Transcribe again…") nie zasłania działającego transkryptu. Kolejność (R23 z poprawką R25):
/// 1) najnowszy kwalifikujący się, 2) najnowszy z NIEPUSTYM transkryptem (pusta próba nie zasłania starego tekstu z lukami),
/// 3) najnowszy z jakimkolwiek transkryptem, 4) najnowszy katalog.
/// Najnowsza próba (leksykalnie najnowszy katalog) zostaje celem wznowienia i odniesieniem retencji audio (`latestRunID`).
public struct RunSelection: Equatable, Sendable {
    /// Dlaczego najnowsza próba nie została bieżącą. „W toku" rozpoznaje dopiero aplikacja (dysk tego nie wie).
    public enum Reason: Equatable, Sendable {
        /// Bez transkryptu albo bez `run.json`: trwa, padła albo została anulowana.
        case unfinished
        case gaps(Int)
        case empty
    }

    public struct Attempt: Equatable, Sendable {
        /// Migawka próby z `run.json` albo `input.json`; `nil`, gdy próba padła przed zapisem wejścia.
        public var snapshot: RunSnapshot?
        public var reason: Reason
        public init(snapshot: RunSnapshot?, reason: Reason) { self.snapshot = snapshot; self.reason = reason }
    }

    public var currentID: String?
    /// Bieżący przebieg się kwalifikuje (ukończony, niepusty, bez luk), a nie wygrał przez fallback.
    public var currentIsComplete = false
    /// Transkrypt bieżącego przebiegu (już odczytany — bez drugiego dekodowania u wołającego).
    public var transcript: Transcript?
    /// Migawka bieżącego przebiegu; `nil` dla przebiegów bez `run.json` i `input.json` (np. bardzo stare).
    public var snapshot: RunSnapshot?
    public var latestAttemptID: String?
    /// Najnowsza próba, gdy nie jest bieżącym przebiegiem.
    public var notPromoted: Attempt?

    public static func of(session: URL) -> RunSelection {
        let ids = RunDirectory.runIDs(in: session)
        var cache: [String: Transcript?] = [:]
        func transcript(_ id: String) -> Transcript? {
            if let hit = cache[id] { return hit }
            let t = (try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil)) ?? nil
            cache[id] = t
            return t
        }
        var metaCache: [String: RunMetadata?] = [:]
        func metadata(_ id: String) -> RunMetadata? {
            if let hit = metaCache[id] { return hit }
            let m = (try? JSONFile.load(RunMetadata?.self, from: RunDirectory(session: session, runID: id).metadata, default: nil)) ?? nil
            metaCache[id] = m
            return m
        }
        func snapshot(_ id: String) -> RunSnapshot? {
            metadata(id)?.snapshot
                ?? ((try? JSONFile.load(RunInput?.self, from: RunDirectory(session: session, runID: id).input, default: nil)) ?? nil)?.snapshot
        }
        // Najpierw mały `run.json`; transkrypt dekodujemy tylko dla ukończonych, od najnowszego (wołane przy każdym przeładowaniu).
        let complete = ids.reversed().first { qualifies(metadata($0), transcript($0)) }
        let current = complete
            ?? ids.reversed().first { transcript($0)?.utterances.isEmpty == false }
            ?? ids.reversed().first { transcript($0) != nil } ?? ids.last

        var out = RunSelection(currentID: current, currentIsComplete: complete != nil, transcript: current.flatMap(transcript),
                               snapshot: current.flatMap(snapshot), latestAttemptID: ids.last)
        if let latest = ids.last, latest != current {
            let reason: Reason
            if metadata(latest)?.finishedAt == nil { reason = .unfinished }
            else if let t = transcript(latest) {
                reason = t.failedChunks.isEmpty ? .empty : .gaps(t.failedChunks.count)
            } else { reason = .unfinished }
            out.notPromoted = Attempt(snapshot: snapshot(latest), reason: reason)
        }
        return out
    }

    /// Przebieg się kwalifikuje: ukończony (`run.json` z `finishedAt`), z niepustym transkryptem bez luk. Jedno kryterium dla
    /// wyboru bieżącego i dla retencji audio (F1): próba, której tu nie awansujemy, nie może stracić audio potrzebnego do wznowienia.
    /// Transkrypt jako `@autoclosure`: dekodowany dopiero po sprawdzeniu małego `run.json`.
    public static func qualifies(_ metadata: RunMetadata?, _ transcript: @autoclosure () -> Transcript?) -> Bool {
        guard metadata?.finishedAt != nil, let t = transcript() else { return false }
        return !t.utterances.isEmpty && t.failedChunks.isEmpty
    }

    /// Czy po zakończeniu przebiegu `runID` puścić łańcuch korekta → autotytuł (R23 pkt 4): tylko gdy został bieżącym i się
    /// kwalifikuje. Wyjątek: pierwsza transkrypcja nagrania (żaden inny przebieg nie ma transkryptu) — bieżąca z luką dostaje
    /// łańcuch jak przed 2.1. Próba z lukami albo pusta obok wcześniejszego transkryptu — nie. Wołane ponownie przed autotytułem
    /// i przed jego zapisem: w trakcie wolnej korekty nowszy przebieg mógł zostać bieżącym (fix round 1, I2).
    public static func shouldPostProcess(session: URL, runID: String) -> Bool {
        let sel = of(session: session)
        guard sel.currentID == runID else { return false }
        if sel.currentIsComplete { return true }
        return RunDirectory.runIDs(in: session).allSatisfy { id in
            id == runID || !FileManager.default.fileExists(atPath: RunDirectory(session: session, runID: id).transcript.path)
        }
    }
}

/// Trwające operacje na przebiegach sesji (korekta, autotytuł), każda z własnym biletem (F2, F3). Rejestr WSZYSTKICH trwających
/// (`isActive`, `sessions` — sesja zajęta, przenoszenie nagrań zablokowane) jest oddzielony od własności komunikatu: komunikat
/// zapisuje tylko najnowsza rozpoczęta w sesji, a wynik (`corrected.json`, ślad słownika) — tylko najnowsza rozpoczęta dla
/// danego przebiegu. Starsza, kończąc się po nowszej, nie zdejmuje zajętości innych, nie nadpisuje komunikatu ani wyniku.
public struct RunOperations: Equatable, Sendable {
    public struct Ticket: Hashable, Sendable {
        public let session: String
        public let runID: String
        let token: Int
    }

    public struct Outcome: Equatable, Sendable {
        /// Najnowsza rozpoczęta w sesji: wolno zapisać porażkę dla interfejsu.
        public var ownsMessage: Bool
        /// Najnowsza rozpoczęta dla tego przebiegu: wolno zapisać wynik.
        public var mayPublish: Bool
        public init(ownsMessage: Bool, mayPublish: Bool) { self.ownsMessage = ownsMessage; self.mayPublish = mayPublish }
    }

    private var counter = 0
    private var active: Set<Ticket> = []
    // Nie czyścimy przy końcu: starsza kończąca się po nowszej musi wciąż widzieć, że nowsza była (nazwy katalogów nie mają „/”).
    private var latestInSession: [String: Int] = [:]
    private var latestForRun: [String: Int] = [:]

    public init() {}

    public mutating func start(session: String, runID: String) -> Ticket {
        counter += 1
        let t = Ticket(session: session, runID: runID, token: counter)
        active.insert(t)
        latestInSession[session] = counter
        latestForRun[session + "/" + runID] = counter
        return t
    }

    public mutating func finish(_ t: Ticket) -> Outcome {
        active.remove(t)
        return Outcome(ownsMessage: latestInSession[t.session] == t.token, mayPublish: latestForRun[t.session + "/" + t.runID] == t.token)
    }

    public func isActive(_ session: String) -> Bool { active.contains { $0.session == session } }
    public var sessions: Set<String> { Set(active.map(\.session)) }
}

/// Język, w jakim powstał wybrany przebieg (I2): z jego migawki, bo „Transcribe again…" może zmienić język bez zmiany
/// `preset.json` sesji. Preset sesji tylko dla przebiegów bez migawki.
public struct RunLanguage: Equatable, Sendable {
    public var language: LanguageCode?
    public var isAuto: Bool

    public static func of(_ snapshot: RunSnapshot?, fallback preset: Preset?) -> RunLanguage {
        if let s = snapshot { return RunLanguage(language: s.language, isAuto: s.preset.isAutoLanguage) }
        return RunLanguage(language: preset?.language, isAuto: preset?.isAutoLanguage == true)
    }
}
