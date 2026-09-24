# Plan E — poprawki po recenzjach (ChatGPT, Hermes/DeepSeek)

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** naprawić błędy wskazane w recenzjach z 2026-09-24: preset zamrożony przy starcie nagrania, wybór presetu w pływającym oknie, odsiew przesłuchu przed ASR, nadzór każdego toru, bezpieczne wznawianie, uczciwe etykiety sondy, odtwarzanie „Me" z mikrofonu.

**Architektura:** bez zmian w podziale modułów. Każde zadanie E zmienia pliki powstałe w A–D i ma **ściśle określone miejsce w kolejności** — tabela niżej.

**Specyfikacja:** oba specy po zadaniu 0 (przegląd §6, kroki 14–18 dotyczą tego planu). Przegląd: `2026-09-24-faza1-00-przeglad.md` §10.

## Wspólne ograniczenia

Obowiązują w całości: przegląd §4. Dodatkowo:

- ✅ **Kod tego planu sprawdzony przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet)**: wszystkie bloki weszły dosłownie, bez poprawek kompilacji; `scripts/test.sh` 99/99; mutacje z E1 krok 9 i E3 krok 8 dały czerwień. E4 nie ma testów automatycznych — sprawdza D3. Gdyby mimo to kompilacja padła, napraw **minimalnie**, bez zmiany zachowania z komentarza, i opisz w raporcie.
- Zmiany podane są jako „zamień blok A na blok B". Blok A ma wystąpić w pliku dokładnie raz. Jeśli nie występuje — **STOP**, nie zgaduj: plik różni się od planu.

## Kolejność

| Zadanie | Wykonaj po | Przed | Liczba testów po zadaniu |
|---|---|---|---|
| **E1** rdzeń: dziennik, nadzór torów, sprzątanie Core Audio | A9 | A10 | 47 |
| **E2** dostawcy: sonda, cache, klucz, walidacja | B3 | B4 | 70 |
| **E3** transkrypcja: przesłuch, wznawianie, migawka, luki | C3 | C4 | 99 |
| **E4** aplikacja: preset przy starcie, pływające okno, odtwarzanie, wznowienie | D2 | D3 | 99 |

## Na co patrzeć przy przeglądzie

1. **Zmiana chipa presetu w trakcie nagrania** → transkrypcja idzie presetem ze **startu**. Test ręczny D3 (po E4).
2. **Mikrofon słyszy głośniki** → fragment skorelowany z kanałem systemowym nie trafia do ASR. Test `crosstalkFromSpeakersIsDroppedBeforeASR` (E3).
3. **Tap umiera, mikrofon dalej działa** → `track.failed` po 30 s, sesja trwa. Test `deadTrackIsFlaggedWhileOtherContinues` (E1).
4. **Wznowienie tym samym `runID` z innym presetem** → odmowa zamiast cudzych wyników. Test `resumingWithADifferentPresetIsRefused` (E3).
5. **Błąd 429 podczas sondy języka** → „unknown", nie „automatic". Test `rateLimitDuringLanguageProbeIsUnknownNotAutomatic` (E2).

---

### Zadanie E1: Rdzeń — dziennik, nadzór torów, sprzątanie Core Audio

Status: ✅ zweryfikowane przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet): kompiluje się bez żadnej poprawki, `scripts/test.sh` 99/99 po całym planie E. Źródła: ChatGPT #9, #10, #12, 🟡 wycieki; Hermes 2.1, 2.3, 4.2.

**Pliki:**
- Zmień: `Sources/MeetNotesSessionFormat/SessionJournal.swift`, `Sources/MeetNotesRecording/SessionRecorder.swift`, `FormatConverter.swift`, `HALCapture.swift`, `SystemTapSource.swift`, `MicrophoneSources.swift`
- Test: dopisz do `Tests/MeetNotesSessionFormatTests/SessionJournalTests.swift` i `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift`

**Interfejsy:**
- Dostarcza: `SessionRecorder(…, trackStallSeconds: Double = 30)` — tor bez porcji przez 30 s dostaje `track.failed` z powodem `stalled30s`, sesja trwa. `tick()` przed `start()` nic nie robi. `FormatConverter.failures: Int`. `HALCapture(…, onChunk:, onFailure:)`. `VoiceProcessedMicrophoneSource` zgłasza `.failed("inputDeviceChanged…")` przy zmianie wejścia.

- [ ] **Krok 1: Testy, które padną.** Na końcu `SessionJournalTests.swift` dopisz:

```swift
@Test func completeButCorruptLastLineIsAnError() throws {
    // ChatGPT #12: tolerujemy tylko urwany fragment BEZ kończącego LF.
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    try Data("{\"type\":\"session.started\",\"hostTime\":1}\nGARBAGE\n".utf8).write(to: url)
    #expect(throws: JournalError.corruptLine(2)) { _ = try SessionJournal.read(url: url) }
}
```

Na końcu `SessionRecorderTests.swift` dopisz:

```swift
@Test func tickBeforeStartDoesNothing() {
    // Hermes 2.1: tick przed start nie może zakończyć sesji jako cisza.
    let r = SessionRecorder(directory: sessionDir(), sources: [], conditions: [SilenceCondition(seconds: 1)],
                            clock: ManualHostClock(10 * s), timebase: ns)
    r.tick()
    #expect(r.endReason == nil)
}

@Test func deadTrackIsFlaggedWhileOtherContinues() throws {
    // ChatGPT #9: tap umiera, mikrofon dostarcza dalej — awaria nie może się schować za żywym torem.
    final class Silent: AudioSource, @unchecked Sendable {
        let trackID = "system"
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
        func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
        func stop() {}
    }
    final class Pump: AudioSource, @unchecked Sendable {
        let trackID = "mic_raw"
        var handler: (@Sendable (AudioSourceEvent) -> Void)?
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 16_000, channels: 1, deviceUID: "m") }
        func start(_ h: @escaping @Sendable (AudioSourceEvent) -> Void) throws { handler = h }
        func stop() {}
    }
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let mic = Pump()
    let r = SessionRecorder(directory: dir, sources: [Silent(), mic], conditions: [StallCondition(seconds: 30)],
                            clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    for k in 1...40 {
        clock.set(UInt64(k) * s)
        mic.handler?(.chunk(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: UInt64(k) * s)))
        r.tick()
    }
    #expect(r.endReason == nil) // mikrofon żyje, sesja trwa
    r.stop()
    let sys = try #require(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "system" })
    #expect(sys.failure == "stalled30s")
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh` — oczekiwane: kod `1`; `completeButCorruptLastLineIsAnError` i `tickBeforeStartDoesNothing` padają, a `deadTrackIsFlaggedWhileOtherContinues` pada błędem kompilacji albo oczekiwaniem.

- [ ] **Krok 3: Dziennik.** W `SessionJournal.read` zamień:

```swift
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
```

na:

```swift
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        // Tylko ostatni fragment BEZ kończącego LF może być urwanym zapisem: append pisze
        // linię razem z LF jednym wywołaniem. Zakończona, a niepoprawna linia to uszkodzenie.
        let unterminatedLast = data.last != 0x0A ? lines.count - 1 : -1
        var events: [JournalEvent] = []
        for (index, line) in lines.enumerated() where !line.isEmpty {
            do {
                events.append(try decoder.decode(JournalEvent.self, from: Data(line)))
            } catch {
                if index == unterminatedLast { break }
                throw JournalError.corruptLine(index + 1)
            }
        }
```

- [ ] **Krok 4: Rejestrator — nadzór torów.** W `SessionRecorder.swift`:

(a) pod `private var zeroResolved: Set<String> = []` dopisz:

```swift
    private let trackStallSeconds: Double
    private var lastChunkByTrack: [String: UInt64] = [:]
    private var stalledTracks: Set<String> = []
```

(b) w `init` zamień `silenceThresholdDBFS: Double = -50, zeroWatch: [String: Double] = ["system": 60]) {` na `silenceThresholdDBFS: Double = -50, zeroWatch: [String: Double] = ["system": 60], trackStallSeconds: Double = 30) {`, a `self.zeroWatch = zeroWatch` na `self.zeroWatch = zeroWatch\n        self.trackStallSeconds = trackStallSeconds`.

(c) w `handle`, pod `lastChunkAt = max(lastChunkAt, chunk.hostTime)` dopisz `lastChunkByTrack[trackID] = chunk.hostTime`.

(d) zamień całą funkcję `tick()` na:

```swift
    public func tick() {
        let now = clock.now()
        lock.lock()
        var reason: EndReason?
        if !finishing, let journal { // bez dziennika sesja jeszcze nie ruszyła (Hermes 2.1)
            reason = evaluateLocked(now: now)
            // Każdy tor z osobna: martwy tor nie chowa się za żywym (ChatGPT #9).
            for s in started where !ended.contains(s.trackID) && !stalledTracks.contains(s.trackID) {
                let last = lastChunkByTrack[s.trackID] ?? startedAt
                if timebase.secondsBetween(now, last) >= trackStallSeconds {
                    try? journal.append(.trackFailed(s.trackID, reason: "stalled\(Int(trackStallSeconds))s", hostTime: now))
                    stalledTracks.insert(s.trackID)
                }
            }
        }
        lock.unlock()
        if let reason { finish(reason) }
    }
```

- [ ] **Krok 5: Błędy konwersji nie znikają (ChatGPT #10).** W `FormatConverter.swift`:
  - pod `private let converter: AVAudioConverter` dopisz `/// Nieudane konwersje — źródło zgłasza je jako .failed zamiast po cichu gubić dźwięk.\n    public private(set) var failures = 0`;
  - w `convertSlice` zamień `guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }` na `guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { failures += 1; return [] }` oraz `guard error == nil, status != .error, let p = out.int16ChannelData else { return [] }` na `guard error == nil, status != .error, let p = out.int16ChannelData else { failures += 1; return [] }`;
  - w `convert` zamień `if let slice = Self.slice(buffer, from: start, count: n) { out += convertSlice(slice) }` na `if let slice = Self.slice(buffer, from: start, count: n) { out += convertSlice(slice) } else { failures += 1 }`.

W `HALCapture.swift`:
  - w `init` zamień `onChunk: @escaping @Sendable (AudioChunk) -> Void) throws {` na `onChunk: @escaping @Sendable (AudioChunk) -> Void, onFailure: @escaping @Sendable (String) -> Void = { _ in }) throws {`, dodaj pole `private let onFailure: @Sendable (String) -> Void` i przypisanie `self.onFailure = onFailure`;
  - w `start` pod `let emit = onChunk` dopisz `let fail = onFailure`, a `let samples = conv.convert(buf)` zamień na:

```swift
            let before = conv.failures
            let samples = conv.convert(buf)
            if conv.failures > before && (conv.failures == 1 || conv.failures % 1_000 == 0) {
                fail("convert failures: \(conv.failures)")
            }
```

  - zamień `guard s2 == noErr else { throw AudioSourceError.coreAudio("DeviceStart", s2) }` na:

```swift
        guard s2 == noErr else {
            AudioDeviceDestroyIOProcID(device, proc) // 🟡 bez tego IOProc wycieka przy nieudanym starcie
            procID = nil
            throw AudioSourceError.coreAudio("DeviceStart", s2)
        }
```

W `SystemTapSource.startCapture` i `RawMicrophoneSource.open` wywołanie `HALCapture(…) { h(.chunk($0)) }` zamień na jawne etykiety: `HALCapture(device: …, inputFormat: …, sampleRate: …, channels: …, onChunk: { h(.chunk($0)) }, onFailure: { h(.failed($0)) })` (argumenty pozycyjne bez zmian).

W `VoiceProcessedMicrophoneSource`, w bloku `installTap`, zamień `let s = conv.convert(buf)` na:

```swift
            let before = conv.failures
            let s = conv.convert(buf)
            if conv.failures > before && (conv.failures == 1 || conv.failures % 1_000 == 0) {
                handler(.failed("convert failures: \(conv.failures)"))
            }
```

Testu jednostkowego na błąd konwertera nie ma: niezgodny format bufora może skończyć się wyjątkiem Objective-C zamiast błędu, więc taki test mógłby wywrócić cały proces testów.

- [ ] **Krok 6: Wyciek tapu (Hermes 2.3).** W `SystemTapSource.build()` zamień:

```swift
        let fmt = try CoreAudioDevices.tapFormat(of: tapID)
        lock.lock(); tap = tapID; aggregate = aggID; lock.unlock()
```

na:

```swift
        let fmt: AVAudioFormat
        do {
            fmt = try CoreAudioDevices.tapFormat(of: tapID)
        } catch {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
        lock.lock(); tap = tapID; aggregate = aggID; lock.unlock()
```

- [ ] **Krok 7: Mikrofon z AEC przy zmianie wejścia (ChatGPT #9, Hermes 4.2).** `AVAudioEngine` z przetwarzaniem głosu nie przebudowuje się tu sam. Zamiast udawać ciągłość, tor zgłasza awarię; surowy mikrofon przebudowuje się i nagrywa dalej, a E3 przełącza transkrypcję na `mic_raw`. W `VoiceProcessedMicrophoneSource`:
  - pod `private var converter: FormatConverter?` dopisz `private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultInputDevice)`;
  - w `start`, pod `try engine.start()` dopisz `watcher.start { handler(.failed("inputDeviceChanged: mic_aec stopped, mic_raw continues")) }`;
  - w `stop`, na początku dopisz `watcher.stop()`.

- [ ] **Krok 8: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 47/47 testów uruchomionych i zaliczonych.`

- [ ] **Krok 9: Mutacja.** W nowym `tick()` zamień `>= trackStallSeconds` na `>= trackStallSeconds * 100`. `scripts/test.sh --filter deadTrackIsFlaggedWhileOtherContinues` — oczekiwane: pada. Przywróć; `47/47`.

- [ ] **Krok 10: Commit.**

```bash
git add Sources Tests
git commit -m "Rdzen: nadzor kazdego toru, bledy konwersji jawne, sprzatanie Core Audio" -m "Po recenzjach ChatGPT i Hermesa: martwy tor dostaje track.failed po 30 s, tick przed startem nic nie robi, zakonczona uszkodzona linia dziennika to blad, wyciek tapu i IOProc przy bledzie startu."
```

---

### Zadanie E2: Dostawcy — sonda języka, cache, klucz w błędzie, walidacja

Status: ✅ zweryfikowane przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet): kompiluje się bez żadnej poprawki, `scripts/test.sh` 99/99 po całym planie E. Źródła: ChatGPT #5, #6, #11, 🟡 pusty model.

**Pliki:**
- Zmień: `Sources/MeetNotesProviders/Probe.swift`, `Preset.swift`, `OpenAICompatibleClient.swift`
- Test: dopisz do `Tests/MeetNotesProvidersTests/ProbeTests.swift`, `ClientTests.swift`, `PresetTests.swift`

**Interfejsy:**
- Dostarcza: `ProbeResult.language: LanguageCode?` (ostatni parametr `init`, domyślnie `nil`); `ProbeCache.result(provider:model:role:language: LanguageCode? = nil)` — klucz zawiera język. `classifyLanguage`: „automatic" tylko przy odrzuceniu parametru (HTTP 400/422); każdy inny błąd albo niestabilna odpowiedź z językiem → „unknown". Treść błędu HTTP bez klucza. `Preset.validate()` odrzuca pusty model ASR.

- [ ] **Krok 1: Testy, które padną.** Na końcu `ProbeTests.swift`:

```swift
@Test func rateLimitDuringLanguageProbeIsUnknownNotAutomatic() async {
    // ChatGPT #5: 429 to nie odrzucony parametr języka.
    let http = StubHTTP { _, body in
        if body["language"] != nil && !isPolishClip(body) { return fail(429, "{\"error\":\"rate limited\"}") }
        return transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown)
}

@Test func unstableAnswerWithLanguageIsNotEnforced() async {
    // ChatGPT #5: jedna różna odpowiedź to jeszcze nie dowód wymuszania.
    let counter = Counter()
    let http = StubHTTP { _, body in
        body["language"] != nil ? transcript("jeden dwa \(counter.next())") : transcript("one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown)
}
```

Na końcu `ClientTests.swift`:

```swift
@Test func errorBodyEchoingTheKeyIsSanitized() async throws {
    // ChatGPT #11: serwer odsyła nagłówek w treści błędu — klucz nie może trafić do cache ani komunikatu.
    let http = StubHTTP { _, _ in fail(400, "{\"error\":\"bad header Authorization: Bearer sk-or-v1-SECRET123\"}") }
    do {
        _ = try await OpenAICompatibleClient(provider: openRouter, key: "sk-or-v1-SECRET123", http: http).listModels()
        Issue.record("oczekiwano błędu")
    } catch {
        #expect(!"\(error)".contains("SECRET123"))
    }
}
```

Na końcu `PresetTests.swift`:

```swift
@Test func probeResultsForDifferentLanguagesDoNotOverwriteEachOther() {
    // ChatGPT #6: klasa obsługi języka jest wynikiem dla KONKRETNEGO języka.
    var cache = ProbeCache()
    let id = UUID()
    cache.record(ProbeResult(providerID: id, model: "m", role: .asr, works: true, languageHandling: .enforced, language: .polish))
    cache.record(ProbeResult(providerID: id, model: "m", role: .asr, works: true, languageHandling: .automatic, language: .english))
    #expect(cache.result(provider: id, model: "m", role: .asr, language: .polish)?.languageHandling == .enforced)
    #expect(cache.result(provider: id, model: "m", role: .asr, language: .english)?.languageHandling == .automatic)
}

@Test func presetWithEmptyModelCannotBeSaved() {
    var file = PresetsFile()
    #expect(throws: PresetError.missingASR) {
        try file.upsert(Preset(name: "Polish", language: .polish, asr: RoleAssignment(providerID: UUID(), model: " ")))
    }
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh` — oczekiwane: kod `1` (m.in. brak parametru `language:` w `ProbeResult`).

- [ ] **Krok 3: `ProbeResult.language` i klucz cache.** W `Probe.swift`:
  - pod `public var checkedAt: Date` dopisz `/// Język, dla którego sonda ASR klasyfikowała obsługę języka. Część klucza cache.\n    public var language: LanguageCode?`;
  - w `init` zamień `checkedAt: Date = Date()) {` na `checkedAt: Date = Date(), language: LanguageCode? = nil) {` i dopisz `self.language = language`;
  - w `probe`, w gałęzi `case .asr:` pod `let lang = language ?? .english` dopisz `r.language = language`.

W `Preset.swift` zamień w `ProbeCache`:

```swift
    static func key(_ provider: UUID, _ model: String, _ role: Role) -> String {
        "\(provider.uuidString)|\(model)|\(role.rawValue)"
    }

    public mutating func record(_ r: ProbeResult) { results[Self.key(r.providerID, r.model, r.role)] = r }

    public func result(provider: UUID, model: String, role: Role) -> ProbeResult? {
        results[Self.key(provider, model, role)]
    }
```

na:

```swift
    static func key(_ provider: UUID, _ model: String, _ role: Role, _ language: LanguageCode?) -> String {
        "\(provider.uuidString)|\(model)|\(role.rawValue)|\(language?.rawValue ?? "-")"
    }

    public mutating func record(_ r: ProbeResult) { results[Self.key(r.providerID, r.model, r.role, r.language)] = r }

    public func result(provider: UUID, model: String, role: Role, language: LanguageCode? = nil) -> ProbeResult? {
        results[Self.key(provider, model, role, language)]
    }
```

- [ ] **Krok 4: Surowsza klasyfikacja.** W `Probe.swift` zamień całe `classifyLanguage` na:

```swift
    public func classifyLanguage(model: String, language: LanguageCode) async -> LanguageHandling {
        let clip = ProbeClips.mismatched(for: language)
        func run(_ lang: LanguageCode?) async -> Result<String, any Error> {
            do {
                let t = try await client.transcribe(wav: clip.wav, model: model, language: lang, shape: .audioTranscriptions)
                return .success(ProbeClips.normalize(t.text))
            } catch {
                return .failure(error)
            }
        }
        guard case .success(let b1) = await run(nil), case .success(let b2) = await run(nil), b1 == b2 else {
            return .unknown // model niedeterministyczny albo błąd bez języka
        }
        let a1 = await run(language)
        if case .failure(let e) = a1 {
            // „Automatyczny" tylko wtedy, gdy API odrzuciło sam parametr (400/422).
            // 401, 429, 500, przekroczony czas → nie wiemy (ChatGPT #5).
            if case ProviderError.http(let status, _)? = e as? ProviderError, status == 400 || status == 422 { return .automatic }
            return .unknown
        }
        guard case .success(let x1) = a1, case .success(let x2) = await run(language), x1 == x2 else {
            return .unknown // różne odpowiedzi z językiem — wymuszania nie da się stwierdzić
        }
        return x1 == b1 ? .automatic : .enforced
    }
```

- [ ] **Krok 5: Klucz w treści błędu.** W `OpenAICompatibleClient.json` zamień:

```swift
            throw ProviderError.http(resp.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
```

na:

```swift
            // Najpierw usuń klucz z całej treści, dopiero potem przytnij — inaczej przycięcie
            // w połowie klucza zostawiłoby jego fragment (ChatGPT #11).
            var body = String(decoding: data, as: UTF8.self)
            if let key, !key.isEmpty { body = body.replacingOccurrences(of: key, with: "••••") }
            throw ProviderError.http(resp.statusCode, String(body.prefix(300)))
```

- [ ] **Krok 6: Pusty model.** W `Preset.validate()` zamień `guard asr != nil else { throw PresetError.missingASR }` na `guard let asr, !asr.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingASR }`.

- [ ] **Krok 7: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 70/70 testów uruchomionych i zaliczonych.`

- [ ] **Krok 8: Commit.**

```bash
git add Sources/MeetNotesProviders Tests/MeetNotesProvidersTests
git commit -m "Dostawcy: surowsza sonda jezyka, cache per jezyk, klucz usuwany z tresci bledu" -m "Po recenzji ChatGPT: automatic tylko przy odrzuceniu parametru (400/422), inne bledy i niestabilne odpowiedzi daja unknown. Pusty model ASR nie przechodzi walidacji."
```

---

### Zadanie E3: Transkrypcja — przesłuch, wznawianie, migawka, luki

Status: ✅ zweryfikowane przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet): kompiluje się bez żadnej poprawki, `scripts/test.sh` 99/99 po całym planie E. Źródła: ChatGPT #1, #4, #7, #13, #14, #15, 🟡 czasy luk; Hermes 3.1, 3.2, 4.2.

**Pliki:**
- Utwórz: `Sources/MeetNotesTranscription/CrosstalkFilter.swift`
- Zmień: `Transcript.swift`, `TranscriptionRunner.swift`
- Zmień: `Tests/MeetNotesTranscriptionTests/SessionFixtures.swift` (stałe UUID w `snapshot()`)
- Test: dopisz do `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`

**Interfejsy:**
- Dostarcza: `CrosstalkFilter` (`correlationThreshold = 0.8`, `maxLagSeconds = 0.3`, `keep(_:mic:system:micOffsetSeconds:rate:)`). `RunSnapshot.preset: Preset` (pełna migawka) i `RunSnapshotError.chatShapeNotForMeetings`. `RunError.badRunID(String)`, `.inputMismatch`. `RunInput` (migawka, bramka, limit okna, ramki ścieżek) zapisany w `runs/<id>/input.json`; `RunDirectory.input`, `RunDirectory.isValid(runID:)`. `TranscriptionRunner(…, crosstalk: CrosstalkFilter = CrosstalkFilter())`.

- [ ] **Krok 1: Stałe identyfikatory w danych testowych.** Wznawianie porównuje teraz migawkę; `snapshot()` z losowymi UUID dawałby przy każdym wywołaniu inną migawkę, a istniejący test P5 dostałby `inputMismatch`. W `SessionFixtures.swift` zamień:

```swift
    let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(name: "Polish", language: language, asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"))
```

na:

```swift
    let provider = Provider(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "OpenRouter",
                            baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Polish", language: language,
                        asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"))
```

- [ ] **Krok 2: Testy, które padną.** Na końcu `RunnerTests.swift` dopisz:

```swift
@Test func crosstalkFromSpeakersIsDroppedBeforeASR() async throws {
    // W§1, rozdz. 17, ChatGPT #1: mikrofon słyszy głośniki, bramka energii uznałaby to za mowę.
    var sys = silence(seconds: 2, rate: 16_000)
    for _ in 0..<5 { sys += tone(seconds: 0.4, rate: 16_000) + silence(seconds: 0.3, rate: 16_000) }
    sys += silence(seconds: 5, rate: 16_000)
    // echo: 100 ms drogi akustycznej, ~14 dB ciszej
    let mic = Array(([Int16](repeating: 0, count: 1_600) + sys.map { Int16(Double($0) * 0.2) }).prefix(sys.count))
    let dir = try makeSession(system: sys, mic: mic)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    #expect(!t.utterances.isEmpty)
    #expect(t.utterances.allSatisfy { $0.speaker == .them })
}

@Test func runIDEscapingTheRunsDirectoryIsRejected() async throws {
    // ChatGPT #13.
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000))
    await #expect(throws: RunError.badRunID("../x")) {
        _ = try await TranscriptionRunner(session: dir, runID: "../x", snapshot: try snapshot(), client: client(ListeningASR())).run()
    }
}

@Test func resumingWithADifferentPresetIsRefused() async throws {
    // ChatGPT #4: te same granice okien nie mogą przenieść wyników na inny język albo model.
    let (samples, _) = burstTrack(seconds: 60, rate: 16_000)
    let dir = try makeSession(system: samples)
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(language: .english),
                                          client: client(ListeningASR())).run()
    }
}

@Test func snapshotCarriesTheWholePresetAndRefusesChatShape() throws {
    // ChatGPT #14 (pełna migawka) i #7 (bez znaczników słów nie ma spotkania).
    let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(name: "Polish", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "m"),
                        summary: RoleAssignment(providerID: provider.id, model: "s", prompt: "Decisions and owners"))
    #expect(try RunSnapshot(preset: preset, provider: provider, probe: nil).preset.summary?.prompt == "Decisions and owners")
    let chat = ProbeResult(providerID: provider.id, model: "m", role: .asr, works: true, shape: .chatAudio)
    #expect(throws: RunSnapshotError.chatShapeNotForMeetings) { _ = try RunSnapshot(preset: preset, provider: provider, probe: chat) }
}

@Test func failedEchoCancelledMicFallsBackToRaw() {
    // Hermes 4.2: martwy mic_aec nie może wypchnąć żywego mic_raw.
    let sum = SessionSummary(startedHostTime: 0, timebase: ns, tracks: [
        .init(id: "system", sampleRate: 48_000, channels: 2),
        .init(id: "mic_raw", sampleRate: 16_000, channels: 1),
        .init(id: "mic_aec", sampleRate: 16_000, channels: 1, failure: "inputDeviceChanged"),
    ])
    #expect(TranscriptionRunner.tracks(in: sum).map(\.id) == ["system", "mic_raw"])
}

@Test func gapTimesAreOnTheSessionTimeline() async throws {
    // 🟡 ChatGPT: luka „Me" przesunięta o opóźnienie startu mikrofonu.
    let mic = silence(seconds: 3, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 3, rate: 16_000)
    let dir = try makeSession(system: silence(seconds: 8, rate: 16_000), mic: mic, micOffset: 0.5)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(),
                                          client: client(ListeningASR(failWhen: { _ in true }))).run()
    let f = try #require(t.failedChunks.first)
    #expect(abs(f.start - 3.3) < 0.05) // 0,5 s przesunięcia + 2,8 s (ton w 3. s minus 0,2 s zapasu bramki)
}

@Test func eightyFiveMinutesStayAlignedAcrossWindowBoundaries() async throws {
    // P4 deterministycznie, bez „jeśli jest plik" (ChatGPT #15, Hermes 3.2). Długi: ~1 min w debug.
    let (samples, starts) = burstTrack(seconds: 85 * 60, rate: 16_000)
    let dir = try makeSession(system: samples)
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r85", snapshot: try snapshot(), client: client(asr)).run()
    let words = t.utterances.flatMap(\.words).sorted { $0.start < $1.start }
    #expect(words.count == starts.count)
    #expect(asr.requests > 10) // wiele okien, więc wiele granic
    for (w, s) in zip(words, starts) { #expect(abs(w.start - s) < 0.03) }
    for (a, b) in zip(words, words.dropFirst()) { #expect(a.end <= b.start) } // bez nakładek
    #expect(words.allSatisfy { $0.end > $0.start })
}
```

- [ ] **Krok 3: Uruchom i sprawdź, że pada.** `scripts/test.sh` — oczekiwane: kod `1` (brak `RunError`, `RunSnapshotError`, `CrosstalkFilter`).

- [ ] **Krok 4: Odsiew przesłuchu.** Utwórz `Sources/MeetNotesTranscription/CrosstalkFilter.swift`:

```swift
import Foundation

/// 🔴 Drugi tryb awarii bramki (W§1, rozdz. 17): przesłuch z głośników. Mikrofon słyszy
/// rozmówców, a bramka energii uznaje to za mowę — MacParakeet wstawiał tak urywki cudzych
/// zdań w środek zdań rozmówcy (52 z 53 wtrąceń ≤ 3 słowa). Fragment mikrofonu, którego
/// obwiednia energii idzie w parze z kanałem systemowym (z opóźnieniem drogi akustycznej
/// do 0,3 s), odpada przed ASR. Obwiednia z ramek 20 ms, nie próbki: tanio i odpornie na
/// barwę pokoju. Próg zachowawczy — gdy użytkownik mówi sam albo przez rozmówcę, obwiednie
/// się rozjeżdżają i fragment zostaje.
public struct CrosstalkFilter: Sendable {
    public var correlationThreshold = 0.8
    public var maxLagSeconds = 0.3

    public init() {}

    /// `micOffsetSeconds`: o ile później ruszył mikrofon niż ścieżka systemowa (oś sesji).
    public func keep(_ regions: [Range<Int>], mic: [Float], system: [Float], micOffsetSeconds: Double,
                     rate: Double = Resampler.asrRate) -> [Range<Int>] {
        let frame = Int(rate * EnergyGate.frameSeconds)
        let micEnv = EnergyGate.frameLevels(mic, rate: rate)
        let sysEnv = EnergyGate.frameLevels(system, rate: rate)
        let offsetFrames = Int((micOffsetSeconds / EnergyGate.frameSeconds).rounded())
        let maxLag = Int((maxLagSeconds / EnergyGate.frameSeconds).rounded())
        return regions.filter { r in
            let a = r.lowerBound / frame
            let b = min(max(a + 1, r.upperBound / frame), micEnv.count)
            guard a < b else { return true }
            let m = Array(micEnv[a..<b])
            var best = 0.0
            for lag in 0...maxLag {
                // echo w mikrofonie w chwili T pochodzi z systemu z chwili T - lag
                let s0 = a + offsetFrames - lag
                guard s0 >= 0, s0 + m.count <= sysEnv.count else { continue }
                best = max(best, Self.pearson(m, Array(sysEnv[s0..<(s0 + m.count)])))
            }
            return best < correlationThreshold
        }
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 2 else { return 0 }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        return sxx > 0 && syy > 0 ? sxy / (sxx * syy).squareRoot() : 0
    }
}
```

- [ ] **Krok 5: Pełna migawka i blokada czatu.** W `Transcript.swift`:
  - pod `public struct RunSnapshot: Codable, Equatable, Sendable {` dopisz `/// Pełny preset z chwili przebiegu — z korektą, podsumowaniem i promptami (spec §8, ChatGPT #14).\n    public var preset: Preset`;
  - w `init` pod `try preset.validate()` dopisz:

```swift
        // Bez znaczników słów pakowane okno rozciąga jedno „zdanie" na minuty ciszy,
        // a klikalna linia czasu kłamie (ChatGPT #7). Kształt czatowy — tylko dyktowanie.
        if probe?.shape == .chatAudio { throw RunSnapshotError.chatShapeNotForMeetings }
        self.preset = preset
```

  - nad `public struct RunSnapshot` dopisz `public enum RunSnapshotError: Error, Equatable {\n    case chatShapeNotForMeetings\n}\n`.

- [ ] **Krok 6: Wykonawca.** W `TranscriptionRunner.swift`:

(a) nad `public struct TranscriptionProgress` dopisz:

```swift
public enum RunError: Error, Equatable {
    case badRunID(String)
    /// Ten sam runID, inne wejście (preset, bramka, limit okna, ramki ścieżek) — ChatGPT #4.
    case inputMismatch
}

/// Wszystko, od czego zależą zapisane okna. Wznowienie tylko przy identycznym wejściu.
public struct RunInput: Codable, Equatable, Sendable {
    public var snapshot: RunSnapshot
    public var gate: EnergyGate.Config
    public var maxChunkSeconds: Double
    public var trackFrames: [String: Int]
}
```

(b) w `RunDirectory` pod `public var transcript: URL { … }` dopisz:

```swift
    public var input: URL { url.appendingPathComponent("input.json") }

    /// Jeden bezpieczny komponent ścieżki: bez `/`, bez `..`, bez kropki na początku (ChatGPT #13).
    public static func isValid(runID: String) -> Bool {
        !runID.isEmpty && runID.count <= 64 && !runID.hasPrefix(".")
            && runID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
```

(c) w `TranscriptionRunner` pod `public let gate: EnergyGate` dopisz `public let crosstalk: CrosstalkFilter`; w `init` zamień `maxChunkSeconds: Double = 59, gate: EnergyGate = EnergyGate()) {` na `maxChunkSeconds: Double = 59, gate: EnergyGate = EnergyGate(), crosstalk: CrosstalkFilter = CrosstalkFilter()) {` i dopisz `self.crosstalk = crosstalk`.

(d) w `tracks(in:)` zamień `if ids.contains("mic_aec") { out.append(("mic_aec", .me)) } else if ids.contains("mic_raw") { out.append(("mic_raw", .me)) }` na:

```swift
        let aecFailed = summary.tracks.first { $0.id == "mic_aec" }?.failure != nil // Hermes 4.2
        if ids.contains("mic_aec") && !aecFailed { out.append(("mic_aec", .me)) }
        else if ids.contains("mic_raw") { out.append(("mic_raw", .me)) }
```

(e) na początku `run(progress:)` — przed `let summary = try session.summarize()` — dopisz `guard RunDirectory.isValid(runID: runID) else { throw RunError.badRunID(runID) }`.

(f) **bezpośrednio** pod `try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("chunks"), withIntermediateDirectories: true)` — przed pętlą przygotowania ścieżek, nie za nią — dopisz:

```swift
        let input = RunInput(snapshot: snapshot, gate: gate.config, maxChunkSeconds: maxChunkSeconds,
                             trackFrames: Dictionary(summary.tracks.map { ($0.id, $0.frames ?? -1) }, uniquingKeysWith: { a, _ in a }))
        if let saved = try JSONFile.load(RunInput?.self, from: dir.input, default: nil) {
            guard saved == input else { throw RunError.inputMismatch }
        } else {
            try JSONFile.save(input, to: dir.input)
        }
        let clock = SessionClock(summary: summary)
```

(g) zamień pętlę przygotowania:

```swift
        for (id, speaker) in Self.tracks(in: summary) {
            speakers[id] = speaker
            let caf = try CAFReader(url: session.trackURL(id))
            let x = try Resampler.toASR(caf.samples, sampleRate: caf.sampleRate, channels: caf.channels)
            let chunks = ChunkPacker(maxSeconds: maxChunkSeconds).pack(gate.speechRegions(x, rate: Resampler.asrRate), samples: x)
            for c in chunks { plan.append((id, c, x)) }
        }
```

na:

```swift
        var systemX: [Float]?
        for (id, speaker) in Self.tracks(in: summary) { // `tracks(in:)` zwraca `system` pierwszy
            speakers[id] = speaker
            let caf = try CAFReader(url: session.trackURL(id))
            let x = try Resampler.toASR(caf.samples, sampleRate: caf.sampleRate, channels: caf.channels)
            var regions = gate.speechRegions(x, rate: Resampler.asrRate)
            if speaker == .me, let sys = systemX {
                let offset = summary.tracks.first { $0.id == id }?.offsetSeconds ?? 0
                regions = crosstalk.keep(regions, mic: x, system: sys, micOffsetSeconds: offset)
            }
            if id == "system" { systemX = x }
            let chunks = ChunkPacker(maxSeconds: maxChunkSeconds).pack(regions, samples: x)
            for c in chunks { plan.append((id, c, x)) }
        }
```

(h) czasy luk na osi sesji: zamień `failures.append(ChunkFailure(track: item.track, index: item.chunk.index, start: item.chunk.sourceStartSeconds,\n                                                 end: item.chunk.sourceEndSeconds, error: "\(error)"))` na:

```swift
                    failures.append(ChunkFailure(
                        track: item.track, index: item.chunk.index,
                        start: clock.sessionSeconds(track: item.track, trackSeconds: item.chunk.sourceStartSeconds),
                        end: clock.sessionSeconds(track: item.track, trackSeconds: item.chunk.sourceEndSeconds),
                        error: "\(error)"))
```

(i) w wywołaniu `Merger.merge(…)` zamień `clock: SessionClock(summary: summary)` na `clock: clock`.

- [ ] **Krok 7: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 99/99 testów uruchomionych i zaliczonych.` Test 85-minutowy trwa około minuty.

- [ ] **Krok 8: Mutacja (przesłuch).** W `CrosstalkFilter` zamień `public var correlationThreshold = 0.8` na `= 1.1`. `scripts/test.sh --filter crosstalkFromSpeakersIsDroppedBeforeASR` — oczekiwane: pada. Przywróć; `99/99`.

- [ ] **Krok 9: Commit.**

```bash
git add Sources/MeetNotesTranscription Tests/MeetNotesTranscriptionTests
git commit -m "Transkrypcja: odsiew przeslucha, bezpieczne wznawianie, pelna migawka presetu" -m "Po recenzjach: fragment mikrofonu skorelowany z kanalem systemowym odpada przed ASR; wznowienie tylko przy identycznym wejsciu (input.json); runID bez ../; model czatowy odrzucany dla spotkan; martwy mic_aec -> mic_raw; luki na osi sesji; test 85 minut."
```

---

### Zadanie E4: Aplikacja — preset przy starcie, pływające okno, odtwarzanie, wznowienie

Status: ✅ zweryfikowane przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet): kompiluje się bez żadnej poprawki, `scripts/test.sh` 99/99 po całym planie E. Źródła: ChatGPT #2, #3, #7, #8, #16, #17; Hermes 1.1, 4.5, 4.8. Testów automatycznych nie ma (interfejs) — sprawdza D3.

**Pliki:**
- Zamień w całości: `Sources/MeetNotesApp/RecordingController.swift`
- Zmień: `AppModel.swift`, `MeetNotesApp.swift`, `MeetingsView.swift`, `MeetingDetailView.swift`, `SetupView.swift`

**Interfejsy:**
- Dostarcza: `RecordingController.start(directory:presetLabel:onEnded:)`, `presetLabel`, `directory`, `showPanel(model:)`. `AppModel.startRecording()` odmawia bez ważnego presetu i zamraża preset (`<sesja>/preset.json`). `AppModel.transcribe(sessionURL:preset:)`, `AppModel.resume(_:)`. `SessionItem.runID`.

- [ ] **Krok 1: `RecordingController.swift` w całości.** Pływające okno służy teraz do wyboru presetu **przed** nagraniem (W§6), a w trakcie pokazuje preset zamrożony przy starcie:

```swift
import AppKit
import Foundation
import MeetNotesRecording
import Observation
import SwiftUI

/// Stan trwającego nagrania dla interfejsu i pływającego okna.
@MainActor
@Observable
final class RecordingController {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastEndReason: EndReason?
    /// Preset zamrożony przy starcie — pokazywany przez całe nagranie (ChatGPT #2).
    private(set) var presetLabel = ""
    /// Katalog trwającej sesji — lista sesji go pomija (Hermes 4.5: nie „Recovered").
    private(set) var directory: URL?
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?

    func start(directory: URL, presetLabel: String, onEnded: @escaping @MainActor (EndReason) -> Void) throws {
        let r = SessionRecorder(directory: directory,
                                sources: [SystemTapSource(), RawMicrophoneSource(), VoiceProcessedMicrophoneSource()])
        r.onEnded = { reason in
            Task { @MainActor in
                self.finish(reason)
                onEnded(reason)
            }
        }
        try r.start()
        recorder = r
        self.directory = directory
        self.presetLabel = presetLabel
        isRecording = r.endReason == nil
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                self.recorder?.tick()
            }
        }
    }

    func stop() { recorder?.stop(reason: .button) }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        recorder = nil
        directory = nil
    }

    /// 🔀 Odstępstwa 1 i 2 (`docs/design/macos.md` §10): okno zostaje na wierzchu, gdy aktywny
    /// jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    func showPanel(model: AppModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Recording"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecordingPanelView(model: model))
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

struct RecordingPanelView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rec = model.recording
        HStack(spacing: 10) {
            if rec.isRecording {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                // Stan nigdy samym kolorem: napis i licznik (macos.md §6.1).
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recording \(Self.clock(rec.elapsed))").monospacedDigit()
                    Text(rec.presetLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") { rec.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                // 🔴 Preset z językiem widoczny i wybierany przed startem (W§2, W§6).
                PresetMenu()
                Spacer()
                Button("Record") { model.startRecording() }
            }
        }
        .padding(12)
        .environment(model)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
```

- [ ] **Krok 2: `AppModel` — preset przy starcie, wznowienie, blokada czatu.**

(a) w `SessionItem` pod `var progress: Double?` dopisz `/// Ostatni przebieg transkrypcji — do wznowienia po przerwie albo restarcie (ChatGPT #17).\n    var runID: String?`.

(b) zamień `showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized` na:

```swift
        // ChatGPT #16: setup także wtedy, gdy dźwięk systemowy nigdy nie przeszedł testu tonem.
        showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !UserDefaults.standard.bool(forKey: "systemAudioVerified")
```

(c) w `reloadSessions` zamień `let transcript = latestTranscript(in: url)\n            return SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast, transcript: transcript)` na:

```swift
            let run = latestRun(in: url)
            return SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast,
                               transcript: run?.transcript, runID: run?.id)
```

i zamień całą funkcję `latestTranscript(in:)` na:

```swift
    func latestRun(in session: URL) -> (id: String, transcript: Transcript?)? {
        let runs = session.appendingPathComponent("runs")
        guard let id = ((try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []).sorted().last else { return nil }
        return (id, try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil))
    }
```

(d) w `savePreset`, na początku bloku `do {` dopisz:

```swift
            if let a = p.asr, probeCache.result(provider: a.providerID, model: a.model, role: .asr, language: p.language)?.shape == .chatAudio {
                return "This model returns no word timings, so it can't be used for meetings."
            }
```

(e) zamień całe funkcje `startRecording()` i `transcribe(sessionURL:preset:)` na:

```swift
    func startRecording() {
        // ChatGPT #2: preset — z językiem — ustalony PRZED startem i zamrożony na całą sesję.
        guard let preset = activePreset, (try? preset.validate()) != nil else {
            lastError = "Choose a preset with a language before recording."
            section = .presets
            return
        }
        let dir = paths.sessions.appendingPathComponent(Self.sessionName(Date()))
        do {
            try recording.start(directory: dir, presetLabel: Self.label(preset)) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadSessions()
                    self?.transcribe(sessionURL: dir, preset: preset)
                }
            }
            try? JSONFile.save(preset, to: dir.appendingPathComponent("preset.json"))
            recording.showPanel(model: self)
            reloadSessions()
        } catch {
            lastError = "Couldn't start recording: \(error)"
        }
    }

    static func label(_ p: Preset) -> String { "\(p.name) · \(p.language?.rawValue.uppercased() ?? "?")" }

    func transcribe(sessionURL: URL, preset: Preset) {
        guard let asr = preset.asr, let provider = provider(asr.providerID), let c = client(for: asr.providerID) else {
            lastError = "The preset's speech-to-text provider is missing."
            return
        }
        let probe = probeCache.result(provider: asr.providerID, model: asr.model, role: .asr, language: preset.language)
        do {
            let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: probe)
            run(sessionURL: sessionURL, runID: Self.sessionName(Date()), snapshot: snapshot, client: c)
        } catch RunSnapshotError.chatShapeNotForMeetings {
            lastError = "This model returns no word timings, so it can't be used for meetings."
        } catch {
            lastError = "\(error)"
        }
    }

    /// ChatGPT #17: wznowienie w aplikacji, także po restarcie — ten sam runID i ta sama
    /// migawka z `input.json`, więc opłacone okna nie idą drugi raz (P5).
    func resume(_ item: SessionItem) {
        guard let runID = item.runID,
              let input = try? JSONFile.load(RunInput?.self, from: RunDirectory(session: item.url, runID: runID).input, default: nil),
              let c = client(for: input.snapshot.providerID) else {
            lastError = "Nothing to resume for this recording."
            return
        }
        run(sessionURL: item.url, runID: runID, snapshot: input.snapshot, client: c)
    }

    private func run(sessionURL: URL, runID: String, snapshot: RunSnapshot, client c: OpenAICompatibleClient) {
        let id = sessionURL.lastPathComponent
        Task {
            do {
                _ = try await TranscriptionRunner(session: sessionURL, runID: runID, snapshot: snapshot, client: c).run { p in
                    Task { @MainActor in
                        if let i = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[i].progress = p.fraction }
                    }
                }
            } catch {
                self.lastError = "Transcription failed: \(error)"
            }
            self.reloadSessions()
        }
    }
```

- [ ] **Krok 3: Menu.** W `MeetNotesApp.swift`, w `CommandMenu("Recording")`, pod przyciskiem nagrywania dopisz:

```swift
                Button("Show Recording Window") { model.recording.showPanel(model: model) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
```

- [ ] **Krok 4: Strona główna.** W `MeetingsView.swift`:
  - trwająca sesja jest w wierszu „Recording" na górze, nie na liście (Hermes 4.5). Zamień:

```swift
        let filtered = model.sessions.filter { s in
            query.isEmpty || s.transcript?.utterances.contains { $0.text.localizedCaseInsensitiveContains(query) } == true
        }
```

na:

```swift
        let filtered = model.sessions.filter { s in
            s.url != model.recording.directory
                && (query.isEmpty || s.transcript?.utterances.contains { $0.text.localizedCaseInsensitiveContains(query) } == true)
        }
```

  - zamień `RecordingRow(elapsed: model.recording.elapsed, preset: model.activePreset?.name ?? "")` na `RecordingRow(elapsed: model.recording.elapsed, preset: model.recording.presetLabel)`;
  - w `SessionRow`, pod `Text(item.duration.map …).foregroundStyle(.secondary)` dopisz:

```swift
                if let bad = item.summary?.tracks.filter({ $0.failure != nil || $0.permissionDenied != nil }), !bad.isEmpty {
                    // ChatGPT #16: brak „Oni" albo „Ja" widoczny na liście, nie tylko w dzienniku.
                    Label("Problem: " + Set(bad.map { $0.id == "system" ? "system audio" : "microphone" }).sorted().joined(separator: ", "),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .help(bad.map { "\($0.id): \($0.failure ?? $0.permissionDenied ?? "")" }.joined(separator: "\n"))
                }
```

  - w `status`, przed `} else if let t = item.transcript {` dopisz:

```swift
        } else if let t = item.transcript, !t.failedChunks.isEmpty {
            Label("Partial — \(t.failedChunks.count) gaps", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        } else if item.transcript == nil && item.runID != nil {
            Label("Interrupted", systemImage: "pause.circle").foregroundStyle(.orange)
```

- [ ] **Krok 5: Widok spotkania — odtwarzanie „Me" i wznowienie.** W `MeetingDetailView.swift`:
  - w `PlaybackState` pod `var player: AVAudioPlayer?` dopisz `var track: String?`;
  - zamień `UtteranceRow(utterance: u) { play(from: u.start) }` na `UtteranceRow(utterance: u) { play(u) }`;
  - zamień całą funkcję `play(from:)` na:

```swift
    /// ChatGPT #8: „Me" nie ma w pliku odsłuchu (to tap systemowy) — gramy tor mikrofonu,
    /// przeliczając czas sesji na czas tej ścieżki.
    private func play(_ u: Utterance) {
        let aecOK = item.summary?.tracks.first { $0.id == "mic_aec" }.map { $0.failure == nil && $0.channels > 0 } ?? false
        let track = u.speaker == .them ? "system" : (aecOK ? "mic_aec" : "mic_raw")
        let offset = item.summary?.tracks.first { $0.id == track }?.offsetSeconds ?? 0
        if playback.track != track {
            playback.player = try? AVAudioPlayer(contentsOf: item.url.appendingPathComponent("\(track).caf"))
            playback.track = track
        }
        playback.player?.currentTime = max(0, u.start - offset)
        playback.player?.play()
    }
```

  - w `ContentUnavailableView`, w `actions:`, pod przyciskiem „Transcribe with…" dopisz `if item.runID != nil { Button("Resume Transcription") { model.resume(item) } }`;
  - w `List`, na początku, dopisz:

```swift
                    if !t.failedChunks.isEmpty {
                        Button("Retry Failed Parts") { model.resume(item) }
                            .help("Sends only the parts that failed; finished parts aren't paid for again")
                    }
```

- [ ] **Krok 6: Setup.** W `SetupView.swift`:
  - klucz `"systemAudioVerified"` występuje w `AppModel` i `SetupView` jako ten sam napis — przepisz go identycznie;
  - zamień `.disabled(state.checking)` na `.disabled(state.checking || model.recording.isRecording)` (Hermes 4.8: bez drugiego tapu w trakcie nagrania);
  - zamień `state.systemAudio = await SystemAudioCheck.run()` na:

```swift
                        let result = await SystemAudioCheck.run()
                        state.systemAudio = result
                        if case .works = result { UserDefaults.standard.set(true, forKey: "systemAudioVerified") }
```

- [ ] **Krok 7: Zbuduj.** `swift build --product MeetNotesApp` — oczekiwane: `Build complete!`. `scripts/test.sh` — `99/99`. `scripts/bundle.sh` — `.build/MeetNotes.app`.

- [ ] **Krok 8: Commit.**

```bash
git add Sources/MeetNotesApp
git commit -m "Aplikacja: preset zamrozony przy starcie, wybor presetu w plywajacym oknie, odtwarzanie Me z mikrofonu, wznowienie" -m "Po recenzjach ChatGPT i Hermesa. Lista pokazuje problemy torow i wyniki czesciowe, setup wraca, dopoki dzwiek systemowy nie przejdzie testu."
```
