# Faza 2.0.2: Nagrywanie na słuchawkach Bluetooth — plan wdrożenia

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tor `system` nagrywa słuchawki Bluetooth z poprawną prędkością, a gdy tor jest zły albo martwy, aplikacja to mówi; w pigułce da się opcjonalnie zmienić wejście.

**Architecture:** (1) Częstotliwość wejściowa `HALCapture` pochodzi z rzeczywistego zegara urządzenia, nie z formatu tapa; istniejący konwerter przelicza do formatu toru. (2) Zmiana częstotliwości urządzenia przebudowuje tap (jest `rebuild()`), z bramką przeciw pętli. (3) Eksperyment z układem urządzenia zbiorczego (bez wyjścia jako podurządzenia). (4) Ostrzeżenia po nagraniu i podpowiedź w pigułce. (5) Opcja „zmień wejście" jako menu w wierszu mikrofonu, bez nowych ekranów.

**Tech Stack:** Swift 6.4 na CLT, Core Audio, `swift-testing`, SwiftUI (bez `@State`).

**Spec:** `docs/superpowers/specs/2026-10-22-faza202-sluchawki-design.md` (decyzje D1–D3 w sekcji 5). Dowody: `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md`.

## Poza zakresem (czego ten plan NIE dostarcza)

Przeczytaj przed startem. Użytkownik nie powinien oczekiwać:

- **Gwarantowanej naprawy przypadku A** (wejście i wyjście na tych samych słuchawkach, sesja `08f6`: 0 klatek). Przyczyna jest **niewyjaśniona** (spec S0b). Plan daje: pomiar (Task 2), eksperyment z układem urządzenia zbiorczego (Task 5), komunikaty (Task 6, 7) i pomiar ScreenCaptureKit (Task 10). Odbiór M4 w konfiguracji A **może wypaść negatywnie**; wtedy wykonawca zatrzymuje się i oddaje decyzję użytkownikowi (Task 11), nie ogłasza sukcesu.
- Naprawy starych sesji (np. `ec0b`): użytkownik ich nie potrzebuje.
- Wyboru wyjścia (tor `system` podąża za domyślnym wyjściem systemu), zapisu preferencji wejścia, nowych ekranów w Settings, pytań przed startem.
- Automatycznej zmiany mikrofonu (D2).
- Przejścia na ScreenCaptureKit: Task 10 to wyłącznie pomiar na osobnej gałęzi.
- Ostrzeżenia przy nagraniach krótszych niż 20 s i przy torze bez kotwic zegara (poza istniejącą informacją o torze bez klatek).
- Wykrywania urządzenia, którego **używa spotkanie** (Teams): D2 rozumiemy jako „domyślne urządzenia systemu, a gdy to słuchawki, to słuchawki". BACKLOG notuje przypadek, gdy Teams używał MacBooka, a domyślne były słuchawki; wtedy pomaga menu wejścia z Task 8–9 (ręcznie). **Założenie do potwierdzenia przez użytkownika: bramka STOP przed Task 7** (Task 7–9 nie startują bez potwierdzenia; Task 1–6 i 10 nie zależą od tej odpowiedzi).

## Mapowanie spec ↔ plan

| Spec §3 | Plan |
|---|---|
| T2 częstotliwość z urządzenia | Task 3 (pomiar: Task 2) |
| T3 nasłuch zmian | Task 4 |
| T1 urządzenie zbiorcze bez wyjścia (eksperyment) | Task 5 |
| T5 ostrzeżenie po nagraniu | Task 6 |
| T4 podpowiedź w pigułce | Task 7 |
| D2/D3 wejście w pigułce | Task 8, 9 |
| S1 ScreenCaptureKit | Task 10 |
| odbiór | Task 11 |

Słownictwo: „tor `system`" = kanał „Them" = „System audio" w interfejsie (jeden byt). Bramki pomiarowe użytkownika nazywamy **M1–M4** (nie „Task").

## Global Constraints

- Testy wyłącznie `scripts/test.sh`. **Kolejność w każdym zadaniu: implementacja → commit → mutacja (wprowadź → test pada → `git checkout <plik>`)**, bo `git checkout` przywraca zacommitowaną wersję. Linia bazowa: **592/592** na `master` po PR #20.
- Nowe pola w zapisywanych typach tylko opcjonalne. Dziennik sesji: bez nowych typów zdarzeń; używamy `track.opened`, `device.changed`, `track.clock`, `track.failed`. Nie emituj `AudioSourceEvent.failed` dla zjawisk, które nie są awarią toru (wpisuje tor do `failedTracks` i wyłącza nadzór stall, `SessionRecorder` ok. l. 171–228).
- SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`; stan lokalny w `ObservableObject` + `@StateObject`. Interfejs po angielsku, dokumenty po polsku.
- Nie zmieniaj Ustawień systemowych, TCC ani pęku kluczy; **każdy pomiar na sprzęcie wykonuje użytkownik** (bramki STOP M1, M2, M2b, M3, M4). Wykonawca nie zgaduje wyniku.
- Domyślne zachowanie bez zmian: nagrywamy domyślne urządzenia systemu. Wybór wejścia w pigułce dotyczy tylko bieżącego nagrania.
- Nie wchodź shellem do `.devdata/sessions/…` ani nie rób `cd` do `Sources/…` (hooki tworzą `.claude-flow/`, `agentdb.rvf`); ścieżki bezwzględne.
- Commity kończą się `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; nigdy `git add -A`; PR scala wyłącznie użytkownik komendą „scal" (`gh pr merge --merge`).
- Po każdej zmianie BACKLOG/ROADMAP/postępu: artefakt „Mapa faz Yascribe" (https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz).
- Konfiguracje pomiarowe: **A** wejście i wyjście: słuchawki; **B** wejście: słuchawki, wyjście: głośniki MacBooka; **C** wejście: MacBook, wyjście: słuchawki; **W** wejście i wyjście: wbudowane (kontrola regresji).

## Review Focus

1. **Regresja na urządzeniach wbudowanych** (48 000 = 48 000 Hz): zmiana nie dotyka toru, który działa (sesja `82c4`). Test: Task 3 (`captureFormatKeepsTheTapFormatWhenRatesAgree`); pomiar W w M2 i M2b.
2. **Pętla przebudowy** (A2DP↔HFP): Task 4 (`RebuildGate`), nasłuchy zakładane na nowo po każdej przebudowie, końcowy stan zawsze zastosowany (odroczone ponowienie).
3. **Wybrane wejście znika w trakcie nagrania**: wraca domyślne, `device.changed` w dzienniku, pigułka pokazuje faktyczną nazwę. Test: Task 8.
4. **Stare sesje bez `effectiveSampleRate`** nie dostają fałszywego ostrzeżenia. Test: Task 1.
5. **Krótkie nagranie** (< 20 s kotwic): brak wniosku o prędkości. Test: Task 1.

---

### Task 1: Czyste funkcje: `Track.rateMismatch` i `DeviceUID.same`

**Files:**
- Modify: `Sources/MeetNotesSessionFormat/SessionSummary.swift` (rozszerzenie `SessionSummary.Track`)
- Create: `Sources/MeetNotesSessionFormat/DeviceUID.swift`
- Test: `Tests/MeetNotesSessionFormatTests/SessionSummaryTests.swift`, `Tests/MeetNotesSessionFormatTests/DeviceUIDTests.swift`

**Interfaces:**
- Produces: `public extension SessionSummary.Track { var rateMismatch: Double? { get } }` — `effectiveSampleRate / sampleRate`, gdy tor ma `effectiveSampleRate`, co najmniej dwie kotwice `clock`, `Double(last.frameIndex − first.frameIndex) / effectiveSampleRate >= 20` (rzeczywisty czas w sekundach) i `abs(ratio − 1) > 0.05`; inaczej `nil`.
  `public enum DeviceUID { public static func same(_ a: String, _ b: String) -> Bool }` — porównuje UID po odcięciu końcówki `:input` / `:output` (słuchawki Bluetooth: `00-02-3C-8D-E0-50:input` i `…:output`); puste UID nigdy nie są równe. Wspólny dla `MeetNotesRecording` i `MeetNotesNotes` (oba importują `MeetNotesSessionFormat`).

- [ ] **Step 1: Write the failing tests:**
  - `rateMismatchFlagsAThreeTimesSlowTrack`: `sampleRate: 48_000`, `effectiveSampleRate: 16_500`, kotwice `frameIndex` 0 i 330 000; wynik `16_500.0/48_000` (tolerancja 1e-9).
  - `rateMismatchFlagsEightPercentOffTrack`: `44_100` kontra `48_000` (0,91875) → nie `nil`.
  - `rateMismatchIgnoresHealthyTracks`: `47_998`/`48_000` → `nil`; `16_000`/`16_000` → `nil`.
  - `rateMismatchNeedsTwentySecondsOfAnchors`: błędny stosunek, kotwice `frameIndex` 0 i 165 000 przy 16 500 Hz (10 s) → `nil`; tor bez `effectiveSampleRate` → `nil`.
  - `sameDeviceIgnoresTheInputOutputSuffix` (`00-02-3C-8D-E0-50:input` i `…:output` → true), `differentDevicesAreNotTheSame` (`BuiltInMicrophoneDevice` kontra `BuiltInSpeakerDevice` → false), `emptyUIDsAreNeverTheSame` ("" i "" → false).
- [ ] **Step 2: Run** `scripts/test.sh` — Expected: FAIL (brak symboli).
- [ ] **Step 3: Implement** obie funkcje.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 599/599.
- [ ] **Step 5: Commit** (jawne ścieżki).
- [ ] **Step 6: Mutation** (po commicie): próg `0.05` → `0.5` (pada `…EightPercentOffTrack`); `>= 20` → `>= 2` (pada `…NeedsTwentySeconds…`); `same` zawsze `false` (pada `sameDeviceIgnores…`); po każdej `git checkout` pliku.

### Task 2: Pomiar zegara tapa: `TapRates` i `meetnotes-cli tap-rate` (bramka M1)

**Files:**
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`nominalSampleRate(of:)`), `Sources/MeetNotesRecording/SystemTapSource.swift` (`rates()`), `Sources/meetnotes-cli/CLI.swift` (polecenie `tap-rate`)

**Interfaces:**
- Produces: `CoreAudioDevices.nominalSampleRate(of device: AudioObjectID) throws -> Double` (`kAudioDevicePropertyNominalSampleRate`, zakres globalny);
  `public struct TapRates: Equatable, Sendable { public var tapFormat: Double; public var aggregateNominal: Double; public var outputNominal: Double }`;
  `SystemTapSource.rates() -> TapRates?` (po `prepare()`, `nil` przed nim).
- CLI: `meetnotes-cli tap-rate [--seconds N] [--with-mic] [--tap-only]` (domyślnie 10 s) wypisuje `tapFormat`, `aggregateNominal`, `outputNominal`, **zmierzoną** częstotliwość dostarczania (suma klatek porcji / czas zegara hosta) i poziom RMS dostarczonych próbek (dBFS; sprawdza, że to nie cisza) w jednej linii. `--with-mic` otwiera `RawMicrophoneSource` **po** starcie tapa, jak aplikacja, i wypisuje te same wartości także po otwarciu mikrofonu (profil słuchawek przełącza się dopiero wtedy; hipoteza S0b). `--tap-only` dochodzi w Task 5.

- [ ] **Step 1:** Zaimplementuj (bez testu jednostkowego: odczyt sprzętu; uzasadnienie w komunikacie commita).
- [ ] **Step 2: Run** `scripts/test.sh` — Expected: 599/599; `swift build` bez nowych ostrzeżeń kompilatora.
- [ ] **Step 3: Commit.**
- [ ] **Step 4: STOP M1 (użytkownik).** Użytkownik uruchamia `meetnotes-cli tap-rate --seconds 15 --with-mic` z dźwiękiem puszczonym przez cały czas w konfiguracjach **C**, **B**, **W** i **A** (A najlepiej z aktywnym połączeniem, np. Teams, żeby słuchawki były w trybie rozmowy); wkleja wyniki. Wykonawca zapisuje liczby w raporcie S0 (sekcja „M1") i **wybiera źródło prawdy dla Task 3**: tę z trzech wartości, która zgadza się ze zmierzoną w C, B i W. **A nie blokuje bramki:** jeśli w A zmierzone dostarczanie to 0 (brak częstotliwości do porównania), zapisz to jako „A otwarte" i przejdź dalej; A rozstrzygają Task 5, 10 i M4. Brak wartości zgodnej z C/B/W = STOP, wynik wraca do użytkownika.

### Task 3: Rzeczywista częstotliwość wejścia tapa (T2; naprawa C i `ec0b`)

**Files:**
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift`, `Sources/MeetNotesRecording/SystemTapSource.swift` (`build()`, `startCapture()`; `HALCapture` bez zmian)
- Test: `Tests/MeetNotesRecordingTests/CaptureFormatTests.swift` (nowy)

**Interfaces:**
- Consumes: Task 2 (`nominalSampleRate`) i wybór źródła z M1.
- Produces: `CoreAudioDevices.captureFormat(tap: AVAudioFormat, deviceRate: Double) -> AVAudioFormat` — gdy `deviceRate > 0` i różni się od `tap.sampleRate` o więcej niż 0,5 Hz, zwraca format z tą samą liczbą kanałów i typem próbek jak tap, ale `sampleRate: deviceRate`; inaczej zwraca `tap` bez zmian.
  `SystemTapSource` podaje `HALCapture` ten format jako `inputFormat`; **format toru zostaje deklarowany jak dziś** (`prepare()`), więc konwerter przelicza do niego. `rebuild()` wywołuje `startCapture()`, więc korzysta z tej samej funkcji.

- [ ] **Step 1: Write the failing tests:** `captureFormatKeepsTheTapFormatWhenRatesAgree` (48 000 i 48 000 → ten sam obiekt, `===`), `captureFormatTakesTheDeviceRateWhenTheyDiffer` (tap 48 000, urządzenie 44 100 → `sampleRate == 44_100`, kanały bez zmian), `captureFormatIgnoresAnUnreadableDeviceRate` (urządzenie 0 → tap bez zmian).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** funkcję i użyj jej w `SystemTapSource.startCapture()`; źródło `deviceRate` wg M1.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 602/602.
- [ ] **Step 5: Commit.**
- [ ] **Step 6: Mutation** (po commicie): próg 0,5 Hz → 50 000 (pada `…TakesTheDeviceRate…`); zawsze `tap` (pada ten sam test); `git checkout` po każdej.
- [ ] **Step 7: STOP M2 (użytkownik):** nagrania **C** i **W** (po 60 s z mową). Kryterium: zegar do pliku 1,0 (`effectiveSampleRate` ≈ deklarowanej ±0,1 %), `Track.rateMismatch == nil` w obu; **W nie może się pogorszyć względem sesji `82c4`** (47 998 Hz). Nie spełnione = STOP.

### Task 4: Nasłuch zmian częstotliwości i bramka przebudowy (T3)

**Files:**
- Modify: `Sources/MeetNotesRecording/DeviceWatcher.swift` (konstruktor `init(object:selector:)`, istniejący zostaje), `Sources/MeetNotesRecording/SystemTapSource.swift`
- Create: `Sources/MeetNotesRecording/RebuildGate.swift`
- Test: `Tests/MeetNotesRecordingTests/RebuildGateTests.swift`

**Interfaces:**
- Consumes: Task 3 (`captureFormat` używany przez `startCapture()` w `rebuild()`).
- Produces: `enum RebuildDecision: Equatable { case now; case deferred(until: Double) }`;
  `struct RebuildGate { init(minInterval: Double = 1.0, maxPerMinute: Int = 6); mutating func decide(now: Double) -> RebuildDecision }` — `.now`, gdy od ostatniej przebudowy minęło co najmniej `minInterval` i w ostatnich 60 s było mniej niż `maxPerMinute`; `.deferred(until: ostatnia + minInterval)`, gdy za wcześnie; `.deferred(until: najstarsza przebudowa w oknie + 60)`, gdy osiągnięto `maxPerMinute`. Bramka **nigdy nie odrzuca**: zawsze wyznacza termin, więc ostatni stan jest zastosowany bez następnego zdarzenia (pętla A2DP↔HFP zwalnia do `maxPerMinute` na minutę, ale końcowy stan jest poprawny).
  `DeviceWatcher(object: AudioObjectID, selector: AudioObjectPropertySelector)`: nasłuch na konkretnym obiekcie. `stop()` musi zdejmować nasłuch z **zapamiętanego** obiektu: dziś robi to zawsze na `kAudioObjectSystemObject` (`DeviceWatcher.swift` l. 23), więc `init` zapamiętuje obiekt (istniejący `init(selector:)` ustawia obiekt systemowy).
  `SystemTapSource`: nasłuch `kAudioDevicePropertyNominalSampleRate` na urządzeniu zbiorczym **i** na bieżącym wyjściu. `kAudioStreamPropertyVirtualFormat` (spec §3 T3) pomijamy **świadomie**: wymaga obiektu strumienia; dodać, jeśli M4 pokaże zmianę formatu bez zmiany częstotliwości nominalnej (spec poprawiony zgodnie z tą decyzją); **istniejący nasłuch zmiany domyślnego wyjścia też przechodzi przez bramkę**. `installListeners()` wołane w `start()` **i na końcu każdego `rebuild()`** (nowe urządzenie zbiorcze ma nowy `AudioObjectID`); `removeListeners()` w `teardown()` i `stop()`. `.deferred(until:)` planuje **jedno** oczekujące ponowienie naraz (`DispatchQueue.asyncAfter`; kolejne zdarzenia w czasie oczekiwania są scalane, a ponowienie czyta stan z chwili wykonania). Bramka niczego nie emituje: **żadnego `AudioSourceEvent.failed`** (patrz Global Constraints).

- [ ] **Step 1: Write the failing tests:** `gateAllowsTheFirstRebuild` (`.now`); `gateDefersASecondRebuildWithinTheMinimumInterval` (0 s `.now`, 0,5 s `.deferred(until: 1.0)`, 1,2 s `.now`); `gateDefersToTheEndOfTheMinuteAfterTheCap` (sześć `.now` w odstępach 2 s od 0 s, siódma w 12,5 s `.deferred(until: 60.0)`, w 61 s `.now`).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** bramkę, `DeviceWatcher(object:selector:)` i podłączenie w `SystemTapSource` jak wyżej.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 605/605.
- [ ] **Step 5: Commit.** Nasłuch sprzętowy bez testu jednostkowego (jak `DeviceWatcher` dziś); weryfikuje go M4.
- [ ] **Step 6: Mutation** (po commicie): `minInterval` na 0 (pada drugi test); `maxPerMinute` na 100 (pada trzeci: siódma byłaby `.now`); `git checkout` po każdej.

### Task 5: Eksperyment: układ urządzenia zbiorczego bez wyjścia (T1; bramka M2b i decyzja D4)

**Files:**
- Modify: `Sources/MeetNotesRecording/SystemTapSource.swift` (budowa słownika urządzenia zbiorczego do osobnej funkcji), `Sources/meetnotes-cli/CLI.swift` (`tap-rate --tap-only`)
- Test: `Tests/MeetNotesRecordingTests/AggregateLayoutTests.swift`

**Interfaces:**
- Produces: `public enum AggregateLayout { case withOutputSubdevice, tapOnly }`; `public init(layout: AggregateLayout = .withOutputSubdevice)` w `SystemTapSource` (domyślnie zachowanie dzisiejsze; `public`, bo używa go `meetnotes-cli`);
  `static func aggregateDescription(layout: AggregateLayout, outputUID: String, tapUUID: String) -> [String: Any]` — dla `.withOutputSubdevice` jak dziś (`kAudioAggregateDeviceMainSubDeviceKey`, `kAudioAggregateDeviceSubDeviceListKey` z wyjściem); dla `.tapOnly` pusta lista podurządzeń i **brak** klucza głównego podurządzenia (jak OpenWhispr).

- [ ] **Step 1: Write the failing tests:** `tapOnlyLayoutHasNoSubDevices` (pusta lista, brak `MainSubDevice`), `outputLayoutKeepsTheOutputAsMainSubDevice` (klucz równy `outputUID`, lista z jedną pozycją).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** funkcję, przepnij `build()` na nią, dodaj flagę CLI.
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 607/607.
- [ ] **Step 5: Commit.** Domyślny układ **bez zmiany**; aplikacja używa `.withOutputSubdevice`.
- [ ] **Step 6: Mutation** (po commicie): zamień gałęzie → oba testy padają; `git checkout`.
- [ ] **Step 7: STOP M2b (użytkownik):** `tap-rate` z `--tap-only` i bez, w konfiguracjach **A, B, C, W**; wyniki do raportu S0. **Decyzja D4 (użytkownik):** czy `.tapOnly` staje się domyślny. Rekomendacja: tak wyłącznie, gdy W i B niepogorszone, a A albo C poprawione; zmiana domyślnej to osobny commit (jedna linia w `SystemTapSource.init`) z wynikami M2b w komunikacie. Bez decyzji użytkownika układ nie zmienia się.

### Task 6: Ostrzeżenia po nagraniu: zła prędkość i tor martwy na tych samych słuchawkach (T5)

**Files:**
- Modify: `Sources/MeetNotesNotes/TrackProblem.swift` (`classify`, `neverStarted`)
- Test: `Tests/MeetNotesNotesTests/TrackProblemTests.swift`

**Interfaces:**
- Consumes: Task 1 (`rateMismatch`, `DeviceUID.same`); `SessionSummary.Track.deviceUIDs` (ostatni element = urządzenie na końcu nagrania).
- Produces: (a) w `TrackProblem.of(…)` tor z `rateMismatch != nil` (bez `failure`/`permissionDenied`) daje ostrzeżenie (`isWarning: true`): `line: "System audio was recorded at the wrong speed."` (dla mikrofonu „Microphone was recorded at the wrong speed."), `detail`: „The track's clock ran at N% of the declared rate, so its audio is sped up or slowed down and speech may be missing from the transcript. Bluetooth headphones switching modes can cause this. Record again with the Mac's microphone or speakers if it matters. Devices: <UID urządzeń toru z dziennika, po przecinku>." (`N` = zaokrąglony procent `rateMismatch × 100`; treść neutralna: nie rozstrzyga HFP czy A2DP).
  (b) `neverStarted` (tor `system`, 0 klatek, drugi tor nagrał): gdy `DeviceUID.same(system.deviceUIDs.last, mic.deviceUIDs.last)`, do `detail` dochodzi zdanie „Both tracks were on the same headset; in call mode it can block system audio. Use the Mac's microphone or speakers." (inaczej tekst bez zmian).

- [ ] **Step 1: Write the failing tests:** `wrongSpeedTrackIsAWarning` (48 000/16 500, kotwice ≥ 20 s → `isWarning`, `line` jak wyżej, `detail` zawiera „34%" oraz UID z `deviceUIDs`), `healthyRateGivesNoProblem`, `wrongSpeedDoesNotMaskAFailure` (`failure: "stalled30s"` zachowuje dotychczasowy komunikat), `neverStartedOnTheSameHeadsetMentionsCallMode`, `neverStartedOnDifferentDevicesKeepsTheOldText`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 612/612.
- [ ] **Step 5: Commit.**
- [ ] **Step 6: Mutation** (po commicie): usuń warunek `rateMismatch != nil` (pada `healthyRateGivesNoProblem`); `DeviceUID.same` na `true` w `neverStarted` (pada `…DifferentDevicesKeepsTheOldText`); `git checkout` po każdej.

### Task 7: Podpowiedź w pigułce przy martwym torze na słuchawkach (T4)

**Files:**
- Create: `Sources/MeetNotesRecording/PillHint.swift`
- Modify: `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`defaultInputUID()`, `defaultOutputUID()`, `isBluetooth(uid:)` przez `kAudioDevicePropertyTransportType` = Bluetooth lub Bluetooth LE), `Sources/MeetNotesApp/RecordingController.swift`, `Sources/MeetNotesApp/Snapshots.swift`
- Test: `Tests/MeetNotesRecordingTests/PillHintTests.swift`

**Interfaces:**
- Consumes: Task 1 (`DeviceUID.same`).
- Produces: `public enum PillHint { public static func systemStalled(stalled: Bool, micUID: String, outputUID: String, isBluetooth: Bool) -> String? }` (`public`, bo używa go `MeetNotesApp`) — gdy `stalled && DeviceUID.same(micUID, outputUID) && isBluetooth`: „Headset in call mode may block system audio. Switch the microphone or the output."; inaczej `nil` (informacja, nie błąd).
  `RecordingController`: nowe pola `micUID`, `outputUID`, `micIsBluetooth`, odświeżane w istniejącym liczniku co sekundę razem z `micName`/`outputName`; w tym zadaniu `micUID` = `defaultInputUID()` (Task 9 przełącza na UID faktycznie otwartego wejścia, bo po ręcznym wyborze domyślne już nie jest nagrywane); `stallHint: String?` wywołuje `PillHint.systemStalled`; wiersz pigułki pokazuje podpowiedź pod wierszem systemowym tylko przy `stallHint != nil`.

- [ ] **Step 1: Write the failing tests:** `hintAppearsForAStalledTrackOnTheSameBluetoothHeadset`, `hintIsAbsentWithoutAStall`, `hintIsAbsentForADifferentOrWiredDevice` (inne UID albo `isBluetooth == false`).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**; migawka `pill-system-stalled-headset` (światło i ciemny; sprawdź obie).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 615/615; `scripts/snapshot.sh`.
- [ ] **Step 5: Commit.**
- [ ] **Step 6: Mutation** (po commicie): zawsze `nil` (pada pierwszy); pominięty `isBluetooth` (pada trzeci); `git checkout`.

### Task 8: Wejście w pigułce: rdzeń (prefactoring bez ścieżki użytkownika; ścieżkę i demo dostarcza Task 9)

**Files:**
- Create: `Sources/MeetNotesRecording/InputChoice.swift`
- Modify: `Sources/MeetNotesRecording/MicrophoneSources.swift` (`RawMicrophoneSource.select(deviceUID:)`, `currentInputName`, nasłuch listy urządzeń), `Sources/MeetNotesRecording/CoreAudioDevices.swift` (`inputDevices()`, `deviceID(forUID:)` przez `kAudioHardwarePropertyTranslateUIDToDevice`)
- Test: `Tests/MeetNotesRecordingTests/InputChoiceTests.swift`

**Interfaces:**
- Produces: `public struct InputDevice: Equatable, Sendable { public var uid: String; public var name: String }`;
  `CoreAudioDevices.inputDevices() -> [InputDevice]` (urządzenia ze strumieniem wejściowym, bez urządzeń zbiorczych „meetnotes-tap");
  `CoreAudioDevices.deviceID(forUID uid: String) throws -> AudioObjectID`;
  `enum InputChoice { static func resolve(preferred: String?, available: [InputDevice], defaultUID: String?) -> String?` (UID do użycia: `preferred`, jeśli jest na liście; inaczej `defaultUID`; `nil` = domyślne systemu); `static func needsReopen(current: String?, preferred: String?, available: [InputDevice], defaultUID: String?) -> Bool` (prawda, gdy `resolve(...) != current`) `}`;
  `RawMicrophoneSource.select(deviceUID: String?)` — zapamiętuje preferencję (pole pod `lock`) i woła `reopen()`; `public var currentInputUID: String?` (pod `lock`, obok `currentInputName`); `open()` używa `InputChoice.resolve` oraz `deviceID(forUID:)` zamiast `defaultInputDevice()`; `currentInputName: String?` (pod `lock`, ustawiane w `open()`).
  Nasłuch: oprócz nasłuchu domyślnego wejścia `RawMicrophoneSource` nasłuchuje `kAudioHardwarePropertyDevices` (lista urządzeń) i przy zmianie woła `reopen()` **tylko gdy** `needsReopen` (odłączenie ręcznie wybranego wejścia przy niezmienionym domyślnym); przebudowa przez `RebuildGate` z Task 4.

- [ ] **Step 1: Write the failing tests:** `choiceKeepsThePreferredDeviceWhenPresent`, `choiceFallsBackToTheDefaultWhenThePreferredDeviceVanishes`, `choiceWithoutPreferenceUsesTheSystemDefault`, `choiceIsNilWhenThereIsNothingToChoose`, `reopenWhenThePreferredDeviceVanished`, `noReopenWhenTheChoiceIsUnchanged`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** jak wyżej; `reopen()` nadal emituje `.deviceChanged(uid)` (wpis `device.changed` w dzienniku).
- [ ] **Step 4: Run** `scripts/test.sh` — Expected: 621/621.
- [ ] **Step 5: Commit.**
- [ ] **Step 6: Mutation** (po commicie): `resolve` zawsze zwraca `preferred` (pada test znikającego urządzenia); `needsReopen` zawsze `false` (pada `reopenWhenThePreferredDeviceVanished`); `git checkout`.

### Task 9: Wejście w pigułce: interfejs (cięcie pionowe: menu → przełączenie → pigułka pokazuje faktyczne wejście)

**Files:**
- Modify: `Sources/MeetNotesApp/RecordingController.swift`, `Sources/MeetNotesApp/Snapshots.swift`

**Interfaces:**
- Consumes: Task 8.
- Produces: `RecordingController` trzyma referencję `private var mic: RawMicrophoneSource?` utworzoną w `start(…)` (dziś `RawMicrophoneSource()` jest w literale tablicy, `RecordingController.swift` l. 50, bez referencji) i przekazaną do `SessionRecorder`; `selectInput(uid: String?)` woła `mic?.select(deviceUID:)`; `micName` w liczniku sekundowym to `mic?.currentInputName ?? CoreAudioDevices.defaultInputName()` (zamiast bezwarunkowego nadpisywania domyślnym, l. 77), a `micUID` to `mic?.currentInputUID ?? CoreAudioDevices.defaultInputUID()`, z `micIsBluetooth` liczonym dla tego UID (`isBluetooth(uid:)`), żeby podpowiedź z Task 7 diagnozowała **faktycznie nagrywane** wejście. W wierszu „Microphone: <nazwa>" mała strzałka `⌄` otwiera `Menu`: „System default" (zaznaczone domyślnie) i lista `inputDevices()`. Bez nowych ekranów, bez zapisu preferencji.

- [ ] **Step 1: Implement** (kod UI; testy jednostkowe nie dotyczą: aplikacja nie ma celu testowego; logika jest w Task 8).
- [ ] **Step 2: Run** `scripts/test.sh` — Expected: 621/621 (bez zmian); `scripts/snapshot.sh` z migawką `pill-input-menu` (menu rysowane jako lista w miejscu, jak popover w migawkach 2.0.1; światło i ciemny).
- [ ] **Step 3: Commit.** Działanie na żywo potwierdza M4.

### Task 10: Spike S1: ScreenCaptureKit jako pomiar (osobna gałąź, bramka M3)

Niezależny od Task 3–9: może ruszyć zaraz po Task 2, równolegle (D1 „równolegle"), gdy użytkownik wyrazi zgodę.

**Files:** osobna gałąź `spike/f202-s1`, **nie scalana do `master`**; wynik trafia do raportu S0 (sekcja „S1") na gałęzi fazy.

- [ ] **Step 1:** Tylko po wyraźnej zgodzie użytkownika na Screen Recording dla tego jednego narzędzia. Jednorazowe polecenie CLI `sck-rate [--seconds N]`: `SCStream` z `capturesAudio = true`, `sampleRate = 48_000`, `channelCount = 2`, filtr na wyświetlacz, `excludesCurrentProcessAudio = true`; wypisuje liczbę klatek audio i zmierzoną częstotliwość. Bez testów (spike).
- [ ] **Step 2: STOP M3 (użytkownik):** uruchomienie w konfiguracjach A, B, C, W (jak M1). Wynik: czy SCK daje klatki i poprawną prędkość, zwłaszcza w A.
- [ ] **Step 3:** Wykonawca dopisuje wyniki do raportu i **nie** proponuje przejścia na SCK sam: decyzja wraca do użytkownika z danymi M1–M4.

### Task 11: Odbiór na żywo, dokumenty, przegląd

- [ ] **Step 1: STOP M4 (użytkownik):** nowy build (`scripts/run.sh`), nagranie **A** na prawdziwym spotkaniu Teams, 3–5 min, oraz krótkie **W**. Kryteria dla A: tor `system` ma klatki; `effectiveSampleRate` toru `system` w granicach **±0,1 %** deklarowanej (`rateMismatch == nil` to tylko dolna poprzeczka ±5 %, niewystarczająca dla celu fazy); transkrypt „Them" zawiera rozmówców; pigułka nie pokazuje fałszywego alarmu; menu wejścia działa (zmiana na wbudowany mikrofon, powrót do „System default", wyłączenie wybranych słuchawek w trakcie nagrania wraca do domyślnego z `device.changed` w dzienniku). Wykonawca czyta dziennik i podsumowanie ścieżkami bezwzględnymi.
- [ ] **Step 2: Gdy kryteria A niespełnione:** STOP. Wykonawca nie ogłasza sukcesu; raport z danymi (M1–M4, M2b, ewentualnie M3) idzie do użytkownika z opcjami: promocja `.tapOnly` (Task 5), przejście na ScreenCaptureKit (wymaga zmiany uprawnień), albo udokumentowanie ograniczenia i poprzestanie na komunikatach (Task 6, 7). Decyzja należy do użytkownika.
- [ ] **Step 3:** Zaktualizuj `docs/superpowers/BACKLOG.md` (pozycja o słuchawkach: zrobione/niezrobione z dowodami), `docs/superpowers/ROADMAP.md` (faza 2.0.2), `CLAUDE.md` (akapit fazy 2.0.2, liczba testów), raport S0 (M1, M2, M2b, M4), oraz artefakt „Mapa faz".
- [ ] **Step 4:** Przegląd całej gałęzi świeżym recenzentem (Review Focus powyżej verbatim), poprawki jednym przebiegiem, PR do `master`; scala użytkownik.
