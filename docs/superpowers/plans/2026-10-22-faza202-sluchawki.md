# Faza 2.0.2: Nagrywanie na słuchawkach Bluetooth — plan wdrożenia

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tor `system` nagrywa słuchawki Bluetooth (wejście i wyjście na tym samym urządzeniu) z poprawną prędkością, a gdy tor jest zły albo martwy, aplikacja to mówi; w pigułce da się opcjonalnie zmienić wejście.

**Architecture:** (1) Częstotliwość wejściowa `HALCapture` pochodzi z rzeczywistego zegara urządzenia zbiorczego, nie z formatu tapa, a istniejący konwerter przelicza do formatu toru. (2) Zmiana częstotliwości i formatu urządzenia przebudowuje tap (jest już `rebuild()`). (3) Ostrzeżenia po nagraniu i podpowiedź w pigułce. (4) Opcja „zmień wejście" jako menu w wierszu mikrofonu, bez nowych ekranów.

**Tech Stack:** Swift 6.4 na CLT, Core Audio (`CATapDescription`, urządzenie zbiorcze, `AudioObjectAddPropertyListenerBlock`), `swift-testing`, SwiftUI (bez `@State`).

**Spec:** `docs/superpowers/specs/2026-10-22-faza202-sluchawki-design.md` (decyzje D1–D3 w sekcji 5). Dowody: `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md`.

## Global Constraints

- Testy wyłącznie `scripts/test.sh`; mutacja każdej bramki (wprowadź → test pada → `git checkout <plik>`, plik wcześniej zacommitowany). Linia bazowa: **592/592** na `master` po PR #20.
- Nowe pola w zapisywanych typach tylko opcjonalne. Dziennik sesji: bez nowych typów zdarzeń (stare czytniki mogą je odrzucić); używamy `track.opened`, `device.changed`, `track.clock`, `track.failed`.
- SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`; stan lokalny w `ObservableObject` + `@StateObject`. Interfejs po angielsku, dokumenty po polsku.
- Nie zmieniaj Ustawień systemowych, TCC ani pęku kluczy; **każdy pomiar na sprzęcie wykonuje użytkownik** (bramki STOP M1, M2, M3). Wykonawca nie zgaduje wyniku pomiaru.
- Domyślne zachowanie bez zmian: nagrywamy domyślne urządzenia systemu; aplikacja **nie** przełącza mikrofonu sama (D2). Wybór wejścia w pigułce dotyczy tylko bieżącego nagrania i nie jest zapisywany.
- Nie wchodź shellem do `.devdata/sessions/…` ani nie rób `cd` do `Sources/…` (hooki tworzą `.claude-flow/`, `agentdb.rvf`); ścieżki bezwzględne.
- Commity kończą się `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; nigdy `git add -A`; PR scala wyłącznie użytkownik komendą „scal" (`gh pr merge --merge`).
- Po każdej zmianie BACKLOG/ROADMAP/postępu: artefakt „Mapa faz Yascribe" (https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz).

## Review Focus

Wejścia i warunki, których testy zadań nie pokrywają bezpośrednio, a recenzent ma sprawdzić świadomie:

1. **Regresja na urządzeniach wbudowanych** (48 000 Hz = 48 000 Hz): zmiana rzeczywistej częstotliwości nie może dotykać toru, który działa (sesja `82c4`). Test: Task 3 (`captureFormatKeepsTheTapFormatWhenRatesAgree`).
2. **Pętla przebudowy**: słuchawki przełączają A2DP↔HFP, a nasłuch zmian częstotliwości odpala `rebuild()` w kółko (FluidVoice #752 opisuje taką pętlę przy prewarm). Test: Task 4 (`RebuildGate`).
3. **Wybrane wejście znika w trakcie nagrania** (słuchawki wyłączone): wraca domyślne, `device.changed` w dzienniku, pigułka pokazuje faktyczną nazwę. Test: Task 7.
4. **Stare sesje bez `effectiveSampleRate`** (jeden lub zero kotwic) nie dostają fałszywego ostrzeżenia o prędkości. Test: Task 1.
5. **Krótkie nagranie**: poniżej 20 s kotwic nie ma wniosku o prędkości (jedna próba 36 s z `08f6` miała 0 klatek, bez kotwic). Test: Task 1.

---

### Task 1: `Track.rateMismatch` (czysta funkcja nad podsumowaniem sesji)

**Files:**
- Modify: `Sources/MeetNotesSessionFormat/SessionSummary.swift` (rozszerzenie `SessionSummary.Track`)
- Test: `Tests/MeetNotesSessionFormatTests/SessionSummaryTests.swift`

**Interfaces:**
- Produces: `public extension SessionSummary.Track { var rateMismatch: Double? { get } }` — `effectiveSampleRate / sampleRate`, gdy tor ma `effectiveSampleRate`, co najmniej dwie kotwice `clock`, rzeczywisty czas między pierwszą a ostatnią kotwicą `Double(last.frameIndex − first.frameIndex) / effectiveSampleRate >= 20` s i `abs(ratio − 1) > 0.05`; inaczej `nil`.

- [ ] **Step 1: Write the failing tests** (`SessionSummaryTests.swift`):
  - `rateMismatchFlagsAThreeTimesSlowTrack`: tor `sampleRate: 48_000`, `effectiveSampleRate: 16_500`, kotwice `clock` o `frameIndex` 0 i 330 000 (to 20 s przy 16 500 Hz); oczekuj wartości `16_500.0/48_000` (≈ 0,344, tolerancja 1e-9).
  - `rateMismatchFlagsEightPercentFastTrack`: `44_100` kontra `48_000` (stosunek 0,91875) → nie `nil`.
  - `rateMismatchIgnoresHealthyTracks`: `47_998` kontra `48_000` → `nil`; `16_000` kontra `16_000` → `nil`.
  - `rateMismatchNeedsTwentySecondsOfAnchors`: ten sam błędny stosunek, ale kotwice obejmują 10 s (`frameIndex` 0 i 165 000 przy 16 500 Hz) → `nil`; tor bez `effectiveSampleRate` → `nil`.
- [ ] **Step 2: Run** `scripts/test.sh` — Expected: FAIL (brak `rateMismatch`).
- [ ] **Step 3: Implement** `rateMismatch` w `SessionSummary.swift`.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 596/596.
- [ ] **Step 5: Mutation:** zmień próg `0.05` na `0.5` → `rateMismatchFlagsEightPercentFastTrack` pada; zmień `>= 20` na `>= 2` → `rateMismatchNeedsTwentySecondsOfAnchors` pada; `git checkout` pliku po każdej.
- [ ] **Step 6: Commit** (jawne ścieżki).

### Task 2: Pomiar zegara tapa: `TapRates` i `meetnotes-cli tap-rate` (bramka M1)

**Files:**
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`nominalSampleRate(of:)`), `Sources/MeetNotesRecording/SystemTapSource.swift` (`rates()`), `Sources/meetnotes-cli/CLI.swift` (polecenie `tap-rate`)

**Interfaces:**
- Produces: `CoreAudioDevices.nominalSampleRate(of device: AudioObjectID) throws -> Double` (`kAudioDevicePropertyNominalSampleRate`, zakres globalny);
  `public struct TapRates: Equatable, Sendable { public var tapFormat: Double; public var aggregateNominal: Double; public var outputNominal: Double }`;
  `SystemTapSource.rates() -> TapRates?` (po `prepare()`, `nil` przed nim).
- CLI: `meetnotes-cli tap-rate [--seconds N]` (domyślnie 10) wypisuje `tapFormat`, `aggregateNominal`, `outputNominal` oraz **zmierzoną** częstotliwość dostarczania (suma klatek porcji / czas zegara hosta) w jednej linii.

- [ ] **Step 1:** Zaimplementuj `nominalSampleRate`, `TapRates`, `rates()`, polecenie CLI (bez testu jednostkowego: czysty odczyt sprzętu; uzasadnienie w komunikacie commita).
- [ ] **Step 2: Run** `scripts/test.sh` — Expected: 596/596; `swift build` bez nowych ostrzeżeń kompilatora.
- [ ] **Step 3: Commit.**
- [ ] **Step 4: STOP M1 (użytkownik).** Poproś użytkownika o uruchomienie `meetnotes-cli tap-rate --seconds 15` w trzech konfiguracjach, z dźwiękiem puszczonym przez cały czas: **A** (wejście i wyjście: słuchawki; najlepiej z aktywnym połączeniem, np. Teams, żeby słuchawki były w trybie rozmowy), **C** (wejście: MacBook, wyjście: słuchawki), **B** (wejście: słuchawki, wyjście: głośniki MacBooka); wynik wkleja do rozmowy. Wykonawca zapisuje liczby w `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md` (sekcja „M1") i **wybiera źródło prawdy dla Task 3**: tę z trzech wartości, która zgadza się ze zmierzoną w C i A. Brak zgodnej wartości = STOP, wynik wraca do użytkownika (nie zgadywać).

### Task 3: Rzeczywista częstotliwość wejścia tapa (naprawa C i `ec0b`)

**Files:**
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift`, `Sources/MeetNotesRecording/SystemTapSource.swift` (`build()`, `startCapture()`; `HALCapture` bez zmian)
- Test: `Tests/MeetNotesRecordingTests/CaptureFormatTests.swift` (nowy)

**Interfaces:**
- Consumes: Task 2 (`nominalSampleRate`) i wybór źródła z M1.
- Produces: `CoreAudioDevices.captureFormat(tap: AVAudioFormat, deviceRate: Double) -> AVAudioFormat` — gdy `deviceRate > 0` i różni się od `tap.sampleRate` o więcej niż 0,5 Hz, zwraca format z tą samą liczbą kanałów, Float32 jak tap, ale `sampleRate: deviceRate`; inaczej zwraca `tap` bez zmian.
  `SystemTapSource` podaje `HALCapture` ten format jako `inputFormat`, a **format toru zostaje deklarowany jak dziś** (`prepare()`), więc konwerter przelicza do niego.

- [ ] **Step 1: Write the failing tests:** `captureFormatKeepsTheTapFormatWhenRatesAgree` (48 000 i 48 000 → ten sam obiekt formatu, `===`), `captureFormatTakesTheDeviceRateWhenTheyDiffer` (tap 48 000, urządzenie 44 100 → `sampleRate == 44_100`, kanały bez zmian), `captureFormatIgnoresAnUnreadableDeviceRate` (urządzenie 0 → tap bez zmian).
- [ ] **Step 2: Run** — Expected: FAIL (brak funkcji).
- [ ] **Step 3: Implement** funkcję i użyj jej w `SystemTapSource.startCapture()` oraz po `rebuild()`; źródło `deviceRate` wg wyniku M1 (`nominalSampleRate(of: aggregate)` albo wyjścia).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 599/599.
- [ ] **Step 5: Mutation:** próg 0,5 Hz zmień na 50 000 → `captureFormatTakesTheDeviceRateWhenTheyDiffer` pada; zwracaj zawsze `tap` → ten sam test pada; `git checkout`.
- [ ] **Step 6: Commit.**
- [ ] **Step 7: STOP M2 (użytkownik):** nagranie C (wyjście: słuchawki, wejście: MacBook, 60 s z mową). Kryterium: w dzienniku sesji zegar do pliku 1,0 (`effectiveSampleRate` ≈ deklarowanej ±0,1 %), `Track.rateMismatch == nil`. Wykonawca czyta dziennik ścieżką bezwzględną i dopisuje wynik do raportu S0. Nie spełnione = STOP.

### Task 4: Nasłuch zmian częstotliwości i bramka przebudowy

**Files:**
- Modify: `Sources/MeetNotesRecording/DeviceWatcher.swift` (konstruktor `init(object:selector:)`, istniejący zostaje), `Sources/MeetNotesRecording/SystemTapSource.swift`
- Create: `Sources/MeetNotesRecording/RebuildGate.swift`
- Test: `Tests/MeetNotesRecordingTests/RebuildGateTests.swift`

**Interfaces:**
- Produces: `struct RebuildGate { init(minInterval: Double = 1.0, maxPerMinute: Int = 6); mutating func allow(now: Double) -> Bool }` — odmawia, gdy od poprzedniej dozwolonej przebudowy minęło mniej niż `minInterval` albo w ostatnich 60 s było już `maxPerMinute` przebudów.
  `DeviceWatcher(object: AudioObjectID, selector: AudioObjectPropertySelector)`: nasłuch na konkretnym obiekcie; `stop()` bez zmian.
  `SystemTapSource` nasłuchuje `kAudioDevicePropertyNominalSampleRate` urządzenia zbiorczego i `kAudioStreamPropertyVirtualFormat` (strumień wyjścia) i po przejściu przez `RebuildGate` woła `rebuild()`; odmowę bramki zapisuje `AudioSourceEvent.failed("rebuildThrottled")` raz na nagranie.

- [ ] **Step 1: Write the failing tests:** `gateAllowsTheFirstRebuild`; `gateRefusesASecondRebuildWithinTheMinimumInterval` (0 s dozwolone, 0,5 s odmowa, 1,2 s dozwolone); `gateCapsRebuildsPerMinute` (sześć dozwolonych w odstępach 2 s, siódma w 12,5 s odmowa, po 60 s od pierwszej znów dozwolona).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `RebuildGate`, `DeviceWatcher(object:selector:)`, podłączenie w `SystemTapSource` (nasłuchy zakładane w `start`, zdejmowane w `stop` i w `teardown`).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 602/602.
- [ ] **Step 5: Mutation:** `minInterval` na 0 → drugi test pada; `maxPerMinute` na 100 → trzeci pada; `git checkout`.
- [ ] **Step 6: Commit.** Nasłuch sprzętowy bez testu jednostkowego (jak `DeviceWatcher` dziś); weryfikuje go M3.

### Task 5: Ostrzeżenie o złej prędkości w widoku spotkania

**Files:**
- Modify: `Sources/MeetNotesNotes/TrackProblem.swift` (`classify`)
- Test: `Tests/MeetNotesNotesTests/TrackProblemTests.swift`

**Interfaces:**
- Consumes: Task 1 (`rateMismatch`).
- Produces: w `TrackProblem.of(…)` tor z `rateMismatch != nil` (i bez `failure`/`permissionDenied`) daje ostrzeżenie (`isWarning: true`) `line: "System audio was recorded at the wrong speed."` (dla mikrofonu „Microphone was recorded at the wrong speed.") i `detail` w stylu pozostałych: co, ile (`ratio` jako procent), co zrobić („Headphones in call mode can do this. Use the Mac's microphone or speakers, then record again.") — treść dla toru `system`.

- [ ] **Step 1: Write the failing tests:** `wrongSpeedTrackIsAWarning` (tor `system`, 48 000/16 500 z kotwicami ≥ 20 s → `isWarning`, `line` jak wyżej, `detail` zawiera „34%"), `healthyRateGivesNoProblem`, `wrongSpeedDoesNotMaskAFailure` (tor z `failure: "stalled30s"` zachowuje dotychczasowy komunikat).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** gałąź w `classify` po sprawdzeniu `permissionDenied`/`failure`.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 605/605.
- [ ] **Step 5: Mutation:** usuń warunek `rateMismatch != nil` → `healthyRateGivesNoProblem` pada; `git checkout`.
- [ ] **Step 6: Commit.**

### Task 6: Podpowiedź w pigułce, gdy mikrofon i wyjście to to samo urządzenie

**Files:**
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`defaultInputUID()`, `defaultOutputUID()`, `sameDevice(_:_:)`), `Sources/MeetNotesApp/RecordingController.swift` (`stallHint`, wiersz systemowy pigułki), `Sources/MeetNotesApp/Snapshots.swift` (migawka)
- Test: `Tests/MeetNotesRecordingTests/DeviceIdentityTests.swift`

**Interfaces:**
- Produces: `CoreAudioDevices.sameDevice(_ a: String, _ b: String) -> Bool` — porównuje UID po odcięciu końcówki `:input` / `:output` (słuchawki Bluetooth raportują `00-02-3C-8D-E0-50:input` i `…:output`); puste UID nigdy nie są równe.
  `RecordingController.stallHint: String?` — gdy `systemStalled` i `sameDevice(micUID, outputUID)`: „Headset in call mode may block system audio. Switch the microphone or the output." Informacja, nie błąd (cisza w poczekalni dalej zwykłym stanem).

- [ ] **Step 1: Write the failing tests:** `sameDeviceIgnoresTheInputOutputSuffix` (`00-02-3C-8D-E0-50:input` i `…:output` → true), `differentDevicesAreNotTheSame` (`BuiltInMicrophoneDevice` kontra `BuiltInSpeakerDevice` → false), `emptyUIDsAreNeverTheSame` ("" i "" → false).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** funkcje i `stallHint`; wiersz pigułki pokazuje podpowiedź pod wierszem systemowym tylko przy `stallHint != nil`; migawka `pill-system-stalled-headset` (światło i ciemny; sprawdź obie).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 608/608; `scripts/snapshot.sh`.
- [ ] **Step 5: Mutation:** `sameDevice` zawsze `false` → pierwszy test pada; `git checkout`.
- [ ] **Step 6: Commit.**

### Task 7: Opcjonalna zmiana wejścia w pigułce

**Files:**
- Modify: `Sources/MeetNotesRecording/MicrophoneSources.swift` (`RawMicrophoneSource.select(deviceUID:)`), `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`inputDevices()`), `Sources/MeetNotesApp/RecordingController.swift` (menu w wierszu mikrofonu, `selectInput`), `Sources/MeetNotesApp/Snapshots.swift`
- Create: `Sources/MeetNotesRecording/InputChoice.swift`
- Test: `Tests/MeetNotesRecordingTests/InputChoiceTests.swift`

**Interfaces:**
- Produces: `public struct InputDevice: Equatable, Sendable { public var uid: String; public var name: String }`;
  `CoreAudioDevices.inputDevices() -> [InputDevice]` (urządzenia z strumieniem wejściowym, bez urządzeń zbiorczych „meetnotes-tap");
  `enum InputChoice { static func resolve(preferred: String?, available: [InputDevice], defaultUID: String?) -> String? }` — zwraca UID do użycia: `preferred`, jeśli jest na liście; w przeciwnym razie `defaultUID` (nil = użyj domyślnego systemu);
  `RawMicrophoneSource.select(deviceUID: String?)` — zapamiętuje preferencję i woła istniejące `reopen()`, które używa `InputChoice.resolve`; brak preferencji = zachowanie dzisiejsze (domyślne wejście).
  Interfejs: w wierszu „Microphone: <nazwa>" pigułki mała strzałka `⌄` otwiera `Menu` z pozycjami „System default" (zaznaczona domyślnie) i listą urządzeń; wybór wywołuje `RecordingController.selectInput(uid:)`. Bez nowych ekranów, bez zapisu preferencji.

- [ ] **Step 1: Write the failing tests:** `choiceKeepsThePreferredDeviceWhenPresent`, `choiceFallsBackToTheDefaultWhenThePreferredDeviceVanishes` (słuchawki wyłączone: `preferred` spoza listy → `defaultUID`), `choiceWithoutPreferenceUsesTheSystemDefault` (nil → `defaultUID`), `choiceIsNilWhenThereIsNothingToChoose` (brak preferencji i brak domyślnego → nil).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `InputChoice`, `inputDevices()`, `select`, menu w pigułce, migawka `pill-input-menu` (otwarte menu rysujemy jako listę w miejscu, jak popover w migawkach 2.0.1; światło i ciemny).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 612/612; `scripts/snapshot.sh`.
- [ ] **Step 5: Mutation:** `resolve` zawsze zwraca `preferred` → test znikającego urządzenia pada; `git checkout`.
- [ ] **Step 6: Commit.**

### Task 8: Spike S1: ScreenCaptureKit jako pomiar (jednorazowy, bramka M3 — decyzja użytkownika)

**Files:** osobna gałąź `spike/f202-s1`, **nie scalana do `master`**; wynik trafia do `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md` (sekcja „S1") na gałęzi fazy.

- [ ] **Step 1:** Tylko po wyraźnej zgodzie użytkownika na Screen Recording dla tego jednego narzędzia. Jednorazowe polecenie CLI `sck-rate [--seconds N]`: `SCStream` z `capturesAudio = true`, `sampleRate = 48_000`, `channelCount = 2`, filtr na wyświetlacz, `excludesCurrentProcessAudio = true`; wypisuje liczbę klatek audio i zmierzoną częstotliwość. Bez testów (spike).
- [ ] **Step 2: STOP M3 (użytkownik):** uruchomienie w konfiguracjach A, B, C (jak M1). Wynik: czy SCK daje klatki i poprawną prędkość w A.
- [ ] **Step 3:** Wykonawca dopisuje wyniki do raportu i **nie** proponuje przejścia na SCK sam: decyzja wraca do użytkownika z danymi z M1, M2, M3 i z odbioru (Task 9).

### Task 9: Odbiór na żywo, dokumenty, artefakt

- [ ] **Step 1: STOP M4 (użytkownik):** nowy build (`scripts/run.sh`), nagranie A (wejście i wyjście: słuchawki, najlepiej na prawdziwym spotkaniu Teams), 3–5 min. Kryteria: tor `system` ma klatki; `Track.rateMismatch == nil`; transkrypt „Them" zawiera rozmówców; pigułka nie pokazuje fałszywego alarmu; menu wejścia w pigułce działa (zmiana na wbudowany mikrofon i powrót do „System default"). Wykonawca czyta dziennik i podsumowanie ścieżkami bezwzględnymi.
- [ ] **Step 2:** Zaktualizuj `docs/superpowers/BACKLOG.md` (pozycja o słuchawkach: zrobione/niezrobione z dowodami), `docs/superpowers/ROADMAP.md` (faza 2.0.2), `CLAUDE.md` (akapit fazy 2.0.2, liczba testów), raport S0 (M1, M2, M4), oraz artefakt „Mapa faz".
- [ ] **Step 3:** Przegląd całej gałęzi świeżym recenzentem (Review Focus powyżej verbatim), poprawki jednym przebiegiem, PR do `master`; scala użytkownik.
