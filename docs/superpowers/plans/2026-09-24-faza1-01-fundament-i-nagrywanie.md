# Plan A — fundament i rdzeń nagrywania

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** pakiet SwiftPM ze skryptem testów odpornym na wady toolchainu, format sesji na dysku i rdzeń nagrywania dwukanałowego z testami T1–T9 — oraz narzędzie `meetnotes-cli record` do sond sprzętowych.

**Architektura:** `MeetNotesSessionFormat` (czysty Foundation: dziennik, podsumowanie, układ CAF) ← `MeetNotesRecording` (źródła, pisarze, rejestrator, warunki końca). Każda ścieżka ma własnego pisarza, więc miks jest strukturalnie niemożliwy. Dziennik `jsonl` jest źródłem prawdy, `session.json` jego pochodną. Czas: czas hosta pierwszej próbki per ścieżka + kotwice zegara co 10 s.

**Stos:** Swift 6.4, CLT, `swift-testing`, Core Audio (`CATapDescription`, urządzenie zbiorcze, IOProc), AVFoundation (`AVAudioEngine` z przetwarzaniem głosu, `AVAudioConverter`).

**Specyfikacja:** `docs/superpowers/specs/2026-09-24-rdzen-nagrywania-design.md` (po poprawkach z zadania 0 w przeglądzie). Przegląd: `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md`.

## Wspólne ograniczenia

Obowiązują w całości: przegląd §4. Najważniejsze dla tego planu:

- Testy wyłącznie przez `scripts/test.sh`; kod `3` = błąd pluginu makr, nie wynik → `rm -rf .build` i powtórz; kod `4` = liczba testów się nie zgadza, wynik nieważny.
- `MeetNotesRecording` zależy wyłącznie od `MeetNotesSessionFormat` (spec rdzenia §3).
- Pliki sesji: `system.caf` (częstotliwość i kanały tapu, Int16 LE), `mic_raw.caf`, `mic_aec.caf` (16 kHz mono Int16 LE), CAF z blokiem `data` o rozmiarze -1.
- Tolerancja luki 30 ms między **sąsiednimi** porcjami; kotwica zegara co 10 s i po każdej luce.
- Warunki końca domyślnie: 600 s ciszy, 4 h twardego limitu, 30 s bez danych. Próg ciszy −50 dBFS.
- Strażnik zer: ścieżka `system` z samych zer przez 60 s → `track.failed` z powodem `allZeros60s`.
- Przetwarzanie głosu z `duckingLevel: .min`.

## Na co patrzeć przy przeglądzie

Pięć wejść, które spec implikuje, a które najłatwiej przeoczyć. Każde ma test w zadaniu, do którego należy kod:

1. **`kill -9` w trakcie zapisu linii dziennika** → urwana ostatnia linia jest pomijana, uszkodzona linia w środku to błąd. Test `readerSkipsTruncatedLastLine`, `readerRejectsCorruptLineInTheMiddle` (A2).
2. **Zegar urządzenia szybszy o ~200 ppm przez godzinę** → żadnej fałszywej luki ciszy, czas z kotwic ≤ 50 ms. Testy `accumulatedDriftNeverInsertsSilence` (A5), `clockAnchorsAbsorbDeviceClockDrift` (A3).
3. **Bufor 4800 ramek z `installTap`** → konwerter oddaje całość w tym samym wywołaniu, etykieta czasu zostaje prawdziwa. Test `sameRateConversionKeepsFrameCountAndShape` (A7).
4. **Odmowa uprawnienia, przy której tap oddaje zera zamiast błędu** → jawne `track.failed`, nie „nagranie" pełne zer. Test `systemTrackOfPureZerosIsFlagged` (A6).
5. **Drugi start w istniejącym katalogu sesji** → nigdy nie nadpisuje. Test `existingSessionDirectoryIsNeverOverwritten` (A6).

Czego testy jednostkowe nie złapią i co sprawdza A10 na sprzęcie: przepięcie na urządzenie o innej częstotliwości (słuchawki Bluetooth), ściszanie Teamsa przez przetwarzanie głosu, jednoczesność dwóch strumieni mikrofonu.

---

### Zadanie A1: Szkielet pakietu i skrypt testów

Status: ✅ zweryfikowane (skrypt sprawdzony w 5 czystych przebiegach i dwiema mutacjami).

**Pliki:**
- Utwórz: `Package.swift`
- Utwórz: `scripts/test.sh`
- Utwórz: `Sources/MeetNotesSessionFormat/_Placeholder.swift`, `Sources/MeetNotesRecording/_Placeholder.swift`, `Sources/MeetNotesProviders/_Placeholder.swift`, `Sources/MeetNotesTranscription/_Placeholder.swift`
- Utwórz: `Sources/meetnotes-cli/main.swift`, `Sources/MeetNotesApp/main.swift`
- Utwórz: `Tests/MeetNotesSessionFormatTests/_Placeholder.swift`, `Tests/MeetNotesRecordingTests/_Placeholder.swift`, `Tests/MeetNotesProvidersTests/_Placeholder.swift`, `Tests/MeetNotesTranscriptionTests/_Placeholder.swift`

**Interfejsy:**
- Dostarcza: cele `MeetNotesSessionFormat`, `MeetNotesRecording` (→ SessionFormat), `MeetNotesProviders`, `MeetNotesTranscription` (→ SessionFormat, Providers), `meetnotes-cli`, `MeetNotesApp`; testy `MeetNotesTranscriptionTests` zależą też od `MeetNotesRecording` (tylko testy). Polecenie `scripts/test.sh [--filter X]`.

- [x] **Krok 1: Pakiet.** Utwórz `Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetNotes",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "MeetNotesApp", targets: ["MeetNotesApp"]),
        .executable(name: "meetnotes-cli", targets: ["meetnotes-cli"]),
    ],
    targets: [
        .target(name: "MeetNotesSessionFormat"),
        .target(name: "MeetNotesRecording", dependencies: ["MeetNotesSessionFormat"]),
        .target(name: "MeetNotesProviders"),
        .target(name: "MeetNotesTranscription", dependencies: ["MeetNotesSessionFormat", "MeetNotesProviders"]),
        .executableTarget(name: "meetnotes-cli", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription"]),
        .executableTarget(name: "MeetNotesApp", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription"]),
        .testTarget(name: "MeetNotesSessionFormatTests", dependencies: ["MeetNotesSessionFormat"]),
        .testTarget(name: "MeetNotesRecordingTests", dependencies: ["MeetNotesRecording"]),
        .testTarget(name: "MeetNotesProvidersTests", dependencies: ["MeetNotesProviders"]),
        .testTarget(name: "MeetNotesTranscriptionTests", dependencies: ["MeetNotesTranscription", "MeetNotesRecording"]),
    ]
)
```

- [x] **Krok 2: Zaślepki.** SwiftPM wymaga co najmniej jednego pliku w każdym celu. Każda zaślepka znika w zadaniu, które wnosi pierwszy prawdziwy plik do celu.

```bash
for t in MeetNotesSessionFormat MeetNotesRecording MeetNotesProviders MeetNotesTranscription; do
  mkdir -p Sources/$t Tests/${t}Tests
  echo "enum _Placeholder {}" > Sources/$t/_Placeholder.swift
  echo "import Testing" > Tests/${t}Tests/_Placeholder.swift
done
mkdir -p Sources/meetnotes-cli Sources/MeetNotesApp scripts
echo 'print("meetnotes-cli")' > Sources/meetnotes-cli/main.swift
echo 'print("MeetNotesApp")' > Sources/MeetNotesApp/main.swift
```

- [x] **Krok 3: Skrypt testów.** Utwórz `scripts/test.sh` i nadaj mu prawo wykonania (`chmod +x scripts/test.sh`):

```bash
#!/bin/bash
# Uruchamia testy i sprawdza, że uruchomiło się DOKŁADNIE tyle testów, ile jest
# deklaracji @Test w Tests/. Nigdy nie uruchamiaj gołego `swift test`:
#
# 1. Na Swift 6.4 + samych Command Line Tools silnik budowania niedeterministycznie
#    gubi plugin makr biblioteki Testing ("plugin for module 'TestingMacros' not
#    found") — dlatego ładujemy go jawnie.
# 2. Po takim błędzie następny przebieg potrafi zameldować "Test run with 0 tests
#    ... passed", a inny uruchomił 11 testów z 23 bez żadnego błędu. Zielony wynik
#    bez sprawdzenia liczby testów nie dowodzi niczego (wnioski z forka, rozdz. 1).
#
# Użycie: scripts/test.sh [argumenty dla swift test, np. --filter NazwaTestu]
# Z --filter liczba nie jest sprawdzana (uruchamia się podzbiór).
set -uo pipefail
cd "$(dirname "$0")/.."

TOOLCHAIN_BIN="$(dirname "$(xcrun --find swift)")"
PLUGIN="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ ! -f "$PLUGIN" ]; then
    echo "test.sh: nie ma pluginu makr Testing: $PLUGIN" >&2
    exit 2
fi

OUT="$(mktemp)"
swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@" 2>&1 | tee "$OUT"
STATUS=${PIPESTATUS[0]}

if grep -q "TestingMacros' not found" "$OUT"; then
    echo "test.sh: BŁĄD BUDOWANIA pluginu makr — to nie jest wynik testów. Uruchom: rm -rf .build && scripts/test.sh" >&2
    exit 3
fi
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi

for arg in "$@"; do
    case "$arg" in --filter|--skip) echo "test.sh: filtr — liczby testów nie sprawdzam"; exit 0 ;; esac
done

RAN=$(grep -oE 'Test run with [0-9]+ tests' "$OUT" | grep -oE '[0-9]+' | paste -sd+ - | bc)
EXPECTED=$(grep -rhE '^[[:space:]]*@Test' Tests | wc -l | tr -d ' ')
rm -f "$OUT"
if [ "${RAN:-0}" -ne "$EXPECTED" ]; then
    echo "test.sh: uruchomiono $RAN testów, a w Tests/ jest $EXPECTED deklaracji @Test. Wynik NIEWAŻNY." >&2
    exit 4
fi
echo "test.sh: $RAN/$EXPECTED testów uruchomionych i zaliczonych."
```

- [x] **Krok 4: Uruchom.** `scripts/test.sh` — oczekiwane: kod `0` i ostatnia linia `test.sh: 0/0 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Mutacja — test znika.** Bezpiecznik ma łapać test, który jest w kodzie, ale się nie uruchamia.

```bash
printf 'import Testing\n#if false\n@Test func vanished() {}\n#endif\n' > Tests/MeetNotesRecordingTests/Mutant.swift
scripts/test.sh; echo "kod=$?"
```

Oczekiwane: `kod=4` i komunikat `uruchomiono 0 testów, a w Tests/ jest 1 deklaracji @Test. Wynik NIEWAŻNY.`

- [x] **Krok 6: Mutacja — test pada.**

```bash
printf 'import Testing\n@Test func mutantFails() { #expect(1 == 2) }\n' > Tests/MeetNotesRecordingTests/Mutant.swift
scripts/test.sh; echo "kod=$?"
rm Tests/MeetNotesRecordingTests/Mutant.swift
```

Oczekiwane: `kod=1` i `✘ Test mutantFails() failed`. Po usunięciu pliku `scripts/test.sh` znów daje `0/0`.

- [x] **Krok 7: Commit.**

```bash
git add Package.swift scripts/test.sh Sources Tests
git commit -m "Szkielet pakietu i skrypt testow odporny na wady toolchainu" -m "Swift 6.4 na samych CLT gubi plugin makr Testing i potrafi zameldowac 0 testow jako sukces. test.sh laduje plugin jawnie i porownuje liczbe uruchomionych testow z deklaracjami @Test."
```

---

### Zadanie A2: Dziennik sesji

Status: ✅ zweryfikowane (4 testy).

**Pliki:**
- Utwórz: `Sources/MeetNotesSessionFormat/Timebase.swift`, `Sources/MeetNotesSessionFormat/JournalEvent.swift`, `Sources/MeetNotesSessionFormat/SessionJournal.swift`
- Usuń: `Sources/MeetNotesSessionFormat/_Placeholder.swift`, `Tests/MeetNotesSessionFormatTests/_Placeholder.swift`
- Test: `Tests/MeetNotesSessionFormatTests/SessionJournalTests.swift`

**Interfejsy:**
- Dostarcza: `Timebase(numer:denom:)`, `Timebase.current`, `seconds(ticks:) -> Double`, `ticks(seconds:) -> UInt64`, `secondsBetween(_:_:) -> Double` (ze znakiem). `JournalEvent` (płaska struktura: `type: Kind`, `hostTime: UInt64` + pola opcjonalne) z fabrykami `.sessionStarted(hostTime:timebase:wallClock:)`, `.trackOpened(_:hostTime:sampleRate:channels:deviceUID:)`, `.trackFirstSample(_:hostTime:)`, `.trackClock(_:frameIndex:hostTime:)`, `.deviceChanged(_:deviceUID:hostTime:)`, `.trackGap(_:frameIndex:gapFrames:hostTime:)`, `.trackPermissionDenied(_:permission:detection:hostTime:)`, `.trackFailed(_:reason:hostTime:)`, `.trackClosed(_:frames:hostTime:)`, `.sessionEnded(reason:hostTime:)`. `SessionJournal(url:) throws` (nie nadpisuje istniejącego pliku), `append(_:) throws` (z `synchronize()`), `close() throws`, `static read(url:) throws -> [JournalEvent]`. `JournalError.alreadyExists(String)`, `.corruptLine(Int)`.

- [x] **Krok 1: Test, który padnie.** Usuń obie zaślepki formatu sesji i utwórz `Tests/MeetNotesSessionFormatTests/SessionJournalTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesSessionFormat

private func tempDir() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func journalRoundTripsEvents() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    let j = try SessionJournal(url: url)
    let tb = Timebase(numer: 1, denom: 1)
    try j.append(.sessionStarted(hostTime: 10, timebase: tb, wallClock: Date(timeIntervalSince1970: 0)))
    try j.append(.trackOpened("system", hostTime: 11, sampleRate: 48_000, channels: 2, deviceUID: "BuiltInSpeakerDevice"))
    try j.close()
    let events = try SessionJournal.read(url: url)
    #expect(events.count == 2)
    #expect(events[1].type == .trackOpened)
    #expect(events[1].deviceUID == "BuiltInSpeakerDevice")
    #expect(events[0].timebase == tb)
}

@Test func journalRefusesToOverwriteExistingSession() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    _ = try SessionJournal(url: url)
    #expect(throws: JournalError.alreadyExists(url.path)) { _ = try SessionJournal(url: url) }
}

@Test func readerSkipsTruncatedLastLine() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    let j = try SessionJournal(url: url)
    try j.append(.sessionStarted(hostTime: 1, timebase: Timebase(numer: 1, denom: 1), wallClock: Date()))
    try j.close()
    let h = try FileHandle(forWritingTo: url)
    try h.seekToEnd()
    try h.write(contentsOf: Data("{\"type\":\"track.op".utf8))
    try h.close()
    #expect(try SessionJournal.read(url: url).count == 1)
}

@Test func readerRejectsCorruptLineInTheMiddle() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    try Data("{\"type\":\"session.started\",\"hostTime\":1}\nGARBAGE\n{\"type\":\"session.ended\",\"hostTime\":2}\n".utf8).write(to: url)
    #expect(throws: JournalError.corruptLine(2)) { _ = try SessionJournal.read(url: url) }
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesSessionFormatTests` — oczekiwane: kod `1`, błędy kompilacji `cannot find … in scope` dla `SessionJournal`, `Timebase`, `JournalError`. Kod `3` to nie ten błąd — `rm -rf .build` i powtórz.

- [x] **Krok 3: Implementacja.** Utwórz trzy pliki:

`Sources/MeetNotesSessionFormat/Timebase.swift`:

```swift
import Foundation

/// Przelicznik tików `mach_absolute_time` na sekundy. Zapisywany w dzienniku,
/// żeby sesję dało się wyrównać na innej maszynie albo po restarcie.
public struct Timebase: Codable, Equatable, Sendable {
    public var numer: UInt32
    public var denom: UInt32

    public init(numer: UInt32, denom: UInt32) {
        self.numer = numer
        self.denom = denom
    }

    public static var current: Timebase {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numer: info.numer, denom: info.denom)
    }

    public func seconds(ticks: UInt64) -> Double {
        Double(ticks) * Double(numer) / Double(denom) / 1_000_000_000
    }

    public func ticks(seconds: Double) -> UInt64 {
        UInt64((seconds * 1_000_000_000 * Double(denom) / Double(numer)).rounded())
    }

    /// Różnica `a - b` w sekundach, ze znakiem.
    public func secondsBetween(_ a: UInt64, _ b: UInt64) -> Double {
        a >= b ? seconds(ticks: a - b) : -seconds(ticks: b - a)
    }
}
```

`Sources/MeetNotesSessionFormat/JournalEvent.swift`:

```swift
import Foundation

/// Jedno zdarzenie dziennika sesji. Płaska struktura z polami opcjonalnymi:
/// prosta w kodowaniu i odporna na dopisywanie nowych pól.
public struct JournalEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStarted = "session.started"
        case trackOpened = "track.opened"
        case trackFirstSample = "track.firstSample"
        case trackClock = "track.clock"
        case deviceChanged = "device.changed"
        case trackGap = "track.gap"
        case trackPermissionDenied = "track.permissionDenied"
        case trackFailed = "track.failed"
        case trackClosed = "track.closed"
        case sessionEnded = "session.ended"
    }

    public var type: Kind
    public var hostTime: UInt64
    public var trackID: String?
    public var sampleRate: Double?
    public var channels: Int?
    public var deviceUID: String?
    public var sampleFormat: String?
    public var frameIndex: Int?
    public var gapFrames: Int?
    public var frames: Int?
    public var permission: String?
    public var detection: String?
    public var reason: String?
    public var timebase: Timebase?
    public var wallClock: Date?

    public init(type: Kind, hostTime: UInt64) {
        self.type = type
        self.hostTime = hostTime
    }
}

public extension JournalEvent {
    static func sessionStarted(hostTime: UInt64, timebase: Timebase, wallClock: Date) -> JournalEvent {
        var e = JournalEvent(type: .sessionStarted, hostTime: hostTime)
        e.timebase = timebase
        e.wallClock = wallClock
        return e
    }

    static func trackOpened(_ trackID: String, hostTime: UInt64, sampleRate: Double, channels: Int, deviceUID: String) -> JournalEvent {
        var e = JournalEvent(type: .trackOpened, hostTime: hostTime)
        e.trackID = trackID
        e.sampleRate = sampleRate
        e.channels = channels
        e.deviceUID = deviceUID
        e.sampleFormat = "int16"
        return e
    }

    static func trackFirstSample(_ trackID: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackFirstSample, hostTime: hostTime)
        e.trackID = trackID
        return e
    }

    static func trackClock(_ trackID: String, frameIndex: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackClock, hostTime: hostTime)
        e.trackID = trackID
        e.frameIndex = frameIndex
        return e
    }

    static func deviceChanged(_ trackID: String, deviceUID: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .deviceChanged, hostTime: hostTime)
        e.trackID = trackID
        e.deviceUID = deviceUID
        return e
    }

    static func trackGap(_ trackID: String, frameIndex: Int, gapFrames: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackGap, hostTime: hostTime)
        e.trackID = trackID
        e.frameIndex = frameIndex
        e.gapFrames = gapFrames
        return e
    }

    static func trackPermissionDenied(_ trackID: String, permission: String, detection: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackPermissionDenied, hostTime: hostTime)
        e.trackID = trackID
        e.permission = permission
        e.detection = detection
        return e
    }

    static func trackFailed(_ trackID: String, reason: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackFailed, hostTime: hostTime)
        e.trackID = trackID
        e.reason = reason
        return e
    }

    static func trackClosed(_ trackID: String, frames: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackClosed, hostTime: hostTime)
        e.trackID = trackID
        e.frames = frames
        return e
    }

    static func sessionEnded(reason: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .sessionEnded, hostTime: hostTime)
        e.reason = reason
        return e
    }
}
```

`Sources/MeetNotesSessionFormat/SessionJournal.swift`:

```swift
import Foundation

public enum JournalError: Error, Equatable {
    case alreadyExists(String)
    case corruptLine(Int)
}

/// Dziennik `journal.jsonl`: jedno zdarzenie na linię, każda linia
/// synchronizowana z dyskiem. Źródło prawdy o sesji (spec rdzenia §5).
public final class SessionJournal: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw JournalError.alreadyExists(url.path)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
    }

    public func append(_ event: JournalEvent) throws {
        var line = try encoder.encode(event)
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try handle.close()
    }

    /// Czyta dziennik. Ostatnia linia może być urwana przez `kill -9` w trakcie
    /// zapisu — jest wtedy pomijana. Uszkodzona linia w środku to błąd.
    public static func read(url: URL) throws -> [JournalEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        var events: [JournalEvent] = []
        for (index, line) in lines.enumerated() where !line.isEmpty {
            do {
                events.append(try decoder.decode(JournalEvent.self, from: Data(line)))
            } catch {
                let isLast = lines[(index + 1)...].allSatisfy { $0.isEmpty }
                if isLast { break }
                throw JournalError.corruptLine(index + 1)
            }
        }
        return events
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 4/4 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Commit.**

```bash
git add Sources/MeetNotesSessionFormat Tests/MeetNotesSessionFormatTests
git commit -m "Format sesji: dziennik jsonl synchronizowany z dyskiem" -m "Urwana ostatnia linia po kill -9 jest pomijana, uszkodzona w srodku to blad. Dziennik nigdy nie nadpisuje istniejacej sesji."
```

---

### Zadanie A3: Podsumowanie sesji i kotwice zegara (T8)

Status: ✅ zweryfikowane (7 testów).

**Pliki:**
- Utwórz: `Sources/MeetNotesSessionFormat/CAFLayout.swift`, `Sources/MeetNotesSessionFormat/SessionSummary.swift`, `Sources/MeetNotesSessionFormat/SessionDirectory.swift`
- Test: `Tests/MeetNotesSessionFormatTests/SessionSummaryTests.swift`

**Interfejsy:**
- Pobiera: `Timebase`, `JournalEvent`, `SessionJournal` (A2).
- Dostarcza: `CAFLayout.headerSize` (= 68), `bytesPerSample` (= 2), `bytesPerFrame(channels:)`, `frames(fileSize:channels:)`. `SessionSummary` (`startedHostTime`, `timebase`, `wallClock`, `endReason: String?`, `crashed: Bool`, `tracks: [Track]`), `SessionSummary.timelineTrackID = "system"`, `static rebuild(from:) throws -> SessionSummary`, `hostTime(track:frame:) -> UInt64?`, `write(to:) throws`; `Track` (`id`, `sampleRate`, `channels`, `deviceUIDs`, `firstSampleHostTime`, `offsetSeconds`, `frames: Int?`, `gaps: [Gap]`, `clock: [ClockAnchor]`, `permissionDenied`, `failure`, `effectiveSampleRate`) z publicznym `init` z wartościami domyślnymi; `SessionSummaryError.missingSessionStart`. `SessionDirectory(url:)`: `journalURL`, `summaryURL`, `trackURL(_:)`, `summarize() throws`, `rebuildSummaryFile() throws`.

- [x] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesSessionFormatTests/SessionSummaryTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesSessionFormat

/// 1 tik = 1 ns, żeby liczby w testach dało się czytać.
private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func baseEvents() -> [JournalEvent] {
    [
        .sessionStarted(hostTime: 0, timebase: ns, wallClock: Date(timeIntervalSince1970: 0)),
        .trackOpened("system", hostTime: 0, sampleRate: 48_000, channels: 2, deviceUID: "spk"),
        .trackOpened("mic_raw", hostTime: 0, sampleRate: 16_000, channels: 1, deviceUID: "mic"),
        .trackFirstSample("system", hostTime: 38_000_000),
        .trackFirstSample("mic_raw", hostTime: 203_000_000),
    ]
}

@Test func offsetsAreMeasuredAgainstSystemTrack() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents())
    let mic = try #require(sum.tracks.first { $0.id == "mic_raw" })
    #expect(abs((mic.offsetSeconds ?? 0) - 0.165) < 1e-9)
    #expect(sum.tracks.first { $0.id == "system" }?.offsetSeconds == 0)
}

@Test func sessionWithoutEndIsMarkedCrashed() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents())
    #expect(sum.crashed)
    #expect(sum.endReason == nil)
}

@Test func endedSessionCarriesReasonAndFrames() throws {
    let events = baseEvents() + [
        .trackClosed("system", frames: 480_000, hostTime: 10 * s),
        .sessionEnded(reason: "silence", hostTime: 10 * s),
    ]
    let sum = try SessionSummary.rebuild(from: events)
    #expect(!sum.crashed)
    #expect(sum.endReason == "silence")
    #expect(sum.tracks.first { $0.id == "system" }?.frames == 480_000)
}

@Test func gapsAndDeviceChangesAreCollected() throws {
    let events = baseEvents() + [
        .deviceChanged("system", deviceUID: "airpods", hostTime: 5 * s),
        .trackGap("system", frameIndex: 240_000, gapFrames: 14_400, hostTime: 5 * s),
    ]
    let sys = try #require(try SessionSummary.rebuild(from: events).tracks.first { $0.id == "system" })
    #expect(sys.deviceUIDs == ["spk", "airpods"])
    #expect(sys.gaps == [.init(frameIndex: 240_000, frames: 14_400)])
}

@Test func missingStartIsRejected() {
    #expect(throws: SessionSummaryError.missingSessionStart) {
        _ = try SessionSummary.rebuild(from: [.trackFirstSample("system", hostTime: 1)])
    }
}

@Test func clockAnchorsAbsorbDeviceClockDrift() throws {
    // Urządzenie deklaruje 48 000 Hz, a naprawdę daje 48 010 Hz (dryf ~208 ppm,
    // rząd wielkości zmierzony u Narady: 213 ms na 901 s).
    let real = 48_010.0
    var events = baseEvents()
    for k in 1...510 { // co 10 s przez 85 minut
        let frame = Int(Double(k) * 10 * real)
        events.append(.trackClock("system", frameIndex: frame, hostTime: 38_000_000 + UInt64(k) * 10 * s))
    }
    let sum = try SessionSummary.rebuild(from: events)
    let frame = Int(5_000 * real) // ok. 83 minuta
    let truth = 38_000_000 + 5_000 * s
    let got = try #require(sum.hostTime(track: "system", frame: frame))
    let errorMs = abs(ns.secondsBetween(got, truth)) * 1000
    #expect(errorMs <= 50) // T8
    // Nominalna częstotliwość pomyliłaby się o ponad sekundę:
    let naive = 38_000_000 + ns.ticks(seconds: Double(frame) / 48_000)
    #expect(abs(ns.secondsBetween(naive, truth)) > 1.0)
    #expect(abs((sum.tracks[0].effectiveSampleRate ?? 0) - real) < 0.5)
}

@Test func directoryInfersFramesOfCrashedTrackFromFileSize() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sd = SessionDirectory(url: dir)
    let j = try SessionJournal(url: sd.journalURL)
    for e in baseEvents() { try j.append(e) }
    try j.close()
    // 1000 ramek stereo Int16 = 4000 bajtów danych + nagłówek
    try Data(count: CAFLayout.headerSize + 4_000).write(to: sd.trackURL("system"))
    let sum = try sd.rebuildSummaryFile()
    #expect(sum.tracks.first { $0.id == "system" }?.frames == 1_000)
    #expect(FileManager.default.fileExists(atPath: sd.summaryURL.path))
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesSessionFormatTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `SessionSummary`, `SessionDirectory`, `CAFLayout`.

- [x] **Krok 3: Implementacja.**

`Sources/MeetNotesSessionFormat/CAFLayout.swift`:

```swift
import Foundation

/// Układ pliku CAF zapisywanego przez rdzeń nagrywania: PCM Int16 little-endian,
/// przeplatany, blok `data` o rozmiarze -1 („do końca pliku"). Dzięki temu plik
/// jest poprawny w każdej chwili, także po `kill -9` (spec rdzenia §5).
/// Wspólne dla pisarza (MeetNotesRecording) i czytelnika (podsumowanie po awarii).
public enum CAFLayout {
    /// 'caff' + wersja + flagi (8) + nagłówek 'desc' (12) + treść 'desc' (32)
    /// + nagłówek 'data' (12) + licznik edycji (4).
    public static let headerSize = 68
    public static let bytesPerSample = 2

    public static func bytesPerFrame(channels: Int) -> Int { channels * bytesPerSample }

    /// Liczba pełnych ramek w pliku o danym rozmiarze.
    public static func frames(fileSize: Int, channels: Int) -> Int {
        max(0, fileSize - headerSize) / bytesPerFrame(channels: channels)
    }
}
```

`Sources/MeetNotesSessionFormat/SessionSummary.swift`:

```swift
import Foundation

public enum SessionSummaryError: Error, Equatable {
    case missingSessionStart
}

/// Podsumowanie sesji — **pochodna** dziennika, odtwarzalna w każdej chwili.
public struct SessionSummary: Codable, Equatable, Sendable {
    public struct Gap: Codable, Equatable, Sendable {
        public var frameIndex: Int
        public var frames: Int
    }

    public struct ClockAnchor: Codable, Equatable, Sendable {
        public var frameIndex: Int
        public var hostTime: UInt64
    }

    public struct Track: Codable, Equatable, Sendable {
        public var id: String
        public var sampleRate: Double
        public var channels: Int
        public var deviceUIDs: [String]
        public var firstSampleHostTime: UInt64?
        /// Przesunięcie pierwszej próbki względem osi sesji w sekundach.
        /// Oś taktuje ścieżka `system` (spec rdzenia §6).
        public var offsetSeconds: Double?
        /// `nil`, gdy ścieżka nie została zamknięta (awaria).
        public var frames: Int?
        public var gaps: [Gap]
        public var clock: [ClockAnchor]
        public var permissionDenied: String?
        public var failure: String?
        /// Rzeczywista częstotliwość z kotwic zegara — różni się od nominalnej
        /// o dryf zegara urządzenia.
        public var effectiveSampleRate: Double?

        public init(id: String, sampleRate: Double, channels: Int, deviceUIDs: [String] = [],
                    firstSampleHostTime: UInt64? = nil, offsetSeconds: Double? = nil, frames: Int? = nil,
                    gaps: [Gap] = [], clock: [ClockAnchor] = [], permissionDenied: String? = nil,
                    failure: String? = nil, effectiveSampleRate: Double? = nil) {
            self.id = id
            self.sampleRate = sampleRate
            self.channels = channels
            self.deviceUIDs = deviceUIDs
            self.firstSampleHostTime = firstSampleHostTime
            self.offsetSeconds = offsetSeconds
            self.frames = frames
            self.gaps = gaps
            self.clock = clock
            self.permissionDenied = permissionDenied
            self.failure = failure
            self.effectiveSampleRate = effectiveSampleRate
        }
    }

    public static let timelineTrackID = "system"

    public var startedHostTime: UInt64
    public var timebase: Timebase
    public var wallClock: Date?
    public var endReason: String?
    public var crashed: Bool
    public var tracks: [Track]

    public init(startedHostTime: UInt64, timebase: Timebase, wallClock: Date? = nil, endReason: String? = nil,
                crashed: Bool = false, tracks: [Track] = []) {
        self.startedHostTime = startedHostTime
        self.timebase = timebase
        self.wallClock = wallClock
        self.endReason = endReason
        self.crashed = crashed
        self.tracks = tracks
    }

    public static func rebuild(from events: [JournalEvent]) throws -> SessionSummary {
        guard let start = events.first, start.type == .sessionStarted, let timebase = start.timebase else {
            throw SessionSummaryError.missingSessionStart
        }
        var summary = SessionSummary(
            startedHostTime: start.hostTime, timebase: timebase, wallClock: start.wallClock,
            endReason: nil, crashed: true, tracks: [])
        var index: [String: Int] = [:]

        for e in events.dropFirst() {
            switch e.type {
            case .trackOpened:
                guard let id = e.trackID else { continue }
                index[id] = summary.tracks.count
                summary.tracks.append(Track(id: id, sampleRate: e.sampleRate ?? 0, channels: e.channels ?? 0,
                                            deviceUIDs: e.deviceUID.map { [$0] } ?? []))
            case .trackFirstSample:
                if let i = e.trackID.flatMap({ index[$0] }) {
                    summary.tracks[i].firstSampleHostTime = e.hostTime
                    summary.tracks[i].clock.append(ClockAnchor(frameIndex: 0, hostTime: e.hostTime))
                }
            case .trackClock:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex {
                    summary.tracks[i].clock.append(ClockAnchor(frameIndex: f, hostTime: e.hostTime))
                }
            case .deviceChanged:
                if let i = e.trackID.flatMap({ index[$0] }), let uid = e.deviceUID {
                    summary.tracks[i].deviceUIDs.append(uid)
                }
            case .trackGap:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex, let g = e.gapFrames {
                    summary.tracks[i].gaps.append(Gap(frameIndex: f, frames: g))
                }
            case .trackPermissionDenied:
                guard let id = e.trackID else { continue }
                if let i = index[id] {
                    summary.tracks[i].permissionDenied = e.permission
                } else {
                    index[id] = summary.tracks.count
                    summary.tracks.append(Track(id: id, sampleRate: 0, channels: 0, permissionDenied: e.permission))
                }
            case .trackFailed:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].failure = e.reason }
            case .trackClosed:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].frames = e.frames }
            case .sessionEnded:
                summary.endReason = e.reason
                summary.crashed = false
            case .sessionStarted:
                continue
            }
        }

        let anchor = summary.tracks.first(where: { $0.id == timelineTrackID })?.firstSampleHostTime
            ?? summary.startedHostTime
        for i in summary.tracks.indices {
            if let first = summary.tracks[i].firstSampleHostTime {
                summary.tracks[i].offsetSeconds = timebase.secondsBetween(first, anchor)
            }
            let c = summary.tracks[i].clock
            if let a = c.first, let b = c.last, b.frameIndex > a.frameIndex {
                let secs = timebase.secondsBetween(b.hostTime, a.hostTime)
                if secs > 0 { summary.tracks[i].effectiveSampleRate = Double(b.frameIndex - a.frameIndex) / secs }
            }
        }
        return summary
    }

    /// Czas hosta ramki `frame` ścieżki `trackID`, liczony z kotwic zegara
    /// (interpolacja liniowa, poza ostatnią kotwicą — ekstrapolacja z ostatniego
    /// odcinka). To jest to, co naprawdę sprawdza T8.
    public func hostTime(track trackID: String, frame: Int) -> UInt64? {
        guard let t = tracks.first(where: { $0.id == trackID }), let first = t.clock.first else { return nil }
        let anchors = t.clock
        let rate: (ClockAnchor, ClockAnchor) -> Double = { a, b in
            Double(b.frameIndex - a.frameIndex) / timebase.secondsBetween(b.hostTime, a.hostTime)
        }
        var lower = first
        var upper: ClockAnchor?
        for a in anchors {
            if a.frameIndex <= frame { lower = a } else { upper = a; break }
        }
        let fps: Double
        if let u = upper, u.frameIndex > lower.frameIndex {
            fps = rate(lower, u)
        } else if anchors.count >= 2, let prev = anchors.dropLast().last, let last = anchors.last, last.frameIndex > prev.frameIndex {
            fps = rate(prev, last)
        } else {
            fps = t.sampleRate
        }
        guard fps > 0 else { return nil }
        let dt = Double(frame - lower.frameIndex) / fps
        return dt >= 0 ? lower.hostTime + timebase.ticks(seconds: dt) : lower.hostTime - timebase.ticks(seconds: -dt)
    }

    public func write(to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        try e.encode(self).write(to: url, options: .atomic)
    }
}
```

`Sources/MeetNotesSessionFormat/SessionDirectory.swift`:

```swift
import Foundation

/// Nazwy plików w katalogu sesji (spec rdzenia §5) i odtwarzanie podsumowania.
public struct SessionDirectory: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var journalURL: URL { url.appendingPathComponent("journal.jsonl") }
    public var summaryURL: URL { url.appendingPathComponent("session.json") }
    public func trackURL(_ trackID: String) -> URL { url.appendingPathComponent("\(trackID).caf") }

    /// Czyta dziennik i odtwarza podsumowanie. Dla ścieżek bez `track.closed`
    /// (awaria) liczbę ramek wylicza z rozmiaru pliku CAF.
    public func summarize() throws -> SessionSummary {
        var summary = try SessionSummary.rebuild(from: SessionJournal.read(url: journalURL))
        for i in summary.tracks.indices where summary.tracks[i].frames == nil && summary.tracks[i].channels > 0 {
            let path = trackURL(summary.tracks[i].id).path
            if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int {
                summary.tracks[i].frames = CAFLayout.frames(fileSize: size, channels: summary.tracks[i].channels)
            }
        }
        return summary
    }

    /// Jak `summarize()`, a wynik zapisuje do `session.json`.
    @discardableResult
    public func rebuildSummaryFile() throws -> SessionSummary {
        let s = try summarize()
        try s.write(to: summaryURL)
        return s
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 11/11 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Mutacja (T8).** W `SessionSummary.swift`, w gałęzi `case .trackClock:`, zamień `summary.tracks[i].clock.append(ClockAnchor(frameIndex: f, hostTime: e.hostTime))` na `_ = (i, f)`. `scripts/test.sh --filter clockAnchorsAbsorbDeviceClockDrift` — oczekiwane: pada (błąd ponad 50 ms, `effectiveSampleRate` puste). Przywróć linię; `scripts/test.sh` znów `11/11`.

- [x] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesSessionFormat Tests/MeetNotesSessionFormatTests
git commit -m "Format sesji: podsumowanie odtwarzane z dziennika, kotwice zegara" -m "Przesuniecia sciezek wzgledem sciezki systemowej, luki, zmiany urzadzen, awaria bez session.ended. Czas ramki z kotwic track.clock - nominalna czestotliwosc mylilaby sie o sekunde po 83 minutach."
```

---

### Zadanie A4: Pisarz i czytnik CAF (T7)

Status: ✅ zweryfikowane (6 testów), z jedną poprawką po recenzji w `CAFReader` (zbędna kopia tablicy, R6), sprawdzoną przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet).

**Pliki:**
- Utwórz: `Sources/MeetNotesRecording/CAFWriter.swift`, `Sources/MeetNotesSessionFormat/CAFReader.swift`
- Usuń: `Sources/MeetNotesRecording/_Placeholder.swift`, `Tests/MeetNotesRecordingTests/_Placeholder.swift`
- Test: `Tests/MeetNotesRecordingTests/CAFWriterTests.swift` (zawiera też pomocniki `tempURL`, `sine`, `readInt16` używane przez dalsze testy nagrywania)

**Interfejsy:**
- Pobiera: `CAFLayout` (A3).
- Dostarcza: `CAFWriter(url:sampleRate:channels:) throws`, `append(_ samples: [Int16]) throws` (przeplatane, pełne ramki), `appendSilence(frames:) throws`, `framesWritten`, `close() throws`, `static header(sampleRate:channels:) -> Data`. `CAFReader(url:) throws` (`sampleRate`, `channels`, `samples: [Int16]`, `frames`), `CAFReadError.tooShort`, `.notOurLayout(String)`.

- [x] **Krok 1: Test, który padnie.** Usuń obie zaślepki nagrywania i utwórz `Tests/MeetNotesRecordingTests/CAFWriterTests.swift`:

```swift
import AVFoundation
import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

func tempURL(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d.appendingPathComponent(name)
}

func sine(frames: Int, channels: Int, rate: Double = 48_000, hz: Double = 440, amp: Double = 0.5) -> [Int16] {
    var out: [Int16] = []
    out.reserveCapacity(frames * channels)
    for i in 0..<frames {
        let v = Int16(amp * 32_767 * sin(2 * .pi * hz * Double(i) / rate))
        for _ in 0..<channels { out.append(v) }
    }
    return out
}

/// Czyta plik systemowym czytnikiem (AVAudioFile) — dowód, że nasz CAF jest
/// zwykłym CAF-em dla innych narzędzi. Czyta w pętli, bo jedno `read(into:)`
/// potrafi oddać mniej ramek niż pojemność bufora.
func readInt16(_ url: URL) throws -> (samples: [Int16], rate: Double, channels: Int) {
    let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
    let ch = Int(f.processingFormat.channelCount)
    let buf = try #require(AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8_192))
    var out: [Int16] = []
    while f.framePosition < f.length {
        try f.read(into: buf)
        if buf.frameLength == 0 { break }
        let p = try #require(buf.int16ChannelData)
        out.append(contentsOf: UnsafeBufferPointer(start: p[0], count: Int(buf.frameLength) * ch))
    }
    return (out, f.processingFormat.sampleRate, ch)
}

@Test func headerHasTheSizeTheReaderAssumes() {
    #expect(CAFWriter.header(sampleRate: 48_000, channels: 2).count == CAFLayout.headerSize)
}

@Test func writtenSamplesReadBackBitExact() throws {
    let url = try tempURL("system.caf")
    let w = try CAFWriter(url: url, sampleRate: 48_000, channels: 2)
    let s = sine(frames: 4_800, channels: 2)
    try w.append(s)
    try w.close()
    let r = try readInt16(url)
    #expect(r.rate == 48_000)
    #expect(r.channels == 2)
    #expect(r.samples == s)
}

@Test func fileIsReadableWithoutClose() throws {
    // Symulacja kill -9: pisarz nie dostaje close(), a plik ma być czytelny.
    let url = try tempURL("mic_raw.caf")
    let w = try CAFWriter(url: url, sampleRate: 16_000, channels: 1)
    try w.append(sine(frames: 16_000, channels: 1, rate: 16_000))
    let r = try readInt16(url)
    #expect(r.samples.count == 16_000)
    _ = w // pisarz żyje dalej, nie zamknięty
}

@Test func silenceIsWrittenAsZeros() throws {
    let url = try tempURL("s.caf")
    let w = try CAFWriter(url: url, sampleRate: 16_000, channels: 1)
    try w.appendSilence(frames: 10_000)
    try w.close()
    let r = try readInt16(url)
    #expect(r.samples.count == 10_000)
    #expect(r.samples.allSatisfy { $0 == 0 })
    #expect(w.framesWritten == 10_000)
}

@Test func ownReaderMatchesSystemReader() throws {
    let url = try tempURL("system.caf")
    let w = try CAFWriter(url: url, sampleRate: 48_000, channels: 2)
    let s = sine(frames: 70_000, channels: 2)
    try w.append(s)
    let own = try CAFReader(url: url)
    #expect(own.samples == s)
    #expect(own.sampleRate == 48_000)
    #expect(own.channels == 2)
    #expect(try readInt16(url).samples == s)
}

@Test func ownReaderRejectsForeignFile() throws {
    let url = try tempURL("x.caf")
    try Data(repeating: 0x41, count: 200).write(to: url)
    #expect(throws: CAFReadError.notOurLayout("magic")) { _ = try CAFReader(url: url) }
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesRecordingTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `CAFWriter`, `CAFReader`.

- [x] **Krok 3: Implementacja.**

`Sources/MeetNotesRecording/CAFWriter.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

/// Minimalny pisarz CAF: PCM Int16 LE, przeplatany, blok `data` o rozmiarze -1.
/// Nagłówek jest kompletny od pierwszego bajtu, więc plik da się odczytać
/// w każdej chwili — także po `kill -9` (T7). Układ: `CAFLayout`.
public final class CAFWriter {
    public let url: URL
    public let sampleRate: Double
    public let channels: Int
    public private(set) var framesWritten = 0
    private let handle: FileHandle

    public init(url: URL, sampleRate: Double, channels: Int) throws {
        precondition(sampleRate > 0 && channels > 0)
        self.url = url
        self.sampleRate = sampleRate
        self.channels = channels
        FileManager.default.createFile(atPath: url.path, contents: Self.header(sampleRate: sampleRate, channels: channels))
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    static func header(sampleRate: Double, channels: Int) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func i64(_ v: Int64) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func fourCC(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        fourCC("caff"); u16(1); u16(0)
        fourCC("desc"); i64(32)
        withUnsafeBytes(of: sampleRate.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        fourCC("lpcm")
        u32(2) // kCAFLinearPCMFormatFlagIsLittleEndian
        u32(UInt32(CAFLayout.bytesPerFrame(channels: channels))) // bajtów na pakiet
        u32(1) // ramek na pakiet
        u32(UInt32(channels))
        u32(16)
        fourCC("data"); i64(-1) // rozmiar nieznany: do końca pliku
        u32(0) // licznik edycji
        assert(d.count == CAFLayout.headerSize)
        return d
    }

    /// Dopisuje próbki przeplatane. Liczba próbek musi być wielokrotnością liczby kanałów.
    public func append(_ samples: [Int16]) throws {
        precondition(samples.count % channels == 0, "niepełna ramka")
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { buf in
            Data(buffer: UnsafeBufferPointer(start: buf.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self) },
                                             count: buf.count * CAFLayout.bytesPerSample))
        }
        try handle.write(contentsOf: data)
        framesWritten += samples.count / channels
    }

    public func appendSilence(frames: Int) throws {
        var left = frames
        let block = 4_800
        while left > 0 {
            let n = min(left, block)
            try handle.write(contentsOf: Data(count: n * CAFLayout.bytesPerFrame(channels: channels)))
            framesWritten += n
            left -= n
        }
    }

    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }
}
```

`Sources/MeetNotesSessionFormat/CAFReader.swift`:

```swift
import Foundation

public enum CAFReadError: Error, Equatable {
    case tooShort
    case notOurLayout(String)
}

/// Czytnik plików zapisanych przez `CAFWriter` — i tylko takich. Sprawdza nagłówek
/// bajt po bajcie, więc cudzy albo uszkodzony plik daje błąd zamiast śmieci.
///
/// Nie używa AVFoundation celowo: `AVAudioFile.read(into:)` potrafi oddać
/// mniej ramek niż pojemność bufora (📐 64 000 ramek w pliku, 63 454 z jednego
/// wywołania), a czytelnik, który o tym zapomni, po cichu obcina końcówkę ścieżki.
public struct CAFReader: Sendable {
    public let sampleRate: Double
    public let channels: Int
    public let samples: [Int16]

    public var frames: Int { samples.count / channels }

    public init(url: URL) throws {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.count >= CAFLayout.headerSize else { throw CAFReadError.tooShort }
        func fourCC(_ at: Int) -> String { String(decoding: d[at..<(at + 4)], as: UTF8.self) }
        func u32(_ at: Int) -> UInt32 { d[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        func u64(_ at: Int) -> UInt64 { d[at..<(at + 8)].reduce(0) { $0 << 8 | UInt64($1) } }
        guard fourCC(0) == "caff" else { throw CAFReadError.notOurLayout("magic") }
        guard fourCC(8) == "desc", u64(12) == 32 else { throw CAFReadError.notOurLayout("desc") }
        guard fourCC(28) == "lpcm" else { throw CAFReadError.notOurLayout("format") }
        guard u32(32) == 2, u32(48) == 16 else { throw CAFReadError.notOurLayout("int16 le") }
        guard fourCC(52) == "data", u64(56) == UInt64.max else { throw CAFReadError.notOurLayout("data -1") }
        let ch = Int(u32(44))
        guard ch > 0 else { throw CAFReadError.notOurLayout("channels") }
        sampleRate = Double(bitPattern: u64(20))
        channels = ch
        let body = d[CAFLayout.headerSize...]
        let count = (body.count / CAFLayout.bytesPerFrame(channels: ch)) * ch
        var out = [Int16](repeating: 0, count: count)
        _ = out.withUnsafeMutableBytes { body.copyBytes(to: $0, count: count * CAFLayout.bytesPerSample) }
        // ⚠️ Poprawka po recenzji (R6): na little-endian (arm64, x86_64) bajty pliku są już
        // w kolejności pamięci. Spike robił tu `out.map { Int16(littleEndian: $0) }` — drugą
        // kopię ~1 GB przy 85-minutowej ścieżce systemowej.
        #if _endian(big)
        samples = out.map { Int16(littleEndian: $0) }
        #else
        samples = out
        #endif
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 17/17 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Mutacja (T7).** W `CAFWriter.header` zamień `fourCC("data"); i64(-1)` na `fourCC("data"); i64(0)`. `scripts/test.sh --filter MeetNotesRecordingTests` — oczekiwane: padają m.in. `fileIsReadableWithoutClose` i `ownReaderMatchesSystemReader`. Przywróć; `17/17`.

- [x] **Krok 6: Commit.**

```bash
git add Sources Tests/MeetNotesRecordingTests
git commit -m "Nagrywanie: wlasny pisarz i czytnik CAF" -m "Blok data o rozmiarze -1: plik jest poprawny w kazdej chwili, takze po kill -9. Czytnik bez AVFoundation, bo AVAudioFile.read(into:) oddaje mniej ramek niz pojemnosc bufora (63454 z 64000)."
```

---

### Zadanie A5: Pisarz ścieżki, luki i kotwice (T6, T8)

Status: ✅ zweryfikowane (6 testów).

**Pliki:**
- Utwórz: `Sources/MeetNotesRecording/AudioSource.swift`, `Sources/MeetNotesRecording/TrackWriter.swift`
- Test: `Tests/MeetNotesRecordingTests/TrackWriterTests.swift`

**Interfejsy:**
- Pobiera: `CAFWriter` (A4), `SessionJournal`, `Timebase`.
- Dostarcza: `TrackFormat(sampleRate:channels:deviceUID:)`, `AudioChunk(samples:hostTime:)` (czas hosta **pierwszej** próbki), `AudioSourceEvent` (`.chunk`, `.deviceChanged(String)`, `.failed(String)`, `.endOfStream`), `AudioSourceError` (`.permissionDenied(String)`, `.deviceUnavailable(String)`, `.coreAudio(String, Int32)`), protokół `AudioSource` (`trackID`, `prepare() throws -> TrackFormat`, `start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws`, `stop()`). `TrackWriter(trackID:url:format:journal:timebase:gapToleranceSeconds: = 0.03, clockIntervalSeconds: = 10) throws`, `write(_:) throws`, `close(hostTime:) throws`, `framesWritten`.

- [x] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesRecordingTests/TrackWriterTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func makeWriter(rate: Double = 16_000, tolerance: Double = 0.03) throws -> (TrackWriter, SessionJournal, URL) {
    let caf = try tempURL("mic_raw.caf")
    let j = try SessionJournal(url: caf.deletingLastPathComponent().appendingPathComponent("journal.jsonl"))
    let w = try TrackWriter(trackID: "mic_raw", url: caf, format: TrackFormat(sampleRate: rate, channels: 1, deviceUID: "mic"),
                            journal: j, timebase: ns, gapToleranceSeconds: tolerance)
    return (w, j, caf)
}

@Test func firstChunkIsJournaledAsFirstSample() throws {
    let (w, j, _) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: 5 * s))
    let events = try SessionJournal.read(url: j.url)
    #expect(events.first?.type == .trackFirstSample)
    #expect(events.first?.hostTime == 5 * s)
}

@Test func jumpBetweenChunksBecomesJournaledSilence() throws {
    let (w, j, caf) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 16_000, channels: 1, rate: 16_000), hostTime: 0))   // 0–1 s
    try w.write(AudioChunk(samples: sine(frames: 16_000, channels: 1, rate: 16_000), hostTime: 3 * s)) // luka 2 s
    try w.close(hostTime: 4 * s)
    let gaps = try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }
    #expect(gaps.count == 1)
    #expect(gaps[0].frameIndex == 16_000)
    #expect(gaps[0].gapFrames == 32_000)
    let r = try readInt16(caf)
    #expect(r.samples.count == 64_000)
    #expect(r.samples[16_000..<48_000].allSatisfy { $0 == 0 })
}

@Test func jitterBelowToleranceIsNotAGap() throws {
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<100 {
        try w.write(AudioChunk(samples: sine(frames: 160, channels: 1, rate: 16_000), hostTime: t))
        t += 10_000_000 + 2_000_000 // 10 ms danych, 12 ms odstępu: 2 ms jittera
    }
    #expect(try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }.isEmpty)
}

@Test func accumulatedDriftNeverInsertsSilence() throws {
    // Zegar urządzenia szybszy o 200 ppm: po 1000 porcjach suma rozjazdu
    // przekracza tolerancję, ale żadna para sąsiednich porcji — nie.
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<1_000 {
        try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
        t += 100_000_000 - 20_000 // 100 ms danych w 99,98 ms czasu hosta
    }
    #expect(try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }.isEmpty)
}

@Test func clockAnchorsAreWrittenPeriodicallyAndAfterGaps() throws {
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<250 { // 25 s po 100 ms
        try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
        t += 100_000_000
    }
    t += 1 * s // luka
    try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
    let clocks = try SessionJournal.read(url: j.url).filter { $0.type == .trackClock }
    #expect(clocks.map { $0.frameIndex } == [160_000, 320_000, 416_000])
    #expect(clocks.last?.hostTime == t)
}

@Test func closeJournalsFrameCount() throws {
    let (w, j, _) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 800, channels: 1, rate: 16_000), hostTime: 0))
    try w.close(hostTime: s)
    let closed = try SessionJournal.read(url: j.url).first { $0.type == .trackClosed }
    #expect(closed?.frames == 800)
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesRecordingTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `TrackWriter`, `TrackFormat`, `AudioChunk`.

- [x] **Krok 3: Implementacja.**

`Sources/MeetNotesRecording/AudioSource.swift`:

```swift
import Foundation

/// Format ścieżki ustalany przed startem źródła: Int16, przeplatany.
public struct TrackFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var deviceUID: String

    public init(sampleRate: Double, channels: Int, deviceUID: String) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.deviceUID = deviceUID
    }
}

/// Porcja próbek w formacie ścieżki i czas hosta jej **pierwszej** próbki.
public struct AudioChunk: Sendable {
    public var samples: [Int16]
    public var hostTime: UInt64

    public init(samples: [Int16], hostTime: UInt64) {
        self.samples = samples
        self.hostTime = hostTime
    }
}

public enum AudioSourceEvent: Sendable {
    case chunk(AudioChunk)
    case deviceChanged(String)
    case failed(String)
    case endOfStream
}

public enum AudioSourceError: Error, Equatable {
    case permissionDenied(String)
    case deviceUnavailable(String)
    case coreAudio(String, Int32)
}

/// Jedno źródło = jedna ścieżka. Dwa kroki startu: `prepare()` ustala format
/// (żeby pisarz istniał, zanim przyjdzie pierwsza próbka), `start` zaczyna dostawy.
public protocol AudioSource: AnyObject, Sendable {
    var trackID: String { get }
    func prepare() throws -> TrackFormat
    func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws
    func stop()
}
```

`Sources/MeetNotesRecording/TrackWriter.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

/// Pisze **jedną** ścieżkę do **jednego** pliku. Nie ma dostępu do innych ścieżek,
/// więc miks jest tu strukturalnie niemożliwy (spec rdzenia §4, 🔴 rozdz. 18).
///
/// Luki: porównuje czas hosta **kolejnych** porcji. Skok ponad tolerancję
/// (przepięcie urządzenia, zgubione bufory) wypełnia ciszą i zapisuje w dzienniku.
/// Dryf zegara urządzenia nie wyzwala luk, bo nie kumuluje się między dwiema
/// sąsiednimi porcjami — pochłaniają go kotwice `track.clock`.
public final class TrackWriter {
    public let trackID: String
    public let format: TrackFormat
    private let caf: CAFWriter
    private let journal: SessionJournal
    private let timebase: Timebase
    private let gapTolerance: Double
    private let clockIntervalFrames: Int
    private var expectedNextHost: UInt64?
    private var lastClockFrame = 0

    public var framesWritten: Int { caf.framesWritten }

    public init(trackID: String, url: URL, format: TrackFormat, journal: SessionJournal, timebase: Timebase,
                gapToleranceSeconds: Double = 0.03, clockIntervalSeconds: Double = 10) throws {
        self.trackID = trackID
        self.format = format
        self.caf = try CAFWriter(url: url, sampleRate: format.sampleRate, channels: format.channels)
        self.journal = journal
        self.timebase = timebase
        self.gapTolerance = gapToleranceSeconds
        self.clockIntervalFrames = Int(clockIntervalSeconds * format.sampleRate)
    }

    public func write(_ chunk: AudioChunk) throws {
        let frames = chunk.samples.count / format.channels
        guard frames > 0 else { return }
        var anchorNow = false
        if let expected = expectedNextHost {
            let jump = timebase.secondsBetween(chunk.hostTime, expected)
            if jump > gapTolerance {
                let gapFrames = Int((jump * format.sampleRate).rounded())
                try journal.append(.trackGap(trackID, frameIndex: caf.framesWritten, gapFrames: gapFrames, hostTime: chunk.hostTime))
                try caf.appendSilence(frames: gapFrames)
                anchorNow = true
            }
        } else {
            try journal.append(.trackFirstSample(trackID, hostTime: chunk.hostTime))
            lastClockFrame = 0
        }
        let firstFrame = caf.framesWritten
        if anchorNow || firstFrame - lastClockFrame >= clockIntervalFrames {
            try journal.append(.trackClock(trackID, frameIndex: firstFrame, hostTime: chunk.hostTime))
            lastClockFrame = firstFrame
        }
        try caf.append(chunk.samples)
        expectedNextHost = chunk.hostTime + timebase.ticks(seconds: Double(frames) / format.sampleRate)
    }

    public func close(hostTime: UInt64) throws {
        try journal.append(.trackClosed(trackID, frames: caf.framesWritten, hostTime: hostTime))
        try caf.close()
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 23/23 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Mutacja (dryf nie może rodzić luk).** W `TrackWriter.write` zamień `expectedNextHost = chunk.hostTime + timebase.ticks(` na `expectedNextHost = (expectedNextHost ?? chunk.hostTime) + timebase.ticks(` — oczekiwany czas zaczyna się kumulować od pierwszej porcji. `scripts/test.sh --filter jitterBelowToleranceIsNotAGap` — oczekiwane: pada (2 ms jittera na porcję kumuluje się ponad 30 ms). Przywróć; `23/23`.

- [x] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesRecording Tests/MeetNotesRecordingTests
git commit -m "Nagrywanie: pisarz sciezki z lukami i kotwicami zegara" -m "Jedna sciezka, jeden plik - miks strukturalnie niemozliwy. Luka tylko przy skoku miedzy sasiednimi porcjami, wiec dryf zegara urzadzenia nie wstawia ciszy."
```

---

### Zadanie A6: Rejestrator sesji i warunki końca (T2, T5, T9)

Status: ✅ zweryfikowane (11 testów).

**Pliki:**
- Utwórz: `Sources/MeetNotesRecording/HostClock.swift`, `Sources/MeetNotesRecording/Levels.swift`, `Sources/MeetNotesRecording/EndCondition.swift`, `Sources/MeetNotesRecording/FileSource.swift`, `Sources/MeetNotesRecording/SessionRecorder.swift`
- Test: `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift`

**Interfejsy:**
- Pobiera: `AudioSource`, `TrackWriter` (A5), `SessionJournal`, `SessionDirectory` (A3).
- Dostarcza: `HostClock` (`now() -> UInt64`), `MachHostClock()`, `ManualHostClock(_:)` z `set(_:)`. `Levels.rmsDBFS(_:) -> Double` (cisza = −160). `EndReason` (`button`, `silence`, `hardLimit`, `sourceStalled`, `endOfInput`, `diskFull`, `writeError`, `noSources`), `RecorderState`, protokół `EndCondition` (`check(_:) -> EndReason?`), `SilenceCondition(seconds:)`, `HardLimitCondition(seconds:)`, `StallCondition(seconds:)`, `[any EndCondition].standard`. `FileSource(trackID:samples:sampleRate:channels:deviceUID:startHostTime:timebase:chunkFrames:jumps:)` — emituje synchronicznie w `start`. `SessionRecorder(directory:sources:conditions: = .standard, clock: = MachHostClock(), timebase: = .current, silenceThresholdDBFS: = -50, zeroWatch: = ["system": 60])`, `start() throws`, `stop(reason:)`, `tick()`, `endReason`, `onEnded`, `static isDiskFull(_:) -> Bool`.

- [ ] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func sessionDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mn-session-\(UUID().uuidString)")
}

private final class DeniedSource: AudioSource, @unchecked Sendable {
    let trackID: String
    init(_ id: String) { trackID = id }
    func prepare() throws -> TrackFormat { throw AudioSourceError.permissionDenied("systemAudio") }
    func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
    func stop() {}
}

@Test func twoSourcesProduceTwoFilesAndAClosedSession() throws {
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 48_000, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 0, timebase: ns)
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 16_000, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 165_000_000, timebase: ns)
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .endOfInput)
    let sum = try SessionDirectory(url: dir).summarize()
    #expect(!sum.crashed)
    #expect(sum.endReason == "endOfInput")
    #expect(Set(sum.tracks.map(\.id)) == ["system", "mic_raw"])
    #expect(try CAFReader(url: dir.appendingPathComponent("system.caf")).frames == 48_000)
    #expect(try CAFReader(url: dir.appendingPathComponent("mic_raw.caf")).frames == 16_000)
}

@Test func startOffsetIsMeasuredNotAssumed() throws {
    // T2: sztuczne 500 ms opóźnienia mikrofonu ma się pojawić w podsumowaniu.
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 4_800, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 1 * s, timebase: ns)
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 1_600, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 1 * s + 500_000_000, timebase: ns)
    try SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let mic2 = try #require(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "mic_raw" })
    #expect(abs((mic2.offsetSeconds ?? 0) - 0.5) < 1e-6)
}

@Test func silenceEndsTheSession() throws {
    // T5: 30 s mowy, potem 120 s ciszy cyfrowej; warunek 60 s ciszy.
    let dir = sessionDir()
    let speech = sine(frames: 30 * 16_000, channels: 1, rate: 16_000)
    let silence = [Int16](repeating: 0, count: 120 * 16_000)
    let mic = FileSource(trackID: "mic_raw", samples: speech + silence, sampleRate: 16_000, channels: 1,
                         startHostTime: 0, timebase: ns, chunkFrames: 1_600)
    let r = SessionRecorder(directory: dir, sources: [mic], conditions: [SilenceCondition(seconds: 60)],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .silence)
    let frames = try CAFReader(url: dir.appendingPathComponent("mic_raw.caf")).frames
    #expect(frames < (30 + 120) * 16_000) // nie dociągnęła do końca pliku
    #expect(frames >= (30 + 60) * 16_000)
}

@Test func deniedPermissionIsJournaledAndSessionContinues() throws {
    // T9 (część, która nie zależy od sondy): odmowa w prepare() jest jawna.
    let dir = sessionDir()
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 1_600, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 0, timebase: ns)
    let r = SessionRecorder(directory: dir, sources: [DeniedSource("system"), mic], conditions: [],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    let sum = try SessionDirectory(url: dir).summarize()
    #expect(sum.tracks.first { $0.id == "system" }?.permissionDenied == "systemAudio")
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("system.caf").path))
    #expect(r.endReason == .endOfInput)
}

@Test func noUsableSourceEndsImmediately() throws {
    let dir = sessionDir()
    let r = SessionRecorder(directory: dir, sources: [DeniedSource("system")], conditions: [],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .noSources)
    #expect(try SessionDirectory(url: dir).summarize().endReason == "noSources")
}

@Test func stallIsDetectedByTick() throws {
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    final class Silent: AudioSource, @unchecked Sendable {
        let trackID = "system"
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
        func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
        func stop() {}
    }
    let r = SessionRecorder(directory: dir, sources: [Silent()], conditions: [StallCondition(seconds: 30)],
                            clock: clock, timebase: ns)
    try r.start()
    clock.set(29 * s); r.tick()
    #expect(r.endReason == nil)
    clock.set(31 * s); r.tick()
    #expect(r.endReason == .sourceStalled)
}

@Test func deviceSwitchGapIsFilledAndJournaled() throws {
    // T6: skok 0,5 s w środku strumienia (przepięcie słuchawek).
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 96_000, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 0, timebase: ns, jumps: [48_128: 0.5])
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let t = try #require(try SessionDirectory(url: dir).summarize().tracks.first)
    #expect(t.gaps.count == 1)
    #expect(t.gaps[0].frames == 24_000)
    #expect(try CAFReader(url: dir.appendingPathComponent("system.caf")).frames == 96_000 + 24_000)
}

@Test func existingSessionDirectoryIsNeverOverwritten() throws {
    let dir = sessionDir()
    let mk = { FileSource(trackID: "mic_raw", samples: sine(frames: 160, channels: 1, rate: 16_000), sampleRate: 16_000,
                          channels: 1, startHostTime: 0, timebase: ns) }
    try SessionRecorder(directory: dir, sources: [mk()], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    #expect(throws: JournalError.self) {
        try SessionRecorder(directory: dir, sources: [mk()], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    }
}

@Test func diskFullIsRecognized() {
    #expect(SessionRecorder.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
    #expect(SessionRecorder.isDiskFull(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
    #expect(!SessionRecorder.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
}

@Test func systemTrackOfPureZerosIsFlagged() throws {
    // T9: 70 s zer cyfrowych na ścieżce systemowej → track.failed, a nie cichy plik.
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: [Int16](repeating: 0, count: 70 * 8_000), sampleRate: 8_000,
                         channels: 1, startHostTime: 0, timebase: ns, chunkFrames: 800)
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let t = try #require(try SessionDirectory(url: dir).summarize().tracks.first)
    #expect(t.failure == "allZeros60s")
}

@Test func quietStartFollowedBySoundIsNotFlagged() throws {
    let dir = sessionDir()
    let samples = [Int16](repeating: 0, count: 30 * 8_000) + sine(frames: 8_000, channels: 1, rate: 8_000)
        + [Int16](repeating: 0, count: 60 * 8_000)
    let sys = FileSource(trackID: "system", samples: samples, sampleRate: 8_000, channels: 1,
                         startHostTime: 0, timebase: ns, chunkFrames: 800)
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    #expect(try SessionDirectory(url: dir).summarize().tracks.first?.failure == nil)
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesRecordingTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `FileSource`, `SessionRecorder`, `ManualHostClock`.

- [ ] **Krok 3: Implementacja.**

`Sources/MeetNotesRecording/HostClock.swift`:

```swift
import Foundation

/// Źródło czasu hosta. W aplikacji `mach_absolute_time`, w testach sterowany ręcznie.
public protocol HostClock: Sendable {
    func now() -> UInt64
}

public struct MachHostClock: HostClock {
    public init() {}
    public func now() -> UInt64 { mach_absolute_time() }
}

public final class ManualHostClock: HostClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    public init(_ start: UInt64 = 0) { value = start }

    public func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ v: UInt64) {
        lock.lock(); value = v; lock.unlock()
    }
}
```

`Sources/MeetNotesRecording/Levels.swift`:

```swift
import Foundation

public enum Levels {
    /// RMS w dBFS dla próbek Int16. Pusta porcja albo sama cisza cyfrowa: -160.
    public static func rmsDBFS(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return -160 }
        var sum = 0.0
        for s in samples {
            let x = Double(s) / 32_768
            sum += x * x
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(-160, 20 * log10(rms)) : -160
    }
}
```

`Sources/MeetNotesRecording/EndCondition.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

/// Powód zakończenia sesji, zapisywany w `session.ended.reason`.
public enum EndReason: String, Codable, Sendable {
    case button
    case silence
    case hardLimit
    case sourceStalled
    case endOfInput
    case diskFull
    case writeError
    case noSources
}

/// Stan widziany przez warunki końca. Czas w tikach hosta.
public struct RecorderState: Sendable {
    public var now: UInt64
    public var startedAt: UInt64
    public var lastLoudAt: UInt64
    public var lastChunkAt: UInt64
    public var timebase: Timebase
}

/// 🔴 Koniec sesji musi mieć warunek mechaniczny (W§1). Lista warunków zamiast
/// jednego `if`, żeby kalendarz dało się dołożyć bez dotykania rdzenia.
public protocol EndCondition: Sendable {
    func check(_ state: RecorderState) -> EndReason?
}

/// Cisza na **wszystkich** ścieżkach dłużej niż `seconds`.
public struct SilenceCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.lastLoudAt) >= seconds ? .silence : nil
    }
}

public struct HardLimitCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.startedAt) >= seconds ? .hardLimit : nil
    }
}

/// Żadne źródło nie dostarczyło porcji od `seconds`.
public struct StallCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.lastChunkAt) >= seconds ? .sourceStalled : nil
    }
}

public extension Array where Element == any EndCondition {
    /// Domyślny zestaw z speców: 10 min ciszy, 4 h twardego limitu, 30 s bez danych.
    static var standard: [any EndCondition] {
        [SilenceCondition(seconds: 600), HardLimitCondition(seconds: 4 * 3600), StallCondition(seconds: 30)]
    }
}
```

`Sources/MeetNotesRecording/FileSource.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

/// Źródło z próbek w pamięci. Deterministyczne — bez niego nie ma powtarzalnych
/// testów, bo mikrofonu i głośników nie da się zaskryptować (spec rdzenia §4).
/// Emituje **synchronicznie** w `start`, porcja po porcji, z syntetycznym czasem hosta.
public final class FileSource: AudioSource, @unchecked Sendable {
    public let trackID: String
    private let samples: [Int16]
    private let format: TrackFormat
    private let startHostTime: UInt64
    private let timebase: Timebase
    private let chunkFrames: Int
    /// indeks ramki → dodatkowy skok czasu hosta w sekundach przed tą ramką
    private let jumps: [Int: Double]
    private let lock = NSLock()
    private var stopped = false

    public init(trackID: String, samples: [Int16], sampleRate: Double, channels: Int, deviceUID: String = "file",
                startHostTime: UInt64, timebase: Timebase, chunkFrames: Int = 1_024, jumps: [Int: Double] = [:]) {
        self.trackID = trackID
        self.samples = samples
        self.format = TrackFormat(sampleRate: sampleRate, channels: channels, deviceUID: deviceUID)
        self.startHostTime = startHostTime
        self.timebase = timebase
        self.chunkFrames = chunkFrames
        self.jumps = jumps
    }

    public func prepare() throws -> TrackFormat { format }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        let ch = format.channels
        let totalFrames = samples.count / ch
        var frame = 0
        var extra = 0.0
        while frame < totalFrames {
            lock.lock(); let s = stopped; lock.unlock()
            if s { return }
            let n = min(chunkFrames, totalFrames - frame)
            for (at, secs) in jumps where at >= frame && at < frame + n { extra += secs }
            let host = startHostTime + timebase.ticks(seconds: Double(frame) / format.sampleRate + extra)
            handler(.chunk(AudioChunk(samples: Array(samples[(frame * ch)..<((frame + n) * ch)]), hostTime: host)))
            frame += n
        }
        handler(.endOfStream)
    }

    public func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }
}
```

`Sources/MeetNotesRecording/SessionRecorder.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

/// Spina źródła, pisarzy, dziennik i warunki końca. Jedyny moduł widzący całość
/// (spec rdzenia §4). Nie wie nic o ASR.
///
/// Współbieżność: porcje przychodzą z kolejek źródeł; cały stan chroni jeden
/// `NSLock`. Źródeł nie zatrzymujemy pod blokadą — `AudioDeviceStop` czeka na
/// trwające wywołanie IOProc, które może właśnie czekać na tę blokadę.
public final class SessionRecorder: @unchecked Sendable {
    public let directory: SessionDirectory
    private let sources: [any AudioSource]
    private let conditions: [any EndCondition]
    private let clock: any HostClock
    private let timebase: Timebase
    private let silenceThreshold: Double
    private let zeroWatch: [String: Double]
    private let lock = NSLock()

    private var journal: SessionJournal?
    private var writers: [String: TrackWriter] = [:]
    private var started: [any AudioSource] = []
    private var ended: Set<String> = []
    private var startedAt: UInt64 = 0
    private var lastLoudAt: UInt64 = 0
    private var lastChunkAt: UInt64 = 0
    private var finishing = false
    private var zeroFirstChunk: [String: UInt64] = [:]
    private var zeroResolved: Set<String> = []
    public private(set) var endReason: EndReason?

    public var onEnded: (@Sendable (EndReason) -> Void)?

    public init(directory: URL, sources: [any AudioSource], conditions: [any EndCondition] = .standard,
                clock: any HostClock = MachHostClock(), timebase: Timebase = .current,
                silenceThresholdDBFS: Double = -50, zeroWatch: [String: Double] = ["system": 60]) {
        self.directory = SessionDirectory(url: directory)
        self.sources = sources
        self.conditions = conditions
        self.clock = clock
        self.timebase = timebase
        self.silenceThreshold = silenceThresholdDBFS
        self.zeroWatch = zeroWatch
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let journal = try SessionJournal(url: directory.journalURL)
        let now = clock.now()
        try journal.append(.sessionStarted(hostTime: now, timebase: timebase, wallClock: Date()))

        var ready: [(any AudioSource, TrackWriter)] = []
        for source in sources {
            do {
                let fmt = try source.prepare()
                let writer = try TrackWriter(trackID: source.trackID, url: directory.trackURL(source.trackID),
                                             format: fmt, journal: journal, timebase: timebase)
                try journal.append(.trackOpened(source.trackID, hostTime: clock.now(), sampleRate: fmt.sampleRate,
                                                channels: fmt.channels, deviceUID: fmt.deviceUID))
                ready.append((source, writer))
            } catch AudioSourceError.permissionDenied(let permission) {
                try journal.append(.trackPermissionDenied(source.trackID, permission: permission,
                                                          detection: "prepare", hostTime: clock.now()))
            } catch {
                try journal.append(.trackFailed(source.trackID, reason: "\(error)", hostTime: clock.now()))
            }
        }

        lock.lock()
        self.journal = journal
        for (s, w) in ready { writers[s.trackID] = w }
        started = ready.map { $0.0 }
        startedAt = now
        lastLoudAt = now
        lastChunkAt = now
        lock.unlock()

        if ready.isEmpty {
            finish(.noSources)
            return
        }
        for (source, _) in ready {
            let id = source.trackID
            do {
                try source.start { [weak self] event in self?.handle(trackID: id, event) }
            } catch {
                try? journal.append(.trackFailed(id, reason: "\(error)", hostTime: clock.now()))
            }
        }
    }

    /// Przycisk „Stop".
    public func stop(reason: EndReason = .button) { finish(reason) }

    /// Warunki zależne od zegara ściennego (np. brak danych). W aplikacji co sekundę.
    public func tick() {
        let now = clock.now()
        lock.lock()
        let reason = finishing ? nil : evaluateLocked(now: now)
        lock.unlock()
        if let reason { finish(reason) }
    }

    private func handle(trackID: String, _ event: AudioSourceEvent) {
        var reason: EndReason?
        lock.lock()
        if !finishing, let journal {
            switch event {
            case .chunk(let chunk):
                do {
                    try writers[trackID]?.write(chunk)
                    watchZerosLocked(trackID: trackID, chunk: chunk, journal: journal)
                    lastChunkAt = max(lastChunkAt, chunk.hostTime)
                    if Levels.rmsDBFS(chunk.samples) > silenceThreshold { lastLoudAt = max(lastLoudAt, chunk.hostTime) }
                    reason = evaluateLocked(now: chunk.hostTime)
                } catch {
                    reason = Self.isDiskFull(error) ? .diskFull : .writeError
                }
            case .deviceChanged(let uid):
                try? journal.append(.deviceChanged(trackID, deviceUID: uid, hostTime: clock.now()))
            case .failed(let why):
                try? journal.append(.trackFailed(trackID, reason: why, hostTime: clock.now()))
            case .endOfStream:
                ended.insert(trackID)
                if ended.count == started.count { reason = .endOfInput }
            }
        }
        lock.unlock()
        if let reason { finish(reason) }
    }

    /// T9: ścieżka złożona z samych zer cyfrowych przez `zeroWatch[trackID]`
    /// sekund to najpewniej odmowa uprawnienia, a nie cisza — zapisujemy to jawnie,
    /// zamiast oddać „nagranie" pełne zer. Sesji nie przerywamy: prawdziwa cisza
    /// na starcie spotkania też się zdarza.
    private func watchZerosLocked(trackID: String, chunk: AudioChunk, journal: SessionJournal) {
        guard let window = zeroWatch[trackID], !zeroResolved.contains(trackID) else { return }
        if chunk.samples.contains(where: { $0 != 0 }) {
            zeroResolved.insert(trackID)
            return
        }
        let first = zeroFirstChunk[trackID] ?? chunk.hostTime
        zeroFirstChunk[trackID] = first
        if timebase.secondsBetween(chunk.hostTime, first) >= window {
            try? journal.append(.trackFailed(trackID, reason: "allZeros\(Int(window))s", hostTime: chunk.hostTime))
            zeroResolved.insert(trackID)
        }
    }

    private func evaluateLocked(now: UInt64) -> EndReason? {
        let state = RecorderState(now: now, startedAt: startedAt, lastLoudAt: lastLoudAt,
                                  lastChunkAt: lastChunkAt, timebase: timebase)
        for c in conditions { if let r = c.check(state) { return r } }
        return nil
    }

    private func finish(_ reason: EndReason) {
        lock.lock()
        if finishing { lock.unlock(); return }
        finishing = true
        endReason = reason
        let toStop = started
        lock.unlock()

        for s in toStop { s.stop() } // bez blokady — patrz komentarz klasy

        lock.lock()
        let now = clock.now()
        for w in writers.values { try? w.close(hostTime: now) }
        try? journal?.append(.sessionEnded(reason: reason.rawValue, hostTime: now))
        _ = try? directory.rebuildSummaryFile()
        try? journal?.close()
        lock.unlock()
        onEnded?(reason)
    }

    static func isDiskFull(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isDiskFull(u) }
        return false
    }
}
```

- [ ] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 34/34 testów uruchomionych i zaliczonych.`

- [ ] **Krok 5: Mutacja (T5).** W `SilenceCondition.check` zamień `>= seconds ? .silence : nil` na `>= seconds * 100 ? .silence : nil`. `scripts/test.sh --filter silenceEndsTheSession` — oczekiwane: pada (`endOfInput` zamiast `silence`). Przywróć.

- [ ] **Krok 6: Mutacja (T9).** W `watchZerosLocked` usuń linię z `try? journal.append(.trackFailed(trackID, reason: "allZeros`. `scripts/test.sh --filter systemTrackOfPureZerosIsFlagged` — oczekiwane: pada. Przywróć; `34/34`.

- [ ] **Krok 7: Commit.**

```bash
git add Sources/MeetNotesRecording Tests/MeetNotesRecordingTests
git commit -m "Nagrywanie: rejestrator sesji i mechaniczne warunki konca" -m "Cisza, twardy limit, brak danych - lista, nie jeden if. Odmowa uprawnienia jawna w dzienniku, sesja trwa z pozostalymi zrodlami. Sciezka systemowa z samych zer przez 60 s oznaczona jako track.failed."
```

---

### Zadanie A7: Konwersja formatu i miary dopasowania (T1, T3, T4)

Status: ✅ zweryfikowane (7 testów).

**Pliki:**
- Utwórz: `Sources/MeetNotesRecording/FormatConverter.swift`, `Sources/MeetNotesRecording/AudioFit.swift`
- Test: `Tests/MeetNotesRecordingTests/FormatConverterTests.swift`, `Tests/MeetNotesRecordingTests/AudioFitTests.swift`

**Interfejsy:**
- Pobiera: `Levels` (A6), `AudioSourceError` (A5).
- Dostarcza: `FormatConverter(input: AVAudioFormat, sampleRate:channels:) throws`, `convert(_: AVAudioPCMBuffer) -> [Int16]` (bez ditheringu, bez rozgrzewania, bufory krojone po 1024 ramki). `AudioFit.fit(reference:recorded:maxLagFrames:) -> Result` (`gain`, `rSquared`, `lagFrames`, `correlation`), `mono(_:channels:) -> [Float]`, `resample(_:from:to:) -> [Float]` (liniowe, tylko do analizy).

- [ ] **Krok 1: Testy, które padną.** Utwórz oba pliki testów:

`Tests/MeetNotesRecordingTests/FormatConverterTests.swift`:

```swift
import AVFoundation
import Foundation
import Testing
@testable import MeetNotesRecording

private func floatBuffer(frames: Int, rate: Double, channels: Int, hz: Double) throws -> AVAudioPCMBuffer {
    let fmt = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                         channels: AVAudioChannelCount(channels), interleaved: false))
    let b = try #require(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)))
    b.frameLength = AVAudioFrameCount(frames)
    for c in 0..<channels {
        for i in 0..<frames { b.floatChannelData![c][i] = Float(0.5 * sin(2 * .pi * hz * Double(i) / rate)) }
    }
    return b
}

@Test func downsamplesStereo48kToMono16k() throws {
    let src = try floatBuffer(frames: 4_800, rate: 48_000, channels: 2, hz: 440)
    let conv = try FormatConverter(input: src.format, sampleRate: 16_000, channels: 1)
    var out: [Int16] = []
    for _ in 0..<10 { out += conv.convert(src) } // 10 × 100 ms
    #expect(abs(out.count - 16_000) <= 1) // bez przetrzymywania: etykieta czasu hosta zostaje prawdziwa
    #expect(Levels.rmsDBFS(out) > -12) // sinus 0,5 ≈ -9 dBFS przetrwał
}

@Test func sameRateConversionKeepsFrameCountAndShape() throws {
    let src = try floatBuffer(frames: 4_800, rate: 48_000, channels: 2, hz: 1_000)
    let conv = try FormatConverter(input: src.format, sampleRate: 48_000, channels: 2)
    let out = conv.convert(src)
    #expect(out.count == 4_800 * 2) // bufor większy niż wewnętrzny limit 4096 wychodzi w całości
    let expected = sine(frames: 4_800, channels: 2, rate: 48_000, hz: 1_000)
    let fit = AudioFit.fit(reference: AudioFit.mono(expected, channels: 2), recorded: AudioFit.mono(out, channels: 2), maxLagFrames: 0)
    #expect(fit.rSquared > 0.999) // T1 na poziomie konwersji: Float32 → Int16 bez zniekształceń
}

@Test func everyCallReturnsItsOwnFramesForTypicalHALBuffers() throws {
    // 512 ramek to typowy bufor IOProc. Wyjście każdego wywołania = jego wejście,
    // więc czas hosta porcji wejściowej jest czasem jej pierwszej próbki wyjścia.
    let src = try floatBuffer(frames: 512, rate: 48_000, channels: 2, hz: 440)
    let conv = try FormatConverter(input: src.format, sampleRate: 48_000, channels: 2)
    for _ in 0..<20 { #expect(conv.convert(src).count == 1_024) }
}
```

`Tests/MeetNotesRecordingTests/AudioFitTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesRecording

private func noise(_ n: Int, seed: UInt64) -> [Float] {
    var x = seed
    return (0..<n).map { _ in
        x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: x >> 11) % 2_000 - 1_000) / 4_000 // średnia zero
    }
}

@Test func identityGivesRSquaredOne() {
    let a = noise(8_000, seed: 1)
    let r = AudioFit.fit(reference: a, recorded: a, maxLagFrames: 10)
    #expect(r.rSquared > 0.9999)
    #expect(abs(r.gain - 1) < 1e-6)
    #expect(r.lagFrames == 0)
}

@Test func findsDelayedAndAttenuatedCopy() {
    // Profil MacParakeeta z rozdz. 18: system w nagraniu ze wzmocnieniem 0,06 i opóźnieniem.
    let a = noise(8_000, seed: 2)
    let delayed = [Float](repeating: 0, count: 240) + a.map { $0 * 0.06 }
    let r = AudioFit.fit(reference: a, recorded: delayed, maxLagFrames: 400)
    #expect(r.lagFrames == 240)
    #expect(abs(r.gain - 0.06) < 1e-3)
}

@Test func independentSignalsHaveLowCorrelation() {
    // T3: po AEC korelacja mikrofonu z systemem ≤ 0,12 (rozdz. 7).
    let r = AudioFit.fit(reference: noise(8_000, seed: 3), recorded: noise(8_000, seed: 4), maxLagFrames: 50)
    #expect(abs(r.correlation) < 0.12)
}

@Test func resampleKeepsDuration() {
    let x = [Float](repeating: 0.1, count: 48_000)
    #expect(AudioFit.resample(x, from: 48_000, to: 16_000).count == 16_000)
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesRecordingTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `FormatConverter`, `AudioFit`.

- [ ] **Krok 3: Implementacja.**

`Sources/MeetNotesRecording/FormatConverter.swift`:

```swift
@preconcurrency import AVFoundation
import Foundation

/// Strumieniowa konwersja dowolnego formatu urządzenia na format ścieżki:
/// Int16, przeplatany, stała częstotliwość. Jeden egzemplarz na strumień —
/// konwerter trzyma stan filtra między wywołaniami. Bez ditheringu.
public final class FormatConverter {
    public let input: AVAudioFormat
    public let output: AVAudioFormat
    private let converter: AVAudioConverter

    public init(input: AVAudioFormat, sampleRate: Double, channels: Int) throws {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                      channels: AVAudioChannelCount(channels), interleaved: true),
              let conv = AVAudioConverter(from: input, to: out) else {
            throw AudioSourceError.coreAudio("AVAudioConverter", -1)
        }
        conv.dither = false
        // Bez „rozgrzewania" filtra: wyjście zaczyna się razem z wejściem, więc czas
        // hosta pierwszej próbki wejścia jest też czasem pierwszej próbki wyjścia.
        conv.primeMethod = .none
        if input.channelCount > 1 && channels == 1 { conv.downmix = true }
        self.input = input
        self.output = out
        self.converter = conv
    }

    /// Największy plasterek podawany konwerterowi naraz. 📐 Dla buforów do 512
    /// ramek wyjście zgadza się z wejściem co do ramki przy każdym wywołaniu;
    /// bufor 4800 ramek (typowy dla `installTap`) wychodzi obcięty do 4096,
    /// a reszta wypada z następnym buforem — z cudzym czasem hosta.
    static let sliceFrames: AVAudioFrameCount = 1_024

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        guard buffer.frameLength > 0 else { return [] }
        if buffer.frameLength <= Self.sliceFrames { return convertSlice(buffer) }
        var out: [Int16] = []
        var start: AVAudioFrameCount = 0
        while start < buffer.frameLength {
            let n = min(Self.sliceFrames, buffer.frameLength - start)
            if let slice = Self.slice(buffer, from: start, count: n) { out += convertSlice(slice) }
            start += n
        }
        return out
    }

    private func convertSlice(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        let ratio = output.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, st in
            if supplied {
                st.pointee = .noDataNow
                return nil
            }
            supplied = true
            st.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, let p = out.int16ChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: p[0], count: Int(out.frameLength) * Int(output.channelCount)))
    }

    /// Kopia ramek [from, from+count) — działa dla układu przeplatanego i nie.
    static func slice(_ b: AVAudioPCMBuffer, from: AVAudioFrameCount, count: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: count) else { return nil }
        dst.frameLength = count
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: b.audioBufferList))
        let out = UnsafeMutableAudioBufferListPointer(dst.mutableAudioBufferList)
        for i in 0..<min(src.count, out.count) {
            guard let s = src[i].mData, let d = out[i].mData, b.frameLength > 0 else { continue }
            let bytesPerFrame = Int(src[i].mDataByteSize) / Int(b.frameLength)
            memcpy(d, s.advanced(by: Int(from) * bytesPerFrame), Int(count) * bytesPerFrame)
            out[i].mDataByteSize = UInt32(Int(count) * bytesPerFrame)
        }
        return dst
    }
}
```

`Sources/MeetNotesRecording/AudioFit.swift`:

```swift
import Foundation

/// Miary z pomiarów w rozdz. 18, jako funkcje: dopasowanie „nagranie ≈ a·wzorzec"
/// z przeszukaniem opóźnienia. Podstawa testów odbiorczych T1, T3, T4.
public enum AudioFit {
    public struct Result: Equatable, Sendable {
        public var gain: Double
        public var rSquared: Double
        public var lagFrames: Int
        public var correlation: Double
    }

    /// Najlepsze dopasowanie `recorded ≈ gain · reference(t - lag)` dla lag w [0, maxLag].
    /// Obie tablice: mono, ta sama częstotliwość.
    public static func fit(reference: [Float], recorded: [Float], maxLagFrames: Int) -> Result {
        var best = Result(gain: 0, rSquared: 0, lagFrames: 0, correlation: 0)
        guard !reference.isEmpty, !recorded.isEmpty else { return best }
        for lag in 0...max(0, maxLagFrames) {
            let n = min(reference.count, recorded.count - lag)
            guard n > 0 else { break }
            var sxy = 0.0, sxx = 0.0, syy = 0.0
            for i in 0..<n {
                let x = Double(reference[i]), y = Double(recorded[i + lag])
                sxy += x * y; sxx += x * x; syy += y * y
            }
            guard sxx > 0, syy > 0 else { continue }
            let gain = sxy / sxx
            var ssRes = 0.0
            for i in 0..<n {
                let e = Double(recorded[i + lag]) - gain * Double(reference[i])
                ssRes += e * e
            }
            let r2 = 1 - ssRes / syy
            if r2 > best.rSquared {
                best = Result(gain: gain, rSquared: r2, lagFrames: lag, correlation: sxy / (sxx * syy).squareRoot())
            }
        }
        return best
    }

    public static func mono(_ interleaved: [Int16], channels: Int) -> [Float] {
        guard channels > 1 else { return interleaved.map { Float($0) / 32_768 } }
        var out = [Float](repeating: 0, count: interleaved.count / channels)
        for f in out.indices {
            var sum: Float = 0
            for c in 0..<channels { sum += Float(interleaved[f * channels + c]) }
            out[f] = sum / Float(channels) / 32_768
        }
        return out
    }

    /// Przepróbkowanie liniowe do analizy (nie do zapisu): obie ścieżki na 16 kHz
    /// przed dopasowaniem — T3 i T4 porównują 48 kHz stereo z 16 kHz mono.
    public static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !x.isEmpty else { return x }
        let n = Int(Double(x.count) * to / from)
        return (0..<n).map { i in
            let pos = Double(i) * from / to
            let j = Int(pos), frac = Float(pos - Double(j))
            return j + 1 < x.count ? x[j] * (1 - frac) + x[j + 1] * frac : x[min(j, x.count - 1)]
        }
    }
}
```

- [ ] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 41/41 testów uruchomionych i zaliczonych.`

- [ ] **Krok 5: Mutacja (przetrzymywanie ramek).** Zamień `static let sliceFrames: AVAudioFrameCount = 1_024` na `= 1_000_000`. `scripts/test.sh --filter sameRateConversionKeepsFrameCountAndShape` — oczekiwane: pada (8192 zamiast 9600 próbek, 📐 w spike'u). Przywróć; `41/41`.

- [ ] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesRecording Tests/MeetNotesRecordingTests
git commit -m "Nagrywanie: konwersja formatu bez przetrzymywania ramek, miary R2" -m "AVAudioConverter trzyma ramki przy buforach ponad 4096 i rozgrzewa filtr - obie rzeczy przesuwalyby probki wzgledem czasu hosta. Plasterki po 1024, primeMethod none."
```

---

### Zadanie A8: Źródła sprzętowe i sprawdzenie dźwięku systemowego

Status: 🔧 skompilowane (źródła sprzętowe nigdy nie uruchomione) + ✅ `SystemAudioCheck.evaluate` (3 testy).

**Pliki:**
- Utwórz: `Sources/MeetNotesRecording/CoreAudioDevices.swift`, `Sources/MeetNotesRecording/HALCapture.swift`, `Sources/MeetNotesRecording/DeviceWatcher.swift`, `Sources/MeetNotesRecording/SystemTapSource.swift`, `Sources/MeetNotesRecording/MicrophoneSources.swift`, `Sources/MeetNotesRecording/SystemAudioCheck.swift`
- Test: `Tests/MeetNotesRecordingTests/SystemAudioCheckTests.swift`

**Interfejsy:**
- Pobiera: `FormatConverter` (A7), `AudioSource` (A5), `Levels` (A6).
- Dostarcza: `CoreAudioDevices.defaultOutputDevice()`, `defaultInputDevice()`, `uid(of:)`, `inputFormat(of:)`, `tapFormat(of:)`. `SystemTapSource()` (`trackID = "system"`), `RawMicrophoneSource()` (`"mic_raw"`, 16 kHz), `VoiceProcessedMicrophoneSource()` (`"mic_aec"`, 16 kHz). `SystemAudioCheckResult` (`.works(peakDBFS:)`, `.silent(peakDBFS:)`, `.failed(String)`), `SystemAudioCheck.evaluate(levelsDBFS:threshold: = -45)`, `SystemAudioCheck.run(timeout: = 1.5) async`.

⚠️ Tego kodu nie da się sprawdzić testem jednostkowym: mikrofonu i głośników nie da się zaskryptować. Działanie sprawdza A10 na sprzęcie.

- [ ] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesRecordingTests/SystemAudioCheckTests.swift`:

```swift
import Testing
@testable import MeetNotesRecording

@Test func toneAboveThresholdMeansWorking() {
    #expect(SystemAudioCheck.evaluate(levelsDBFS: [-160, -160, -23, -160]) == .works(peakDBFS: -23))
}

@Test func onlyZerosMeansSilent() {
    // Tak wygląda odmowa uprawnienia, jeśli system oddaje zera zamiast błędu.
    #expect(SystemAudioCheck.evaluate(levelsDBFS: [-160, -160, -160]) == .silent(peakDBFS: -160))
}

@Test func noChunksAtAllMeansSilent() {
    #expect(SystemAudioCheck.evaluate(levelsDBFS: []) == .silent(peakDBFS: -160))
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter SystemAudioCheck` — oczekiwane: kod `1`, `cannot find 'SystemAudioCheck' in scope`.

- [ ] **Krok 3: Implementacja.**

`Sources/MeetNotesRecording/CoreAudioDevices.swift`:

```swift
import AVFoundation
import CoreAudio
import Foundation

/// Cienkie opakowania na właściwości Core Audio.
public enum CoreAudioDevices {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func defaultOutputDevice() throws -> AudioObjectID {
        try systemDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func defaultInputDevice() throws -> AudioObjectID {
        try systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func systemDevice(_ selector: AudioObjectPropertySelector) throws -> AudioObjectID {
        var addr = address(selector)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        guard st == noErr, id != kAudioObjectUnknown else { throw AudioSourceError.deviceUnavailable("selector \(selector)") }
        return id
    }

    public static func uid(of device: AudioObjectID) throws -> String {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid)
        guard st == noErr, let v = uid?.takeRetainedValue() else { throw AudioSourceError.coreAudio("DeviceUID", st) }
        return v as String
    }

    /// Format strumienia wejściowego urządzenia (albo urządzenia zbiorczego z tapem).
    public static func inputFormat(of device: AudioObjectID) throws -> AVAudioFormat {
        var addr = address(kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeInput)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &asbd)
        guard st == noErr, let f = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioSourceError.coreAudio("StreamFormat", st)
        }
        return f
    }

    public static func tapFormat(of tap: AudioObjectID) throws -> AVAudioFormat {
        var addr = address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
        guard st == noErr, let f = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioSourceError.coreAudio("TapFormat", st)
        }
        return f
    }
}
```

`Sources/MeetNotesRecording/HALCapture.swift`:

```swift
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// IOProc na urządzeniu Core Audio → konwersja → porcje z czasem hosta pierwszej
/// próbki (`mHostTime` wejścia). Wspólne dla tapu (urządzenie zbiorcze)
/// i surowego mikrofonu.
final class HALCapture: @unchecked Sendable {
    private let device: AudioObjectID
    private let inputFormat: AVAudioFormat
    private let converter: FormatConverter
    private let onChunk: @Sendable (AudioChunk) -> Void
    private let queue = DispatchQueue(label: "meetnotes.hal", qos: .userInteractive)
    private var procID: AudioDeviceIOProcID?

    init(device: AudioObjectID, inputFormat: AVAudioFormat, sampleRate: Double, channels: Int,
         onChunk: @escaping @Sendable (AudioChunk) -> Void) throws {
        self.device = device
        self.inputFormat = inputFormat
        self.converter = try FormatConverter(input: inputFormat, sampleRate: sampleRate, channels: channels)
        self.onChunk = onChunk
    }

    func start() throws {
        let fmt = inputFormat
        let conv = converter
        let emit = onChunk
        var proc: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, inInputData, inInputTime, _, _ in
            guard inInputTime.pointee.mFlags.contains(.hostTimeValid),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            let samples = conv.convert(buf)
            if !samples.isEmpty { emit(AudioChunk(samples: samples, hostTime: inInputTime.pointee.mHostTime)) }
        }
        guard st == noErr, let proc else { throw AudioSourceError.coreAudio("CreateIOProc", st) }
        procID = proc
        let s2 = AudioDeviceStart(device, proc)
        guard s2 == noErr else { throw AudioSourceError.coreAudio("DeviceStart", s2) }
    }

    func stop() {
        guard let proc = procID else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        procID = nil
    }
}
```

`Sources/MeetNotesRecording/DeviceWatcher.swift`:

```swift
import CoreAudio
import Foundation

/// Obserwator zmiany domyślnego urządzenia (wejścia albo wyjścia). Bez niego
/// przepięcie słuchawek urywa nagranie (W§1 🆕). Narada instaluje trzy takie.
final class DeviceWatcher: @unchecked Sendable {
    private var addr: AudioObjectPropertyAddress
    private let queue = DispatchQueue(label: "meetnotes.devicewatcher")
    private var block: AudioObjectPropertyListenerBlock?

    init(selector: AudioObjectPropertySelector) {
        addr = CoreAudioDevices.address(selector)
    }

    func start(_ onChange: @escaping @Sendable () -> Void) {
        let b: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        block = b
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, b)
    }

    func stop() {
        guard let b = block else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, b)
        block = nil
    }
}
```

`Sources/MeetNotesRecording/SystemTapSource.swift`:

```swift
import AVFoundation
import CoreAudio
import Foundation

/// Kanał „Oni": process tap Core Audio na całym wyjściu systemu, przez urządzenie
/// zbiorcze związane z bieżącym wyjściem (spec rdzenia §2, droga Narady).
/// Przy zmianie domyślnego wyjścia przebudowuje tap na nowym urządzeniu; luka
/// wychodzi w dzienniku przez skok czasu hosta (TrackWriter).
/// Format ścieżki ustalany raz, przy `prepare()`: częstotliwość i kanały tapu,
/// Int16. Po przepięciu na urządzenie o innej częstotliwości konwerter
/// przepróbkowuje do formatu ścieżki — nigdy nie pisze w złej częstotliwości.
public final class SystemTapSource: AudioSource, @unchecked Sendable {
    public let trackID = "system"
    private let lock = NSLock()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var capture: HALCapture?
    private var format: TrackFormat?
    private var handler: (@Sendable (AudioSourceEvent) -> Void)?
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultOutputDevice)

    public init() {}

    public func prepare() throws -> TrackFormat {
        let (tapFmt, uid) = try build()
        let f = TrackFormat(sampleRate: tapFmt.sampleRate, channels: Int(tapFmt.channelCount), deviceUID: uid)
        lock.lock(); format = f; lock.unlock()
        return f
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        lock.lock(); self.handler = handler; lock.unlock()
        try startCapture()
        watcher.start { [weak self] in self?.rebuild() }
    }

    public func stop() {
        watcher.stop()
        lock.lock(); let c = capture; capture = nil; lock.unlock()
        c?.stop()
        teardown()
    }

    /// Tworzy tap i urządzenie zbiorcze na bieżącym wyjściu. Zwraca format tapu i UID wyjścia.
    private func build() throws -> (AVAudioFormat, String) {
        let output = try CoreAudioDevices.defaultOutputDevice()
        let outputUID = try CoreAudioDevices.uid(of: output)
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        desc.name = "meetnotes-system"
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw AudioSourceError.coreAudio("CreateProcessTap", st) }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "meetnotes-tap",
            kAudioAggregateDeviceUIDKey: "meetnotes-tap-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        let st2 = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard st2 == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw AudioSourceError.coreAudio("CreateAggregateDevice", st2)
        }
        let fmt = try CoreAudioDevices.tapFormat(of: tapID)
        lock.lock(); tap = tapID; aggregate = aggID; lock.unlock()
        return (fmt, outputUID)
    }

    private func startCapture() throws {
        lock.lock()
        guard let f = format, let h = handler else { lock.unlock(); return }
        let agg = aggregate, tapID = tap
        lock.unlock()
        let c = try HALCapture(device: agg, inputFormat: try CoreAudioDevices.tapFormat(of: tapID),
                               sampleRate: f.sampleRate, channels: f.channels) { h(.chunk($0)) }
        try c.start()
        lock.lock(); capture = c; lock.unlock()
    }

    private func teardown() {
        lock.lock()
        let agg = aggregate, tapID = tap
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        lock.unlock()
        if agg != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agg) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    }

    private func rebuild() {
        lock.lock(); let c = capture; capture = nil; let h = handler; lock.unlock()
        c?.stop()
        teardown()
        do {
            let (_, uid) = try build()
            try startCapture()
            h?(.deviceChanged(uid))
        } catch {
            h?(.failed("rebuild: \(error)"))
        }
    }
}
```

`Sources/MeetNotesRecording/MicrophoneSources.swift`:

```swift
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

enum MicrophonePermission {
    static func check() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: throw AudioSourceError.permissionDenied("microphone")
        default: return
        }
    }
}

/// Kanał „Ja", surowy: HAL bez żadnego przetwarzania, 16 kHz mono (spec rdzenia §5).
public final class RawMicrophoneSource: AudioSource, @unchecked Sendable {
    public let trackID = "mic_raw"
    public static let sampleRate = 16_000.0
    private let lock = NSLock()
    private var capture: HALCapture?
    private var handler: (@Sendable (AudioSourceEvent) -> Void)?
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultInputDevice)

    public init() {}

    public func prepare() throws -> TrackFormat {
        try MicrophonePermission.check()
        let dev = try CoreAudioDevices.defaultInputDevice()
        return TrackFormat(sampleRate: Self.sampleRate, channels: 1, deviceUID: try CoreAudioDevices.uid(of: dev))
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        lock.lock(); self.handler = handler; lock.unlock()
        try open()
        watcher.start { [weak self] in self?.reopen() }
    }

    public func stop() {
        watcher.stop()
        lock.lock(); let c = capture; capture = nil; lock.unlock()
        c?.stop()
    }

    @discardableResult
    private func open() throws -> String {
        let dev = try CoreAudioDevices.defaultInputDevice()
        lock.lock(); let h = handler; lock.unlock()
        guard let h else { return "" }
        let c = try HALCapture(device: dev, inputFormat: try CoreAudioDevices.inputFormat(of: dev),
                               sampleRate: Self.sampleRate, channels: 1) { h(.chunk($0)) }
        try c.start()
        lock.lock(); capture = c; lock.unlock()
        return try CoreAudioDevices.uid(of: dev)
    }

    private func reopen() {
        lock.lock(); let c = capture; capture = nil; let h = handler; lock.unlock()
        c?.stop()
        do { h?(.deviceChanged(try open())) } catch { h?(.failed("reopen: \(error)")) }
    }
}

/// Kanał „Ja" po platformowym AEC (`setVoiceProcessingEnabled`). Kopia obok
/// surowego — decyzja o AEC zostaje odwracalna (spec rdzenia §2).
/// 🔴 Przetwarzanie głosu domyślnie ścisza inne aplikacje, w tym Teams, i to
/// ściszenie trafiłoby też do kanału systemowego — ustawiamy je na minimum.
public final class VoiceProcessedMicrophoneSource: AudioSource, @unchecked Sendable {
    public let trackID = "mic_aec"
    public static let sampleRate = 16_000.0
    private let engine = AVAudioEngine()
    private var converter: FormatConverter?

    public init() {}

    public func prepare() throws -> TrackFormat {
        try MicrophonePermission.check()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        let dev = try CoreAudioDevices.defaultInputDevice()
        converter = try FormatConverter(input: input.outputFormat(forBus: 0), sampleRate: Self.sampleRate, channels: 1)
        return TrackFormat(sampleRate: Self.sampleRate, channels: 1, deviceUID: try CoreAudioDevices.uid(of: dev))
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        guard let conv = converter else { throw AudioSourceError.deviceUnavailable("not prepared") }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buf, when in
            guard when.isHostTimeValid else { return }
            let s = conv.convert(buf)
            if !s.isEmpty { handler(.chunk(AudioChunk(samples: s, hostTime: when.hostTime))) }
        }
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

`Sources/MeetNotesRecording/SystemAudioCheck.swift`:

```swift
@preconcurrency import AVFoundation
import Foundation

public enum SystemAudioCheckResult: Equatable, Sendable {
    /// Tap usłyszał dźwięk testowy.
    case works(peakDBFS: Double)
    /// Tap działa, ale dźwięku nie usłyszał — odmowa uprawnienia albo wyciszenie.
    case silent(peakDBFS: Double)
    case failed(String)
}

/// Sprawdzenie **działania**, a nie flagi uprawnienia (spec fazy 1, §1.3, O5):
/// uruchamia tap, odtwarza krótki ton i mierzy, czy wrócił. Publicznego API do
/// odczytu stanu uprawnienia dźwięku systemowego nie ma; to sprawdzenie nie
/// potrzebuje prywatnego TCC i działa bez względu na to, czy system przy odmowie
/// zwraca błąd, czy zera.
public enum SystemAudioCheck {
    public static func evaluate(levelsDBFS: [Double], threshold: Double = -45) -> SystemAudioCheckResult {
        let peak = levelsDBFS.max() ?? -160
        return peak > threshold ? .works(peakDBFS: peak) : .silent(peakDBFS: peak)
    }

    /// Ton 880 Hz, 300 ms, -20 dBFS. Słyszalny — interfejs uprzedza o nim.
    public static func run(timeout: Double = 1.5) async -> SystemAudioCheckResult {
        let tap = SystemTapSource()
        let levels = LevelCollector()
        do {
            _ = try tap.prepare()
            try tap.start { event in
                if case .chunk(let c) = event { levels.add(Levels.rmsDBFS(c.samples)) }
            }
        } catch {
            return .failed("\(error)")
        }
        defer { tap.stop() }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        guard let tone = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fmt.sampleRate * 0.3)) else {
            return .failed("tone buffer")
        }
        tone.frameLength = tone.frameCapacity
        for c in 0..<Int(fmt.channelCount) {
            for i in 0..<Int(tone.frameLength) {
                tone.floatChannelData![c][i] = Float(0.1 * sin(2 * .pi * 880 * Double(i) / fmt.sampleRate))
            }
        }
        do { try engine.start() } catch { return .failed("\(error)") }
        player.scheduleBuffer(tone, at: nil, options: [], completionHandler: nil)
        player.play()
        try? await Task.sleep(for: .seconds(timeout))
        engine.stop()
        return evaluate(levelsDBFS: levels.values)
    }
}

final class LevelCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.lock(); v.append(x); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return v }
}
```

- [ ] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 44/44 testów uruchomionych i zaliczonych.` Jedno ostrzeżenie `consider using asynchronous alternative function` przy `scheduleBuffer` jest świadome: wersja `async` czeka na koniec odtwarzania i przy zatrzymanym silniku zawiesiłaby sprawdzenie.

- [ ] **Krok 5: Commit.**

```bash
git add Sources/MeetNotesRecording Tests/MeetNotesRecordingTests
git commit -m "Nagrywanie: process tap, mikrofon surowy i z AEC, sprawdzenie dzwieku systemowego" -m "Tap na urzadzeniu zbiorczym przebudowywany przy zmianie wyjscia. Przetwarzanie glosu z duckingLevel min, zeby nie sciszac Teamsa. Sprawdzenie dzialania tonem testowym zamiast prywatnego TCC."
```

---

### Zadanie A9: CLI — nagrywanie, podsumowanie, dopasowanie

Status: 🔧 pełny CLI (A9 + B4 + C4 razem) skompilowany i sprawdzony dymnie przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet). Wersja pośrednia po samym A9 nie była kompilowana osobno. Plik powstał przez wycięcie z pełnego `CLI.swift` ze spike'a (🔧 skompilowany) poleceń wymagających planów B i C oraz przez nowe `readAnyAudio`, złożone z pomocnika `readInt16` z testów A4 (✅). Wykonawca kompiluje go pierwszy.

**Pliki:**
- Usuń: `Sources/meetnotes-cli/main.swift`
- Utwórz: `Sources/meetnotes-cli/CLI.swift`

**Interfejsy:**
- Pobiera: wszystko z A2–A8.
- Dostarcza: `meetnotes-cli record <katalog> [--seconds N] [--silence N] [--no-aec] [--no-system]`, `summarize <katalog>`, `fit <wzorzec> <nagranie.caf> [--max-lag-ms N]`, `check-system-audio`. Funkcje `CLI.option(_:_:)`, `CLI.positional(_:_:)`, `CLI.readAnyAudio(_:)` — używane w planach B i C.

⚠️ Uruchomione z terminala dziedziczy uprawnienia TCC aplikacji terminala, nie aplikacji MeetNotes.

- [ ] **Krok 1: Implementacja.** Usuń zaślepkę i utwórz `Sources/meetnotes-cli/CLI.swift`:

```swift
import AVFoundation
import Foundation
import MeetNotesRecording
import MeetNotesSessionFormat

/// Narzędzie deweloperskie: sondy i testy odbiorcze bez interfejsu.
/// Uwaga: uruchomione z terminala dziedziczy uprawnienia TCC terminala
/// (albo aplikacji, w której terminal działa), nie aplikacji MeetNotes.
@main
struct CLI {
    static let usage = """
    meetnotes-cli <polecenie>
      record <katalog> [--seconds N] [--silence N] [--no-aec] [--no-system]   nagrywa sesję (Ctrl-C = Stop)
      summarize <katalog>                                         odtwarza session.json z dziennika
      fit <wzorzec> <nagranie.caf> [--max-lag-ms N]              T1/T3/T4: dopasowanie nagranie ≈ a·wzorzec
      check-system-audio                                          sprawdza, czy tap słyszy dźwięk systemowy
    """

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { print(usage); exit(64) }
        let cmd = args.removeFirst()
        do {
            switch cmd {
            case "record": try await record(args)
            case "summarize": try summarize(args)
            case "fit": try fit(args)
            case "check-system-audio": print(await SystemAudioCheck.run())
            default: print(usage); exit(64)
            }
        } catch {
            FileHandle.standardError.write(Data("błąd: \(error)\n".utf8))
            exit(1)
        }
    }

    static func option(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func positional(_ args: [String], _ n: Int) throws -> String {
        let p = args.filter { !$0.hasPrefix("--") }
        guard n < p.count else { print(usage); exit(64) }
        return p[n]
    }

    static func record(_ args: [String]) async throws {
        let dir = URL(fileURLWithPath: try positional(args, 0))
        var sources: [any AudioSource] = []
        if !args.contains("--no-system") { sources.append(SystemTapSource()) }
        sources.append(RawMicrophoneSource())
        if !args.contains("--no-aec") { sources.append(VoiceProcessedMicrophoneSource()) }
        var conditions: [any EndCondition] = .standard
        if let s = option(args, "--seconds").flatMap(Double.init) { conditions.append(HardLimitCondition(seconds: s)) }
        // ⚠️ Po recenzji (R1): krótszy próg ciszy do sprzętowego T5. Pierwszy na liście wygrywa.
        if let s = option(args, "--silence").flatMap(Double.init) { conditions.insert(SilenceCondition(seconds: s), at: 0) }
        let recorder = SessionRecorder(directory: dir, sources: sources, conditions: conditions)
        let done = AsyncStream<EndReason> { cont in recorder.onEnded = { cont.yield($0); cont.finish() } }
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT)
        sigint.setEventHandler { recorder.stop(reason: .button) }
        sigint.resume()
        let ticker = Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); recorder.tick() } }
        try recorder.start()
        print("nagrywam do \(dir.path) — Ctrl-C kończy")
        for await reason in done { print("koniec: \(reason.rawValue)") }
        ticker.cancel()
        try summarize([dir.path])
    }

    static func summarize(_ args: [String]) throws {
        let s = try SessionDirectory(url: URL(fileURLWithPath: try positional(args, 0))).rebuildSummaryFile()
        print("koniec: \(s.endReason ?? "BRAK (awaria)")")
        for t in s.tracks {
            let off = t.offsetSeconds.map { String(format: "%+.3f s", $0) } ?? "—"
            let rate = t.effectiveSampleRate.map { String(format: "%.2f Hz", $0) } ?? "—"
            print("  \(t.id): \(Int(t.sampleRate)) Hz × \(t.channels), ramek \(t.frames ?? -1), przesunięcie \(off), "
                  + "efektywnie \(rate), luk \(t.gaps.count)"
                  + (t.permissionDenied.map { ", ODMOWA \($0)" } ?? "") + (t.failure.map { ", BŁĄD \($0)" } ?? ""))
        }
    }

    static func fit(_ args: [String]) throws {
        // Wzorzec w dowolnym formacie (np. aiff z `say`), nagranie — nasz CAF.
        let ref = try readAnyAudio(URL(fileURLWithPath: try positional(args, 0)))
        let rec = try CAFReader(url: URL(fileURLWithPath: try positional(args, 1)))
        let rate = 16_000.0
        let a = AudioFit.resample(AudioFit.mono(ref.samples, channels: ref.channels), from: ref.rate, to: rate)
        let b = AudioFit.resample(AudioFit.mono(rec.samples, channels: rec.channels), from: rec.sampleRate, to: rate)
        let lagMs = option(args, "--max-lag-ms").flatMap(Double.init) ?? 500
        let r = AudioFit.fit(reference: a, recorded: b, maxLagFrames: Int(lagMs / 1000 * rate))
        print(String(format: "a = %.4f  R² = %.4f  korelacja = %.4f  opóźnienie = %.1f ms",
                     r.gain, r.rSquared, r.correlation, Double(r.lagFrames) / rate * 1000))
    }

    /// Czyta dowolny plik audio jako Int16 przeplatany. W pętli: jedno `read(into:)`
    /// potrafi oddać mniej ramek niż pojemność bufora (📐 63 454 z 64 000).
    static func readAnyAudio(_ url: URL) throws -> (samples: [Int16], rate: Double, channels: Int) {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let ch = Int(f.processingFormat.channelCount)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8_192) else {
            throw AudioSourceError.coreAudio("AVAudioPCMBuffer", -1)
        }
        var out: [Int16] = []
        while f.framePosition < f.length {
            try f.read(into: buf)
            if buf.frameLength == 0 { break }
            guard let p = buf.int16ChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: p[0], count: Int(buf.frameLength) * ch))
        }
        return (out, f.processingFormat.sampleRate, ch)
    }
}
```

- [ ] **Krok 2: Zbuduj.** `swift build --product meetnotes-cli` — oczekiwane: `Build complete!`. Błąd kompilacji tu oznacza błąd w złożeniu planu, nie w kodzie ze spike'a — napraw i zanotuj w dokumencie sondy.

- [ ] **Krok 3: Test dymny bez sprzętu.** `swift run meetnotes-cli` — oczekiwane: tekst pomocy i kod wyjścia 64. `swift run meetnotes-cli summarize /nie/ma` — oczekiwane: `błąd:` i kod 1.

- [ ] **Krok 4: Pełne testy.** `scripts/test.sh` — oczekiwane: `44/44`.

- [ ] **Krok 5: Commit.**

```bash
git add Sources/meetnotes-cli
git commit -m "CLI: record, summarize, fit, check-system-audio" -m "Narzedzie do sond sprzetowych i testow odbiorczych T1-T9 bez interfejsu."
```

---

### Zadanie A10: Sondy i testy odbiorcze na sprzęcie (bramki G1, G2)

Status: nigdy niewykonane. **Wymaga użytkownika przy komputerze**: nagrywa dźwięk systemowy i mikrofon, zmienia uprawnienie w Ustawieniach systemowych. Wykonawca nie przestawia uprawnień sam — podaje instrukcję i czeka.

**Pliki:**
- Utwórz: `docs/superpowers/spikes/2026-09-24-s1-s2-sprzet.md` — wyniki: polecenia, wyjście `summarize` i `fit`, werdykty.

- [ ] **Krok 1: Przygotowanie.** `swift build -c release --product meetnotes-cli`, potem `B=$(swift build -c release --show-bin-path)/meetnotes-cli`. Release, bo `fit` przeszukuje opóźnienia siłowo (O(długość × opóźnienia)) — na 30-sekundowym pliku w trybie debug liczyłby minutami.

- [ ] **Krok 2: S1 — tap przy odmowie (G1).** Użytkownik w *Ustawienia systemowe → Prywatność i ochrona → Nagrywanie ekranu i dźwięku systemowego → Tylko nagrywanie dźwięku systemowego* **wyłącza** aplikację, z której działa terminal. Potem: `$B check-system-audio`.

| Wynik | Znaczenie | Działanie |
|---|---|---|
| `failed(... CreateProcessTap ... <status>)` | odmowa daje błąd | w `SystemTapSource.build()`, po `guard st == noErr`, przed `throw AudioSourceError.coreAudio("CreateProcessTap", st)` dodaj `if st == <zaobserwowany status> { throw AudioSourceError.permissionDenied("systemAudio") }`; zanotuj status |
| `silent(peakDBFS: -160.0)` | odmowa daje zera | bez zmian w kodzie: łapią to strażnik zer (A6) i test tonem w setupie (D) |
| `works(...)` | uprawnienie nie zostało wyłączone | powtórz krok |

Na koniec użytkownik **włącza** uprawnienie z powrotem i `$B check-system-audio` ma dać `works(peakDBFS: …)`.

- [ ] **Krok 3: S2 — dwa strumienie mikrofonu naraz (G2).** Głośniki, nie słuchawki. **S2a:** użytkownik puszcza mowę z YouTube'a i **milczy**: `$B record /tmp/mn-s2 --seconds 30`, potem `$B summarize /tmp/mn-s2`. **S2b:** to samo, ale użytkownik mówi przez ~10 s: `$B record /tmp/mn-s2b --seconds 30`; w `afplay /tmp/mn-s2b/mic_aec.caf` słychać użytkownika — AEC nie wycina jego głosu przy mowie obu stron.
  - Oczekiwane: trzy ścieżki, każda z ramkami > 0. `mic_raw` i `mic_aec` z przesunięciem rzędu 0,1–2 s względem `system`.
  - `$B fit /tmp/mn-s2/system.caf /tmp/mn-s2/mic_raw.caf` — korelacja wyraźnie > 0,12 (echo w surowym).
  - `$B fit /tmp/mn-s2/system.caf /tmp/mn-s2/mic_aec.caf` — **korelacja ≤ 0,12 (T3)**. Liczone na S2a: przy mowie użytkownika niska korelacja nic by nie dowodziła (ChatGPT 🟡).
  - Uchem: głośność YouTube'a nie spada w chwili startu nagrania (ducking).
  - **STOP i decyzja użytkownika**, jeśli `mic_aec` albo `mic_raw` ma 0 ramek, albo `track.failed`, albo obie korelacje ≤ 0,12 (surowy też przetworzony). Spec rdzenia §2 zakłada oba strumienia — zmiana wymaga decyzji, który porzucić.

- [ ] **Krok 4: T1 — odsłuch jest tapem.** `say -v Zosia --data-format=LEF32@48000 -o /tmp/mn-ref.caf "Sprawdzam nagrywanie, raz, dwa, trzy, cztery, pięć"`. `$B record /tmp/mn-t1 --seconds 12 --no-aec & sleep 1; afplay /tmp/mn-ref.caf; wait`. Potem `$B fit /tmp/mn-ref.caf /tmp/mn-t1/system.caf --max-lag-ms 2000` — oczekiwane: **R² ≥ 0,999** i opóźnienie ~1000 ms. Wzorzec w 48 kHz, bo domyślne 22 050 Hz z `say` dokłada przepróbkowanie po drodze i przy R² < 0,999 nie wiadomo, czy winny jest tap, czy łańcuch (Hermes 4.7). `fit` szuka tylko dodatniego opóźnienia — wzorzec zawsze jako pierwszy argument. Jeśli opóźnienie wychodzi na granicy 2000 ms, zwiększ `--max-lag-ms` — odtwarzanie ruszyło później.

- [ ] **Krok 5: T4 — mikrofon nie trafia do odsłuchu.** Słuchawki, nic nie gra, użytkownik mówi ~10 s. `$B record /tmp/mn-t4 --seconds 15 --no-aec`, potem `$B fit /tmp/mn-t4/mic_raw.caf /tmp/mn-t4/system.caf` — oczekiwane: **|a| < 0,01**.

- [ ] **Krok 6: T6 — przepięcie urządzenia.** `$B record /tmp/mn-t6 --seconds 60`, w trakcie gra muzyka; w 20. sekundzie użytkownik podłącza słuchawki Bluetooth, w 40. je odłącza. `$B summarize /tmp/mn-t6` — oczekiwane: `system` ma ≥ 2 zmiany urządzenia i luki; brak `track.failed`. Odsłuch `afplay /tmp/mn-t6/system.caf` — dźwięk ciągły poza lukami, **bez przyspieszenia ani spowolnienia** (inna częstotliwość słuchawek przepróbkowana do formatu ścieżki).

- [ ] **Krok 7: T8 — długa sesja (opcjonalnie w trakcie prawdziwego spotkania).** `$B record ~/mn-t8` przez ≥ 85 min, Ctrl-C. `summarize` — oczekiwane: każda ścieżka ma `efektywnie` w granicach ±0,1% nominalnej i kotwice co ~10 s (`grep -c track.clock ~/mn-t8/journal.jsonl` ≈ liczba minut × 6 × liczba ścieżek).

- [ ] **Krok 8: T7 — `kill -9`.** `$B record /tmp/mn-t7 &`, po 10 s `kill -9 $!`. `$B summarize /tmp/mn-t7` — oczekiwane: `koniec: BRAK (awaria)`, ścieżki z ramkami > 0; `afplay /tmp/mn-t7/system.caf` gra.

- [ ] **Krok 9: T5 — koniec z ciszy na sprzęcie.** Nic nie gra, użytkownik milczy. `$B record /tmp/mn-t5 --silence 60 --seconds 120`, potem `$B summarize /tmp/mn-t5` — oczekiwane: `koniec: silence` (nie `hardLimit`), sesja krótsza niż 90 s. Szum tła pokoju powyżej −50 dBFS da `hardLimit` — wtedy zanotuj poziom (`$B fit` nie mierzy poziomu; wystarczy obserwacja) i powtórz w cichszym miejscu.

- [ ] **Krok 10: Zapisz wyniki i commit.** Wyniki wszystkich kroków do `docs/superpowers/spikes/2026-09-24-s1-s2-sprzet.md`. Jeśli S1 wymagał zmiany w `SystemTapSource`, dołącz ją.

```bash
git add docs/superpowers/spikes Sources/MeetNotesRecording
git commit -m "Sondy S1, S2 i testy odbiorcze T1-T9 na sprzecie"
```
