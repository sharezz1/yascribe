# Faza 2.0 „Lokalne modele" — plan implementacji

> **Dla wykonawców (Claude Code):** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (rekomendowane) albo `superpowers:executing-plans`. Jedno zadanie = jedna sesja/podagent. Kroki używają pól `- [ ]`. **Start od T0 (spike S0); po T0 jest punkt STOP.** Spiki (T0, T1, T9) to pomiary, nie kod produktu; punkty STOP należą do użytkownika.

**Cel:** MeetNotes dostaje lokalną ścieżkę **obok API**: transkrypcja Parakeet v3 w procesie (2.0a) oraz korekta i podsumowanie lokalnym modelem tekstowym przez Ollamę, llama.cpp albo oMLX (2.0b). Rola po roli wybierasz w presecie: API albo lokalnie.

**Architektura:** (2.0a) nowy moduł `MeetNotesLocalASR` jest **jedynym** miejscem, które importuje FluidAudio; reszta widzi tylko `TranscriptionClient`. Nowy `ProviderKind.fluidAudio`; klient lokalny to `actor` z `load`/`unload`, wołany przez niezmieniony `TranscriptionRunner`. (2.0b) lokalny model tekstowy to zwykły `Provider` na loopbacku (`OpenAICompatibleClient` bez zmian transportu poza limitem czasu i oczyszczaniem „thinking"); dochodzą budżet kontekstu i map-reduce dla podsumowania. Wbudowany model pobierany przez aplikację jest poza fazą (→ 2.1+).

**Stos:** Swift 6.4 (tryb 6), tylko Command Line Tools, `swift-testing`, SwiftUI; **jedyna nowa zależność zewnętrzna: FluidAudio (Apache-2.0)** — warunkowo, po „go" z T0.

**Spec:** `docs/superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md`; recenzja: `docs/superpowers/reports/F20-recenzja-design.md`. Plan argumentuje ze speca; wykonawca czyta oba.

**Gałąź:** przed T0: `git switch -c faza20` od bieżącego HEAD (`faza15`, zawiera markę Yascribe; jeśli użytkownik woli od `master` — zapytać). Spec, ten plan i recenzję zacommitować pierwsze, jawnymi ścieżkami.

## Poza zakresem

Granice (spec §2, decyzje 1–4): wbudowany model tekstowy i `llama-server` zarządzany przez aplikację (2.1+); diaryzacja, słownik/word boosting, transkrypt na żywo, AEC offline, Cohere lokalnie, dyktowanie; embeddingi lokalne; zmiany formatu na dysku poza **opcjonalnymi** polami; ciche przełączenie na API przy awarii lokalnej (anty-cel — nigdy).

## Wspólne ograniczenia

Obowiązują w każdym zadaniu (z CLAUDE.md i speca, dosłownie):

- **Swift 6.4, tryb 6, tylko Command Line Tools, `swift-testing`.** SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`; stan lokalny przez `ObservableObject` + `@StateObject`; `@Observable` działa.
- **Testy wyłącznie `scripts/test.sh`**, nigdy goły `swift test`. Kod 3 = usterka pluginu makr (`rm -rf .build`), kod 4 = rozjazd liczby testów (wynik NIEWAŻNY — STOP). Każdy `@Test` zaczyna linię. Katalogi tymczasowe: `mn-<UUID>`.
- **Nowe pola w zapisywanych typach (`Provider`, `RunSnapshot`, `RunInput`…) tylko opcjonalne** (lekcja E6).
- **Nigdy `git add -A` ani `git add .`** — jawne ścieżki. **Mutacja każdej bramki:** najpierw `git add` ścieżek zadania, potem mutacja → test ma paść → `git checkout -- <plik>` → dopiero commit.
- **Klucze API wpisuje tylko użytkownik.** Literały testowe `test-fake-…`. Nie zmieniamy Ustawień systemowych, TCC ani pęku kluczy.
- **Nic z lokalnej roli nie wychodzi do chmury bez decyzji użytkownika; brak cichego fallbacku do API.** Model ASR pobiera się **wyłącznie po akcji użytkownika**, nigdy w tle.
- **„Lokalny" = loopback** (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) **albo** `ProviderKind.fluidAudio`. Adres LAN/tunel/host zdalny nie dostaje znaczników „On this Mac" ani „Fully local".
- **Interfejs po angielsku**, dokumenty w repo po polsku.
- **FluidAudio występuje wyłącznie w module `MeetNotesLocalASR`** (kryterium 3.9 z `docs/plan.md` §3).
- **Wartości liczbowe (limity czasu, budżety kontekstu, modele rekomendowane) pochodzą z raportów S0/S2**; w planie są tylko szkice oznaczone *szkic*.

## Review Focus (czego spec nie mówi, a co użytkownik napotka)

Najpierw najbardziej prawdopodobne; każda linia ma test w zadaniu, które posiada kod:

1. **Preset z lokalnym ASR, a modelu nie ma (albo jest uszkodzony) w chwili startu przebiegu.** Oczekiwane: przebieg nie startuje, komunikat z przyciskiem pobrania, **nic nie idzie do API**. `missingModelRefusesRunAndNeverFallsBack` (T6), `tamperedModelFileIsRefusedWithReason` (T3).
2. **Serwer lokalny wyłączony albo model niezaładowany przy „Generate notes" / korekcie.** Oczekiwane: szybki, czytelny błąd z nazwą serwera i podpowiedzią, nie surowe `URLError` i nie 120 s wiszenia. `unreachableLocalServerNamesTheServer` (T11).
3. **Model „thinking" (Qwen, DeepSeek) zwraca blok rozumowania** — także nieskończony (ucięty limitem tokenów). Oczekiwane: do notatki i do parsowania numerowanych linii trafia tylko odpowiedź; sam ucięty blok = pusta odpowiedź = błąd, nie wyciek. `unterminatedThinkBlockIsAnEmptyReply` (T10).
4. **Transkrypt dłuższy niż budżet kontekstu.** Oczekiwane: map-reduce zachowuje mówców, czasy, nazwy i liczby; padnięta jedna część = notatka nie powstaje, z numerem części (bez „częściowej notatki"); wejście reduce nigdy nie przekracza budżetu (Ollama obcina po cichu). `reduceInputKeepsSpeakerAndClock`, `reduceInputNeverExceedsTheBudgetInTheWorstCase`, `oneFailedPartFailsTheSummary` (T13).
5. **Wznowienie przebiegu po zmianie modelu we wspólnym magazynie FluidAudio przez inną aplikację.** Oczekiwane: odmowa wznowienia z komunikatem „Start a new transcription”, nie mieszanie okien z dwóch modeli. Uwaga: `AppModel.resume` podaje do runnera **zapisany** snapshot, więc `RunError.inputMismatch` tu nie zadziała — bramka jest osobna: `resumeWithChangedModelFingerprintIsRefused` (T6, `RunGate.checkResume`).

---

## Przydział modeli i effort

| Zadanie | Model | Effort | Dlaczego |
|---|---|---|---|
| T0 spike S0 (kod sondy) | Sonnet | **xhigh** | nieznane API FluidAudio w naszym toolchainie, nic nie wolno zgadywać |
| T0 interpretacja raportu (STOP) | **Opus** | **xhigh** | go/no-go: zależność zewnętrzna, bundle, test.sh |
| T1 spike S1 (pomiar ASR) | Sonnet | high | pomiar; wymaga decyzji §13 użytkownika |
| T2 typ `.fluidAudio`, lokalność, bramka klucza | Sonnet | high | jeden predykat; ElevenLabs/Ollama bez regresji |
| T3 `MeetNotesLocalASR`: magazyn modelu | Sonnet | **xhigh** | integralność, szew testowy, pobieranie |
| T4 klient lokalny + migawka | Sonnet | **xhigh** | actor, dekodowanie WAV, odcisk modelu; przegląd Opusa po zadaniu |
| T5 sonda i `loadModels`/wiersz dostawcy | Sonnet | medium | trzy miejsca, każde z testem |
| T6 integracja w `AppModel` | Sonnet | high | cykl życia, odmowa bez modelu |
| T7 UI karty modelu i wiersza | Sonnet | medium | wzór: karty modeli Meetily, `SettingsView` |
| T8 odbiór 2.0a (STOP) | **Opus** xhigh / Haiku (dokumenty) | xhigh | sieć off, kryteria z §13 |
| T9 spike S2 (pomiar serwerów) | Sonnet | high | Ollama do zainstalowania przez użytkownika; STOP |
| T10 `chat(timeout:)` + „thinking" | Sonnet | high | transport i parsowanie; przegląd Opusa |
| T11 dostawcy llama.cpp/oMLX, lokalność w UI, błędy serwera | Sonnet | medium | mechanika wg wzoru Ollamy |
| T12 budżet kontekstu | Sonnet | **xhigh** | dwa mechanizmy w jednym, wykrywanie tylko obniża |
| T13 map-reduce | Sonnet | **xhigh** | kontrakt promptu notatki; przegląd Opusa |
| T14 odbiór 2.0b, dokumenty, przegląd całości (STOP) | **Opus** xhigh / Haiku | xhigh | przegląd przed scaleniem |
| Po każdym zadaniu: `scripts/test.sh`, liczba testów, mutacje, odhaczanie `- [ ]` | Haiku | low | mechanika |

---

## FAZA 2.0a — lokalny ASR

### Task 0: Spike S0 — FluidAudio w naszym toolchainie (throwaway)

**Files:**
- Create (poza repo, w scratchpadzie sesji): osobny pakiet `f20-s0/` z zależnością FluidAudio; **nie dotykaj `Package.swift` repo**.
- Create: `docs/superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md` (raport; bez treści nagrań użytkownika).

**Interfaces:**
- Produces: raport z odpowiedziami na pytania (a)–(e) i rekomendacją go/no-go; **nazwy API FluidAudio, których używa T3/T4** (ładowanie modelu, transkrypcja `[Float]` 16 kHz, czasy tokenów, `cleanup`, lokalizacja magazynu); **jeden pin**: wersja FluidAudio (tag/commit), wariant modelu i precyzja enkodera (`version`, `encoderPrecision` podawane do `downloadAndLoad`) oraz wersja `text-processing-rs` (`NemoTextProcessing.xcframework` ma własne wydania); `Package.resolved` z tego pinu trafia do commitu T3.

- [ ] **Step 1:** W osobnym pakiecie (Swift 6.4, tylko CLT) dodaj FluidAudio, przypięty do konkretnej wersji; `swift build` — zapisz wynik i ostrzeżenia współbieżności. Kryterium (a).
- [ ] **Step 2:** Wywołaj ASR na pliku testowym z `.devdata/sessions` (wyłącznie lokalnie; w raporcie tylko długości i metryki): próbki `[Float]` 16 kHz → tekst + czasy słów (łączenie tokenów w słowa). Kryterium (d). Zmierz: czas pierwszego uruchomienia po świeżym pobraniu (kompilacja ANE), czas kolejnych, szczytowa pamięć, RTF; koszt dekodowania WAV 16-bit w `[Float]` (kryterium (e)).
- [ ] **Step 3:** Zbadaj magazyn: czy pobieranie można skierować do podanego katalogu (potrzebne do szwu testowego T3), czy FluidAudio zwraca natychmiast przy istniejącym modelu, **lista plików i rozmiary ze ŚWIEŻEGO pobrania tym samym pinem** do pustego katalogu testowego (to jest wejście do manifestu T3 — nie z istniejącego, cudzego magazynu: inna aplikacja mogła pobrać inny wariant/precyzję), czy `cleanup()` zwalnia pamięć.
- [ ] **Step 4:** Wpływ na repo — **na kopii** (`cp -R` do scratchpadu, nie w repo): dodaj zależność do `Package.swift` kopii i uruchom (b) `scripts/test.sh` — przechodzi, liczba testów zgodna, bez kodu 3/4; (c) `scripts/bundle.sh` składa `.app`, `otool -L` nie pokazuje zależności z `.build`, aplikacja się uruchamia (`binaryTarget` `NemoTextProcessing.xcframework`: czy trafia do paczki?).
- [ ] **Step 5:** Napisz raport z tabelą (a)–(e): przeszło/nie, dowód (komenda i wynik). **No-go** = wypisz opcje: vendoring, bezpośrednie CoreML, sidecar w rodzaju `parakeet-mlx-server`, rezygnacja z 2.0a.
- [ ] **Step 6: STOP** — Opus czyta raport i przedstawia użytkownikowi rekomendację. Bez „go" T2–T8 się nie zaczynają (2.0b, T9–T14, nie zależy od S0, ale kolejność speca to S0 → 2.0a → S2 → 2.0b).
- [ ] **Step 7:** Commit raportu: `git add docs/superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md && git commit -m "F20 T0: S0 FluidAudio — raport"`.

---

### Task 1: Spike S1 — jakość Parakeet vs `mai-transcribe-2`

**Files:** Create: `docs/superpowers/spikes/2026-10-20-f20-s1-jakosc-asr.md`

**Warunek wstępny:** użytkownik rozstrzygnął spec §13 (materiał, referencja, które kryteria `docs/plan.md` §3 obowiązują). **Bez tego T1 się nie zaczyna; kod 2.0a (T2–T7) może iść bez T1** — S1 bramkuje tylko raport odbioru T8 i decyzję z pomiaru „T11” z fazy 1.5 (Auto/para PL+EN), nie kod.

**Interfaces:** Consumes: adapter z S0 (kod spike'a). Produces: raport z liczbami.

- [ ] **Step 1:** Zapisz w raporcie, co wskazał użytkownik w §13 (korpus: które sesje, ile minut; referencja: ręczna czy „zgodność"). Referencję dla kryterium 3.3 (wynik FluidVoice, 26 min: `~/Downloads/fluidvoice - bez AI parakeet.txt`, audio w `GCX/meeting notes/2026-09-23/WFM/`) skopiuj do `.devdata/` (nie do repo; `~/Downloads` bywa czyszczony) i podaj tam ścieżkę w raporcie. Metryka nazywa się **WER** tylko przy tekście referencyjnym; inaczej **zgodność z `mai-transcribe-2`**.
- [ ] **Step 2:** Zmierz na tym samym materiale: PL (jawny język), para PL+EN, odcinki ciszy i sam mikrofon bez mówienia (halucynacje), RTF. Wyniki obok `mai-transcribe-2` (z istniejących transkryptów lub nowego przebiegu).
- [ ] **Step 3:** Zmierz kryteria `docs/plan.md` §3, które użytkownik uznał za obowiązujące (propozycja ze speca §13: 3.1, 3.2, 3.3–3.4, 3.7, 3.8, 3.9).
- [ ] **Step 4:** Raport bez progu go/no-go (decyzja użytkownika, spec §11.7). Commit: `git add docs/superpowers/spikes/2026-10-20-f20-s1-jakosc-asr.md && git commit -m "F20 T1: S1 — jakość lokalnego ASR"`.

---

### Task 2: `ProviderKind.fluidAudio`, lokalność i jedna bramka klucza

**Files:**
- Modify: `Sources/MeetNotesProviders/Provider.swift`, `Sources/MeetNotesProviders/ElevenLabsClient.swift` (rozszerzenie `Provider.transcriptionClient`/`verify` — jeden `switch`), `Sources/MeetNotesApp/AppModel.swift:311` (`providerWithKey`)
- Test: `Tests/MeetNotesProvidersTests/ProviderLocalityTests.swift` (nowy)

**Interfaces:**
- Produces: `ProviderKind.fluidAudio`; `Provider.isLocal: Bool` (`.fluidAudio` → `true`; `.openAICompatible` → host w `{localhost, 127.0.0.1, ::1}` lub z końcówką `.localhost`; `.elevenLabs` → `false`); `Provider.requiresKey: Bool { !isLocal }`; `Provider.fluidAudioBaseURL: URL` = `local://fluidaudio`; `public protocol ReleasableClient: Sendable { func release() async }` (T4/T6); `UnlinkedLocalClient: TranscriptionClient` w `MeetNotesProviders`, który **zawsze rzuca** `ProviderError.badResponse("On-device transcription isn't linked in this build.")` — wymagany, bo `MeetNotesProviders` nie może zależeć od `MeetNotesLocalASR`; aplikacja podstawia prawdziwego klienta (T6).

- [ ] **Step 1: Napisz testy** w `ProviderLocalityTests.swift`: `loopbackHostsAreLocal` (`http://localhost:11434/v1`, `http://127.0.0.1:8080/v1`, `http://[::1]:8000/v1`, `http://llm.localhost/v1` → `isLocal == true`), `lanTunnelAndRemoteHostsAreNotLocal` (`http://192.168.1.5:11434/v1`, `http://my-mac.local:8000/v1`, `https://openrouter.ai/api/v1` → `false`), `fluidAudioIsLocalWithoutAnAddress` (`Provider(name:baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio).isLocal == true`), `elevenLabsOnLoopbackIsStillNotLocal`, `oldProvidersJSONWithoutKindStillLoads` (dekodowanie JSON bez pola `kind` → `api == .openAICompatible`).
- [ ] **Step 2:** `scripts/test.sh --filter ProviderLocalityTests` → FAIL (symbole nie istnieją).
- [ ] **Step 3:** Zaimplementuj `ProviderKind.fluidAudio`, `isLocal`, `requiresKey`, `ReleasableClient`, `UnlinkedLocalClient`; w `Provider.transcriptionClient` i `Provider.verify` dodaj gałąź `.fluidAudio` (`verify` zwraca `.failed("Checked inside the app.")`, bo prawdziwy test robi `AppModel`, T6).
- [ ] **Step 4:** W `AppModel.providerWithKey` zamień twardą listę hostów na `guard key != nil || !p.requiresKey` (jedyny predykat). Test w `ProviderLocalityTests` nie sięga do `AppModel`, więc dodaj `keylessGateAcceptsOnlyLocalProviders` na czystej funkcji `Provider.requiresKey` dla czterech przypadków (Ollama, OpenRouter, ElevenLabs, fluidAudio).
- [ ] **Step 5:** `scripts/test.sh` — całość zielona, liczba testów zgodna.
- [ ] **Step 6: Mutacja:** `git add` ścieżek zadania; w `isLocal` usuń gałąź `.fluidAudio` → `fluidAudioIsLocalWithoutAnAddress` ma paść; `git checkout -- Sources/MeetNotesProviders/Provider.swift`.
- [ ] **Step 7:** `git add Sources/MeetNotesProviders/Provider.swift Sources/MeetNotesProviders/ElevenLabsClient.swift Sources/MeetNotesApp/AppModel.swift Tests/MeetNotesProvidersTests/ProviderLocalityTests.swift && git commit -m "F20 T2: ProviderKind.fluidAudio, isLocal, jedna bramka klucza"`.

---

### Task 3: `MeetNotesLocalASR` — magazyn modelu (stan, pobranie, integralność, szew testowy)

**Files:**
- Modify: `Package.swift` (nowy target `MeetNotesLocalASR` z zależnością FluidAudio **przypiętą pinem z raportu S0**; `testTarget` `MeetNotesLocalASRTests`), `Package.resolved` (repo go pinuje celowo — `.gitignore`; **musi wejść do commitu**)
- Create: `Sources/MeetNotesLocalASR/ModelStore.swift`, `Sources/MeetNotesLocalASR/ModelManifest.swift`
- Test: `Tests/MeetNotesLocalASRTests/ModelStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct ModelManifest: Codable, Equatable, Sendable { public var model: String; public var files: [String: Int64]; public var totalBytes: Int64 { get } }` — nazwa pliku względem katalogu modelu → rozmiar; stała `ModelManifest.parakeetV3` z listy plików **świeżego pobrania tym samym pinem** (raport S0, nie cudzy magazyn).
  - `public enum ModelStatus: Equatable, Sendable { case missing; case ready; case invalid(reason: String); case unknownVariant(reason: String) }` — `invalid`: oczekiwane pliki są, ale brakuje któregoś albo rozmiar się nie zgadza (komunikat z nazwą pliku); `unknownVariant`: zestaw nazw plików inny niż w manifeście (inny wariant/precyzja pobrana przez inną aplikację) — **nie** „invalid”, bez pętli „Download again”.
  - `public struct ModelStore: Sendable { public init(directory: URL = ModelStore.defaultDirectory, download: @escaping @Sendable (URL, @Sendable (Double?) -> Void) async throws -> Void = ModelStore.fluidAudioDownload); public static var defaultDirectory: URL { get }; public static func resolveDirectory(env: [String: String]) -> URL; public func status() -> ModelStatus; public func download(progress: @escaping @Sendable (Double?) -> Void) async throws; public func remove() throws; public var modelDirectory: URL { get }; public func fingerprint() -> String? }`.
    - `defaultDirectory` = `resolveDirectory(env: ProcessInfo.processInfo.environment)`; **tylko w buildzie DEBUG** zmienna `MEETNOTES_MODEL_STORE` wskazuje inny katalog (odbiór T8 na kopii magazynu, bez dotykania wspólnego); w release ignorowana.
    - `fingerprint()` = SHA-256 z listy (nazwa, rozmiar) i `config.json`; `nil`, gdy status ≠ `ready`.
    - Stan „pobieranie w toku” **nie** należy do `ModelStore` (to `struct`): trzyma go `LocalASRSupport` (T6).

- [ ] **Step 1: Napisz testy** (katalog `mn-<UUID>`, bez FluidAudio i sieci; pobieranie przez wstrzyknięty `download`): `emptyDirectoryIsMissing`; `completeModelIsReady`; `tamperedModelFileIsRefusedWithReason` (plik o złym rozmiarze → `.invalid` z jego nazwą); `missingFileIsInvalid`; `differentVariantFileNamesAreUnknownVariantNotInvalid`; `fingerprintIsStableAndChangesWithAFile`; `removeDeletesOnlyTheModelDirectoryNotItsSiblings` (siostrzany `parakeet-tdt-0.6b-v2-coreml` zostaje); `downloadIsNoOpWhenAlreadyReady` (wstrzyknięty `download` nie jest wołany); `downloadValidatesTheManifestAfterwards` (atrapa zapisuje zły plik → rzuca błąd z powodem); `envOverrideChangesTheDirectoryOnlyInDebug` (czysta `resolveDirectory(env:)`).
- [ ] **Step 2:** `scripts/test.sh --filter ModelStoreTests` → FAIL.
- [ ] **Step 3:** Zaimplementuj. `fluidAudioDownload` opakowuje pobieranie FluidAudio z pinem (wersja + precyzja) i raportuje postęp. Uszkodzone pobranie = `invalid` + propozycja ponowienia; nigdy samonaprawa cudzego katalogu.
- [ ] **Step 4:** `scripts/test.sh` — zielone; `grep -rn "import FluidAudio" Sources | grep -v MeetNotesLocalASR` jest puste (kryterium 3.9).
- [ ] **Step 5: Mutacja:** w `status()` pomiń porównanie rozmiarów → `tamperedModelFileIsRefusedWithReason` ma paść; `git checkout -- Sources/MeetNotesLocalASR/ModelStore.swift`.
- [ ] **Step 6:** Commit: `git add Package.swift Package.resolved Sources/MeetNotesLocalASR Tests/MeetNotesLocalASRTests && git commit -m "F20 T3: magazyn modelu lokalnego ASR (manifest, odcisk, szew testowy)"`.

---

### Task 4: Klient lokalny + odcisk modelu w migawce przebiegu

**Files:**
- Create: `Sources/MeetNotesLocalASR/LocalASRClient.swift`, `Sources/MeetNotesLocalASR/WAVDecoder.swift`, `Sources/MeetNotesLocalASR/FluidAudioEngine.swift`
- Modify: `Sources/MeetNotesTranscription/Transcript.swift` (`RunSnapshot`)
- Test: `Tests/MeetNotesLocalASRTests/LocalASRClientTests.swift`, `Tests/MeetNotesLocalASRTests/WAVDecoderTests.swift`, `Tests/MeetNotesTranscriptionTests/RunnerTests.swift` (dopisać)

**Interfaces:**
- Consumes: `TranscriptionClient`, `TranscriptionResult`, `TranscribedWord`, `ReleasableClient` (T2), `ModelStore`, `ModelStatus` (T3).
- Produces:
  - `public protocol LocalASREngine: Sendable { func load() async throws; func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]); func unload() async }` — szew do atrapy; `FluidAudioEngine: LocalASREngine` to jedyny plik z `import FluidAudio` poza `ModelStore`.
  - `public enum LocalASRPhase: Equatable, Sendable { case preparing, ready }`.
  - `public actor LocalASRClient: TranscriptionClient, ReleasableClient { public nonisolated let provider: Provider; public init(provider: Provider, engine: any LocalASREngine, store: ModelStore, onPhase: @escaping @Sendable (LocalASRPhase) -> Void = { _ in }); public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult; public func release() async }` — leniwy `load()` przy pierwszym żądaniu, z `onPhase(.preparing)` przed i `onPhase(.ready)` po (kompilacja ANE bywa wielominutowa — spec §4.2); `release()` woła `engine.unload()`; ignoruje `language` (wskazówka FluidAudio jest tylko skryptowa); `shape` ≠ `.audioTranscriptions` → `ProviderError.badResponse`.
  - `public enum WAVDecoder { public static func samples(_ wav: Data) throws -> [Float] }` — WAV 16 kHz mono Int16 (jak `WAVEncoder`, także klipy sondy); inny format → błąd.
  - `RunSnapshot.modelFingerprint: String?` (opcjonalne; `init(...)` dostaje `modelFingerprint: String? = nil`).

- [ ] **Step 1: Napisz testy:** `WAVDecoderTests`: `roundTripsWAVEncoderOutput` (kodowanie `WAVEncoder.wav(pcm, rate: 16000)` → `samples` zgodne do 1/32767), `rejectsStereoAndWrongRate`; `LocalASRClientTests` na `FakeEngine`: `returnsTextAndWordTimings`, `loadsLazilyOnceAcrossRequests`, `reportsPreparingAroundTheFirstLoadOnly`, `releaseUnloadsAndNextRequestLoadsAgain`, `ignoresTheLanguageParameter`, `chatShapeIsRejected`, `refusesToTranscribeWhenStoreIsNotReady` (rzuca błąd z powodem, **nie** woła silnika); `RunnerTests`: `snapshotsWithDifferentFingerprintsAreNotEqual`, `oldInputJSONWithoutFingerprintStillLoads`.
- [ ] **Step 2:** `scripts/test.sh --filter "LocalASRClientTests|WAVDecoderTests|RunnerTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj `WAVDecoder`, `LocalASRClient`, `FluidAudioEngine` (mapowanie wyniku FluidAudio na słowa z czasami wg raportu S0), `RunSnapshot.modelFingerprint`. **Uwaga:** bramka wznowienia po zmianie modelu to T6 — `AppModel.resume` podaje do runnera zapisany snapshot, więc `RunError.inputMismatch` dla zmiany odcisku nie wystąpi w aplikacji.
- [ ] **Step 4:** `scripts/test.sh` — zielone.
- [ ] **Step 5: Mutacja:** (a) usuń sprawdzenie `store.status()` w `LocalASRClient` → `refusesToTranscribeWhenStoreIsNotReady` ma paść; (b) w `RunSnapshot.init` wstaw `self.modelFingerprint = nil` → `snapshotsWithDifferentFingerprintsAreNotEqual` ma paść (mutacja łamie równość w pamięci, nie samo `Codable`). Po każdej `git checkout -- <plik>`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesLocalASR Sources/MeetNotesTranscription/Transcript.swift Tests/MeetNotesLocalASRTests Tests/MeetNotesTranscriptionTests/RunnerTests.swift && git commit -m "F20 T4: klient lokalnego ASR i odcisk modelu w migawce"`. **Przegląd Opusa po zadaniu.**

---

### Task 5: Sonda `.filtered`, lista modeli i wiersz dostawcy

**Files:**
- Modify: `Sources/MeetNotesProviders/Probe.swift` (gałąź w `ProbeRunner.probe`), `Sources/MeetNotesProviders/ProviderSetup.swift` (`ProviderPreset.onThisMac`, `ready`, `matching`, `rows`), `Sources/MeetNotesApp/AppModel.swift` (`loadModels`)
- Test: `Tests/MeetNotesProvidersTests/ProbeTests.swift`, `Tests/MeetNotesProvidersTests/ProviderSetupTests.swift` (dopisać)

**Interfaces:**
- Produces: `ProviderPreset.onThisMac` (id `"on-this-mac"`, nazwa „On this Mac · Parakeet", `needsKey: false`, `kind: .fluidAudio`, `baseURL: Provider.fluidAudioBaseURL.absoluteString`, `role: "Speech-to-text on this Mac · no network"`); `ProviderPreset.matching(_:)` rozpoznaje `.fluidAudio` po `kind`; `ProviderPreset.ready == [openRouter, elevenLabs, ollama, onThisMac]` (T11 dopisze llama.cpp i oMLX); `LocalASRModels.parakeetV3 = "parakeet-tdt-0.6b-v3"` w `MeetNotesProviders` (stała, żeby `loadModels` nie importował LocalASR).

- [ ] **Step 1: Napisz testy:** `fluidAudioProbeReportsFilteredLanguageHandling` (atrapa `TranscriptionClient` z `provider.kind == .fluidAudio`, klip PL → `works == true`, `languageHandling == .filtered`, **`classifyLanguage` nie jest wołane** — atrapa liczy wywołania `transcribe(language: nil)` i oczekuje dokładnie jednego), `fluidAudioProbeForCorrectionRoleSaysSpeechToTextOnly` (`textClient == nil` → `failure == "<name> does only speech-to-text."`, zachowanie pożądane), `fluidAudioProviderIsMatchedByKindNotAddress`, `savedFluidAudioProviderIsNotShownAsCustomRow` (`ProviderListRow.rows` zwraca jeden `.preset(onThisMac, provider)` i brak `.custom`).
- [ ] **Step 2:** `scripts/test.sh --filter "ProbeTests|ProviderSetupTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj gałąź: w `ProbeRunner.probe` dla `.asr`, gdy `client.provider.kind == .fluidAudio` i `shape == .audioTranscriptions`, ustaw `r.languageHandling = .filtered` bez klasyfikacji; dopisz preset, `matching`, `ready`; w `AppModel.loadModels` gałąź dla `.fluidAudio`: `modelLists[k] = role == .asr ? [ModelInfo(id: LocalASRModels.parakeetV3, …)] : []`, bez sieci.
- [ ] **Step 4:** `scripts/test.sh` — zielone.
- [ ] **Step 5: Mutacja:** usuń gałąź `.fluidAudio` w `probe` → `fluidAudioProbeReportsFilteredLanguageHandling` ma paść; `git checkout -- Sources/MeetNotesProviders/Probe.swift`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesProviders/Probe.swift Sources/MeetNotesProviders/ProviderSetup.swift Sources/MeetNotesApp/AppModel.swift Tests/MeetNotesProvidersTests/ProbeTests.swift Tests/MeetNotesProvidersTests/ProviderSetupTests.swift && git commit -m "F20 T5: sonda .filtered, lista modeli i wiersz „On this Mac”"`.

---

### Task 6: Integracja w `AppModel` — klient, odmowa bez modelu, wznowienie, zwolnienie, fazy

**Files:**
- Modify: `Package.swift` (`MeetNotesApp` zależy od `MeetNotesLocalASR`; `Package.resolved`, jeśli się zmienił), `Sources/MeetNotesApp/AppModel.swift` (`transcriptionClient(for:)`, `transcribe(sessionURL:preset:)`, `resume`, `run(...)`, `verifyProvider`)
- Create: `Sources/MeetNotesApp/LocalASRSupport.swift` (`ObservableObject`: `phase` pobierania/przygotowania i `store`)
- Test: aplikacja nie ma testTargetu (pozycja z ROADMAP), więc **logika żyje w `MeetNotesLocalASR`** (`RunGate`, `LocalASRFactory`) i tam jest testowana; `AppModel` tylko ją woła.

**Interfaces:**
- Consumes: `LocalASRClient`, `ModelStore`, `ModelStatus`, `ReleasableClient`, `RunSnapshot.modelFingerprint`, `LocalASRPhase`.
- Produces (w `MeetNotesLocalASR`):
  - `public struct RunGateRefusal: Error, Equatable, Sendable { public var message: String; public var canDownload: Bool }`
  - `public enum RunGate { public static func check(status: ModelStatus) -> RunGateRefusal?; public static func checkResume(snapshot: RunSnapshot, provider: Provider, currentFingerprint: String?) -> RunGateRefusal?; public static func fingerprintForSnapshot(provider: Provider, store: ModelStore) -> String? }` (`nil` = wolno / brak odcisku). Komunikaty po angielsku: `.missing` → „The on-device speech model isn't downloaded yet. Download it in Settings.” (`canDownload: true`); `.invalid(reason)` → „The on-device speech model failed its check: \(reason). Download it again.” (`true`); `.unknownVariant(reason)` → „Another app stored a different variant of this model: \(reason).” (`false`); `checkResume` → „The on-device model changed since this run. Start a new transcription.” — odmowa **tylko** gdy `provider.api == .fluidAudio` i zapisany odcisk (nie `nil`) różni się od bieżącego; przebiegi API ignorują odcisk; `fingerprintForSnapshot` zwraca odcisk tylko dla `.fluidAudio`.
  - `LocalASRFactory.client(provider:store:engine:onPhase:) -> Result<any TranscriptionClient, RunGateRefusal>` — bez ścieżki do API: przy odmowie nie powstaje żaden klient.

- [ ] **Step 1: Napisz testy** w `Tests/MeetNotesLocalASRTests/RunGateTests.swift`: `missingModelRefusesRunAndNeverFallsBack` (status `.missing` → `RunGateRefusal(canDownload: true)`, a `LocalASRFactory.client` zwraca `.failure`), `readyAllowsRun`, `invalidMissingAndUnknownVariantHaveDifferentMessages`, `resumeWithChangedModelFingerprintIsRefused`, `resumeWithSameFingerprintIsAllowed`, `resumeOfApiRunIgnoresFingerprint`, `apiProviderGetsNoFingerprintInSnapshot`.
- [ ] **Step 2:** `scripts/test.sh --filter RunGateTests` → FAIL.
- [ ] **Step 3:** Zaimplementuj `RunGate`, `LocalASRFactory`, `LocalASRSupport`. W `AppModel.transcriptionClient(for:)` dla `.fluidAudio`: `RunGate.check(store.status())` → przy odmowie `lastError`, `nil` (żadnego fallbacku); inaczej klient z `onPhase` podpiętym do `LocalASRSupport.phase` (`.preparing`). W `transcribe(sessionURL:preset:)` przekaż `modelFingerprint: RunGate.fingerprintForSnapshot(provider:store:)`. W `resume` **przed** `run(...)` wywołaj `RunGate.checkResume(...)` i przy odmowie ustaw `lastError`. W `run(...)` dodaj w `defer` zadania `await (client as? ReleasableClient)?.release()`. W `verifyProvider` dla `.fluidAudio`: `.verified(models: 1)` gdy `status == .ready`, inaczej `.failed(<komunikat RunGate>)`.
- [ ] **Step 4:** `scripts/test.sh` — zielone; `swift build` aplikacji bez nowych ostrzeżeń współbieżności (poza szumem linkera).
- [ ] **Step 5: Mutacja:** (a) w `RunGate.check` zwróć `nil` dla `.missing` → `missingModelRefusesRunAndNeverFallsBack` ma paść; (b) w `checkResume` zwróć `nil` zawsze → `resumeWithChangedModelFingerprintIsRefused` ma paść. Po każdej `git checkout -- Sources/MeetNotesLocalASR/RunGate.swift`.
- [ ] **Step 6:** Commit: `git add Package.swift Package.resolved Sources/MeetNotesApp/AppModel.swift Sources/MeetNotesApp/LocalASRSupport.swift Sources/MeetNotesLocalASR Tests/MeetNotesLocalASRTests && git commit -m "F20 T6: integracja lokalnego ASR w AppModel (odmowa, wznowienie, zwolnienie)"`.

---

### Task 7: UI — karta modelu i wiersz „On this Mac" (Settings, preset)

**Files:**
- Modify: `Sources/MeetNotesApp/SettingsView.swift`, `Sources/MeetNotesApp/PresetsView.swift`, `Sources/MeetNotesApp/ProviderLogos.swift` (ikona), `Sources/MeetNotesApp/Snapshots.swift` (sceny: karta Ready / Downloading / Missing / Invalid)
- Test: brak testTarget aplikacji; logika stanu karty w `MeetNotesLocalASR` (`ModelCardState` z pary `ModelStatus` + `LocalASRSupport.Phase`) z testem `cardStateMapsEveryStatus`.

**Interfaces:** Consumes: `ModelStore`, `ModelStatus`, `LocalASRSupport` (T6). Wzór wizualny: karty modeli Meetily (`docs/design/inspiracje/meetily-modele-lokalne.png`), język wizualny B (`docs/design/macos.md` §11).

- [ ] **Step 1:** `ModelCardState` + test `cardStateMapsEveryStatus` (każda para status/faza → tytuł, opis, przycisk główny: `missing` „Download (<rozmiar>)", faza `downloading` pasek, faza `preparing` „Preparing model… this can take a few minutes the first time" (spec §4.2), `ready` „Ready" + „Remove…", `invalid` „Download again", `unknownVariant` komunikat bez przycisku pobrania). **Rozmiar z `ModelManifest.totalBytes`**, nie na sztywno.
- [ ] **Step 2:** Karta w Settings → Providers: nazwa „Parakeet TDT v3", rozmiar, „Multilingual", stan; „Remove…" pyta z nazwą lokalizacji (magazyn **wspólny z innymi aplikacjami**). Pobieranie tylko po kliknięciu.
- [ ] **Step 3:** Wiersz „On this Mac · Parakeet" z przyciskiem „Enable" (tworzy `Provider(kind: .fluidAudio)` bez klucza i adresu); w edytorze presetu przy roli ASR znacznik „On this Mac"; ostrzeżenie „Model not downloaded" z przyciskiem Download. Interfejs po angielsku.
- [ ] **Step 4:** Sceny w `Snapshots.swift` dla czterech stanów; `scripts/run.sh` i obejrzenie na żywo (screenshot do raportu T8).
- [ ] **Step 5:** `scripts/test.sh` zielone; commit: `git add Sources/MeetNotesApp Sources/MeetNotesLocalASR Tests/MeetNotesLocalASRTests && git commit -m "F20 T7: karta modelu i wiersz „On this Mac”"`.

---

### Task 8: Odbiór 2.0a na sprzęcie (STOP)

**Files:** Create: `docs/superpowers/reports/F20-2.0a-odbior.md`

- [ ] **Step 1:** **Sieć wyłączona** (Wi-Fi off — robi użytkownik, nie my): nagranie PL → transkrypcja lokalnym presetem → poprawny transkrypt, czasy słów, postęp monotoniczny. Zrzut ekranu karty modelu.
- [ ] **Step 2:** Ścieżki awarii: (a) preset lokalny, model usunięty za zgodą użytkownika **albo** katalog magazynu wskazany testowo → odmowa z przyciskiem pobrania, brak ruchu do API (obserwacja sieci); (b) podmieniony plik w **kopii** magazynu (build deweloperski z `scripts/run.sh` i `MEETNOTES_MODEL_STORE` wskazującym kopię; wspólnego magazynu nie ruszamy — używają go inne aplikacje) → odmowa z przyczyną (kryterium 3.8); (c) wznowienie przerwanego przebiegu tym samym presetem; (d) wznowienie po zmianie pliku w kopii magazynu → odmowa „Start a new transcription"; (e) lokalny ASR + ścieżka awarii w trakcie przebiegu: okna zostają, luki jawne, brak ruchu do API.
- [ ] **Step 3:** Kryteria `docs/plan.md` §3 uznane przez użytkownika w §13 — wynik każdego z liczbą; wyniki S1 (T1) wpisane lub „S1 niewykonany".
- [ ] **Step 4:** Raport; **STOP** — użytkownik zatwierdza. Commit raportu: `git add docs/superpowers/reports/F20-2.0a-odbior.md && git commit -m "F20 T8: odbiór 2.0a"`.

---

## FAZA 2.0b — lokalny model tekstowy (kolejność speca: po T8; technicznie niezależna od T2–T8, ale T11 dopisuje do `ProviderPreset.ready` z T5, więc nie równolegle)

### Task 9: Spike S2 — Ollama, llama.cpp, oMLX (pomiar, throwaway)

**Files:** Create: `docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md`

**Warunki wstępne (robi użytkownik):** Ollama zainstalowana (jest tylko `~/.ollama/models`); oMLX uruchamiany z `oMLX.app` (CLI z brew nie startuje); `llama-server` z Homebrew działa. Bez tego raport porównałby dwa serwery, nie trzy.

- [ ] **Step 1:** Przygotuj **dwa** materiały w formacie `[m:ss] Me|Them: …` jak `NotePromptBuilder.transcriptLines`: (a) **sklejka ~60 min** z `.devdata/sessions` — **tylko** do pomiaru czasu, czasu do pierwszego bajtu i kontekstu; (b) **różne, nawet krótsze sesje** do jakości i odrzuceń korekty (powtórzony tekst sklejki zaniżałby odrzucenia i zawyżał spójność). W raporcie tylko liczby.
- [ ] **Step 2:** Dla 2–3 modeli ≤8B Q4 (16 GB RAM) na każdym z trzech serwerów — **na Ollamie obowiązkowo `bonsai-2` (Prism ML, Apache-2.0, model „thinking”, tag `latest` = 9b ≈ 3,2 GB, kontekst 256K; polski niepotwierdzony; pobranie `ollama pull bonsai-2` po zgodzie użytkownika z 2026-10-20, wariant 27b ≈ 8,3 GB odpada przy 16 GB)** — zmierz przez `curl`/skrypt: czas całości **i czas do pierwszego bajtu** dla notatki i korekty partii; czy odpowiedź zawiera „thinking” (`<think>`, `reasoning_content`); numerację linii korekty (`CorrectionBatches.parse`) i **odsetek odrzuconych linii** `CorrectionRules.accepts` (nie partii). **Baseline:** ta sama notatka i korekta z obecnego presetu API na tym samym materiale (b) — użytkownik ocenia różnicę.
- [ ] **Step 3:** Kontekst: jeden przebieg z wejściem dłuższym niż `num_ctx` — czy Ollama obcina po cichu (odpowiedź bez błędu, ale bez końca transkryptu); jak wygląda błąd przepełnienia na llama.cpp i oMLX (kod HTTP i treść — wejście do `ContextError`). `/api/show` (wymaga nazwy modelu) i `/props` (poza `/v1`): jakie pola zwracają, maksimum modelu czy efektywny kontekst; port oMLX (potwierdzić 8000). **Zmierz znaki na token dla polskiego** (do `ContextBudget.charsPerToken` w T12) i **realną długość odpowiedzi mapy** na część (do limitu wyjścia w T13).
- [ ] **Step 4:** Raport z tabelą i **proponowanymi wartościami**: limity transportowy i miękki dla lokalnych, domyślny budżet kontekstu w tokenach, `charsPerToken`, limit wyjścia mapy, modele rekomendowane, sposób wykrywania kontekstu (tylko obniżanie).
- [ ] **Step 5: STOP** — użytkownik wybiera domyślne limity i modele; wartości trafiają do T10–T13. Commit: `git add docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md && git commit -m "F20 T9: S2 — pomiary serwerów tekstowych"`.

---

### Task 10: `chat(timeout:maxTokens:)`, oczyszczanie „thinking”, limity dla wszystkich wołających

**Files:**
- Modify: `Sources/MeetNotesProviders/OpenAICompatibleClient.swift` (`chat`, `chatContent`), `Sources/MeetNotesNotes/NoteGenerator.swift`, `Sources/MeetNotesNotes/Corrector.swift`, `Sources/MeetNotesNotes/AutoTitle.swift` (trzeci wołający `chat`, dziś `timeout: 60`), `Sources/MeetNotesApp/NotesModel.swift` (limity dla lokalnych)
- Create: `Sources/MeetNotesProviders/ThinkingStripper.swift`, `Sources/MeetNotesProviders/ChatLimits.swift`
- Test: `Tests/MeetNotesProvidersTests/ClientTests.swift`, `Tests/MeetNotesProvidersTests/ThinkingStripperTests.swift` (nowy), `Tests/MeetNotesProvidersTests/ChatLimitsTests.swift` (nowy), `Tests/MeetNotesProvidersTests/Stub.swift` (zapis `timeoutInterval` i ciała)

**Interfaces:**
- Produces:
  - `public func chat(model: String, system: String, user: String, timeout: Double = 120, maxTokens: Int? = nil) async throws -> String` — `timeout` trafia do `request(..., timeout:)`, `maxTokens` do pola `max_tokens` ciała (gdy `nil` — brak pola); wołający bez parametrów zachowuje dzisiejsze zachowanie.
  - `public enum ThinkingStripper { public static func clean(_ reply: String) -> String }` — usuwa wszystkie bloki `<think>…</think>` (także wielokrotne, z nowymi liniami), a **niedomknięty** blok `<think>…` do końca odpowiedzi usuwa w całości; zwraca przycięty tekst.
  - `chatContent` bierze tylko `content` (ignoruje `reasoning_content`/`reasoning`) i przepuszcza przez `ThinkingStripper.clean`; pusty wynik → `ProviderError.badResponse("empty reply")`.
  - `public struct ChatLimits: Equatable, Sendable { public var soft: Double; public var transport: Double; public static func `for`(_ provider: Provider, role: Role) -> ChatLimits }` — API: dzisiejsze wartości (notatka 180/120, korekta 120/120, **tytuł 60/120**); lokalne (`provider.isLocal`): wartości z T9 (*szkic:* notatka 600/660, korekta 300/330, tytuł 120/150; **transport zawsze ≥ soft**). `NotesModel` liczy limity dla każdego z trzech wołających (notatka, korekta, `AutoTitle`).

- [ ] **Step 1: Napisz testy:** `ThinkingStripperTests`: `removesClosedBlocks`, `removesMultipleBlocksAndKeepsTheAnswer`, `unterminatedThinkBlockIsAnEmptyReply` (`"<think>zaczynam"` → `""`), `leavesPlainTextUntouched`; `ClientTests`: `chatUsesTheGivenTransportTimeout` (`StubHTTP` zapisuje `timeoutInterval`; `timeout: 600` → 600), `chatSendsMaxTokensOnlyWhenGiven`, `chatIgnoresReasoningContentField`, `chatReplyWithOnlyAThinkBlockThrowsEmptyReply`; `ChatLimitsTests`: `localProvidersGetLongerLimitsThanRemote`, `transportIsNeverShorterThanSoft`, `autoTitleGetsLocalLimitsToo`.
- [ ] **Step 2:** `scripts/test.sh --filter "ThinkingStripperTests|ClientTests|ChatLimitsTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj. `NoteGenerator`, `Corrector` i `AutoTitle.generate` dostają `chatTimeout: Double?` (domyślnie `nil` = 120 s), przekazywany do `chat`; `NotesModel` wylicza `ChatLimits.for(provider, role:)` i podaje `soft` jako `timeout`/`batchTimeout`, `transport` jako `chatTimeout`.
- [ ] **Step 4:** `scripts/test.sh` — zielone.
- [ ] **Step 5: Mutacja:** (a) w `ThinkingStripper` usuń obsługę niedomkniętego bloku → `unterminatedThinkBlockIsAnEmptyReply` ma paść; (b) w `chat` zignoruj `timeout` → `chatUsesTheGivenTransportTimeout` ma paść. Po każdej `git checkout -- <plik>`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesProviders Sources/MeetNotesNotes Sources/MeetNotesApp/NotesModel.swift Tests/MeetNotesProvidersTests && git commit -m "F20 T10: limity chat dla lokalnych, max_tokens, oczyszczanie thinking"`. **Przegląd Opusa po zadaniu.**

---

### Task 11: Dostawcy llama.cpp i oMLX, lokalność w UI, czytelne błędy serwera

**Files:**
- Modify: `Sources/MeetNotesProviders/ProviderSetup.swift` (`ProviderPreset.llamaCpp`, `.omlx`, `ready`, `matching`, `ProviderCheck.describe`), `Sources/MeetNotesProviders/Preset.swift` (`Preset.isFullyLocal`), `Sources/MeetNotesApp/ProviderLogos.swift`, `Sources/MeetNotesApp/SettingsView.swift`, `Sources/MeetNotesApp/PresetsView.swift`, `Sources/MeetNotesApp/NotesModel.swift` (komunikaty), `Sources/MeetNotesApp/Snapshots.swift`
- Test: `Tests/MeetNotesProvidersTests/ProviderSetupTests.swift`, `Tests/MeetNotesProvidersTests/LocalServerErrorTests.swift` (nowy)

**Interfaces:**
- Produces: `ProviderPreset.llamaCpp` (id `"llamacpp"`, „llama.cpp", `http://localhost:8080/v1`, `needsKey: false`, rola „Runs on this Mac · correction and summary"); `ProviderPreset.omlx` (id `"omlx"`, „oMLX", `http://localhost:8000/v1` — port potwierdzony w T9); `ProviderPreset.ready == [openRouter, elevenLabs, ollama, llamaCpp, omlx, onThisMac]`; `LocalServerHint.message(for provider: Provider, error: Error) -> String?` — dla `provider.isLocal`: `.cannotConnectToHost`/`.cannotFindHost` → „Can't reach \(provider.name) at \(address). Start it and try again." (Ollama: `ollama serve`; llama.cpp: `llama-server -m <model>`; oMLX: „open the oMLX app"); **`.timedOut` → „\(provider.name) didn't answer within N s. Try a smaller model, a longer limit or a lower Context window."** (to zwykle działający serwer, nie wyłączony — nie sugerować restartu); `.networkConnectionLost` → „\(provider.name) dropped the connection."; dla nielokalnych `nil`.

- [ ] **Step 1: Napisz testy:** `ProviderSetupTests`: `llamaCppAndOmlxAreReadyProvidersWithoutKeys`, `matchingFindsThemByAddress`; `LocalServerErrorTests`: `unreachableLocalServerNamesTheServer` (`URLError(.cannotConnectToHost)` + provider Ollama → tekst zawiera „Ollama" i adres), `timeoutIsNotReportedAsServerDown` (`.timedOut` → tekst o limicie/mniejszym modelu, bez „Start it"), `connectionLostSaysDropped`, `remoteProviderErrorsAreNotRewritten` (OpenRouter → `nil`), `lanHostDoesNotGetThisMacWording`.
- [ ] **Step 2:** `scripts/test.sh --filter "ProviderSetupTests|LocalServerErrorTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj presety i `LocalServerHint`; podepnij w miejscach, gdzie `NotesModel` składa komunikat o błędzie korekty/notatki (`ContextError.describe` → najpierw `LocalServerHint`). UI: znacznik „On this Mac" przy roli, gdy `provider.isLocal`; plakietka „Fully local" na presecie, gdy wszystkie przypisane role są lokalne (czysta funkcja `Preset.isFullyLocal(providers:)` w `MeetNotesProviders`, test `presetIsFullyLocalOnlyWhenEveryAssignedRoleIsLocal`: pusta rola się nie liczy, rola ElevenLabs/OpenRouter psuje).
- [ ] **Step 4:** `scripts/test.sh` — zielone; sceny w `Snapshots.swift`.
- [ ] **Step 5: Mutacja:** w `isFullyLocal` pomiń sprawdzanie roli `summary` → test ma paść; `git checkout -- Sources/MeetNotesProviders/Preset.swift`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesProviders Sources/MeetNotesApp Tests/MeetNotesProvidersTests && git commit -m "F20 T11: llama.cpp i oMLX, lokalność w UI, błędy serwera lokalnego"`.

---

### Task 12: Budżet kontekstu — jeden mechanizm dla korekty i notatki

**Files:**
- Modify: `Sources/MeetNotesProviders/Provider.swift` (opcjonalne `contextTokens`), `Sources/MeetNotesNotes/Corrector.swift` (`maxBatchChars` z budżetu), `Sources/MeetNotesApp/NotesModel.swift` (nowy closure `contextFor`), `Sources/MeetNotesApp/AppModel.swift` (cache wykrytego kontekstu, wiązanie `contextFor`), `Sources/MeetNotesApp/SettingsView.swift` (pole „Context window (tokens)” dla dostawców lokalnych)
- Create: `Sources/MeetNotesProviders/ContextBudget.swift`, `Sources/MeetNotesProviders/ContextProbe.swift`
- Test: `Tests/MeetNotesProvidersTests/ContextBudgetTests.swift`, `Tests/MeetNotesNotesTests/CorrectorTests.swift` (dopisać)

**Interfaces:**
- Produces:
  - `Provider.contextTokens: Int?` (opcjonalne, E6) — ustawiane przez użytkownika.
  - `public struct ContextBudget: Equatable, Sendable { public var tokens: Int; public var inputChars: Int; public static func resolve(provider: Provider, detected: Int?) -> ContextBudget? }` — `nil` dla dostawców nielokalnych (API: bez budżetu i bez map-reduce). Dla lokalnych: `base = provider.contextTokens ?? defaultTokens` (*szkic:* 4 096, z T9), `tokens = min(base, detected ?? base)` (**wykrycie może tylko obniżyć**), `inputChars = Int(Double(tokens) × charsPerToken) − reserveChars` (*szkic:* `charsPerToken` 1,5 — **z pomiaru T9**, nie 2; `reserveChars` = miejsce na prompt systemowy i odpowiedź, *szkic* 40% tokenów). **`inputChars` jest jedynym limitem wejścia** dla `Corrector` (rozmiar partii) i dla splittera z T13.
  - `public enum ContextProbe { public static func detect(provider: Provider, model: String, http: any HTTPClient) async -> Int? }` — best effort: Ollama `POST /api/show` z `{"model": model}` i llama.cpp `GET /props` pod adresem **bez końcowego `/v1`**; każdy błąd/nieznany serwer → `nil`.
  - `NotesModel.contextFor: (UUID, String) -> Int?` (provider, model → wykryty kontekst z cache w pamięci `AppModel`; wołane raz przy ładowaniu listy modeli roli, nigdzie nie zapisywane).
  - `Corrector.maxBatchChars` = `budget.inputChars` gdy `budget != nil`, inaczej dzisiejsze 6 000.

- [ ] **Step 1: Napisz testy:** `detectionCanOnlyLowerTheBudget` (`detected: 128_000` przy `contextTokens: 4_096` → 4 096; `detected: 2_048` → 2 048), `remoteProviderHasNoBudget`, `userValueOverridesTheDefault`, `inputCharsLeavesRoomForThePromptAndTheAnswer`, `ollamaShowSendsTheModelAndBothEndpointsLiveOutsideV1` (StubHTTP: ścieżki `/api/show` z `model` w ciele i `/props`, nie `/v1/...`), `unknownServerYieldsNilNotAnError`, `correctorBatchSizeFollowsTheBudget` (mały budżet → więcej partii niż przy 6 000 znaków).
- [ ] **Step 2:** `scripts/test.sh --filter "ContextBudgetTests|CorrectorTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj; wykrycie wołane raz przy ładowaniu listy modeli i trzymane w pamięci (nie zapisywane); `NotesModel` dostaje `contextFor` jak inne closures.
- [ ] **Step 4:** `scripts/test.sh` — zielone.
- [ ] **Step 5: Mutacja:** w `resolve` zamień `min` na `max` → `detectionCanOnlyLowerTheBudget` ma paść; `git checkout -- Sources/MeetNotesProviders/ContextBudget.swift`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesProviders Sources/MeetNotesNotes Sources/MeetNotesApp Tests/MeetNotesProvidersTests Tests/MeetNotesNotesTests && git commit -m "F20 T12: budżet kontekstu dla korekty i notatki"`.

---

### Task 13: Map-reduce dla podsumowania

**Files:**
- Modify: `Sources/MeetNotesNotes/NotePrompt.swift`, `Sources/MeetNotesNotes/NoteGenerator.swift`, `Sources/MeetNotesNotes/ContextError.swift`, `Sources/MeetNotesApp/NotesModel.swift`
- Create: `Sources/MeetNotesNotes/TranscriptSplitter.swift`
- Test: `Tests/MeetNotesNotesTests/MapReduceTests.swift`, `Tests/MeetNotesNotesTests/PromptTests.swift`, `Tests/MeetNotesNotesTests/ContextErrorTests.swift` (dopisać)

**Interfaces:**
- Consumes: `ContextBudget` (T12), `ChatLimits` i `chat(timeout:maxTokens:)` (T10), `NotePromptBuilder.transcriptLines`, `NoteGenerator`.
- Produces:
  - `public enum TranscriptSplitter { public static func parts(_ lines: [String], maxChars: Int) -> [[String]] }` — pakuje linie `[m:ss] Me|Them: …` po kolei; **linia dłuższa niż `maxChars` jest dzielona na granicy słowa**, z powtórzonym prefiksem `[m:ss] Me:`/`Them:` na każdym kawałku (monolog bez pauz 1,2 s jest jedną wypowiedzią); jeśli linii nie da się podzielić (jedno słowo > `maxChars`) → jawny błąd `NoteGenerationError.failed("A single line is longer than the Context window. Raise it in Settings.")`.
  - `NotePromptBuilder.mapPrompt(part: [String], index: Int, count: Int, notesLanguage: LanguageCode?) -> NotePrompt` — system: skondensuj do **tego samego formatu linii** `[m:ss] Me|Them: …`, zachowaj nazwy, liczby, decyzje i zadania, bez interpretacji i dodawania treści; user: linie części. Wywołanie z `maxTokens` = limit wyjścia mapy z T9.
  - `NotePromptBuilder.build(...)` dostaje `condensed: Bool = false` — gdy `true`, w prompcie systemowym dopisane „The transcript below is a condensed version of the full recording.” **Context i My notes tylko w reduce.**
  - `NoteGenerator.generate(...)` dostaje `budget: ContextBudget? = nil`; gdy `budget == nil` albo transkrypt mieści się w `budget.inputChars` → ścieżka dzisiejsza bez zmian. Inaczej: map każdej części (limit czasu **na wywołanie**, `ChatLimits.soft`), potem **warunek w kodzie: `suma wyjść mapy ≤ budget.inputChars`**; gdy się nie mieści → reduce **hierarchiczny** (części wyjść mapy znowu przez map, do trzech poziomów), a gdy nadal nie → `NoteGenerationError.failed("The transcript is too long for this model's Context window. Raise it in Settings or use a model with a longer context.")` — **nigdy wysyłka większa niż budżet**. Błąd dowolnej części → `failed("Part n of m failed: …")`, żadnej częściowej notatki.
  - `ContextError.describe(model:error:isLocal:)` — zdanie „Splitting long transcripts arrives later” zostaje dla ścieżki API (`isLocal == false`); dla lokalnych: wskazuje „Context window” w Settings.

- [ ] **Step 1: Napisz testy:** `TranscriptSplitter`: `splitsAtLineBoundariesNeverMidLine`, `oversizedLineIsSplitAtWordBoundaryKeepingThePrefix`, `unsplittableLineIsAnExplicitError`; `PromptTests`: `condensedPromptAddsTheOneSentence`, `mapPromptDemandsTheSameLineFormat`, `mapPromptHasNoUserNotesNorContext`; `MapReduceTests` (atrapa klienta zapisuje prompty i podane `maxTokens`/`timeout`): `shortTranscriptTakesTheSinglePromptPath` (1 wywołanie), `longTranscriptMapsEachPartThenReducesOnce` (n+1), `reduceInputKeepsSpeakerAndClock`, `userNotesAndContextAppearOnlyInReduce`, `reduceInputNeverExceedsTheBudgetInTheWorstCase` (7 części × maksymalne wyjście mapy → wejście reduce ≤ `inputChars` albo hierarchia/błąd), `tooLongEvenAfterHierarchyIsAnExplicitError`, `oneFailedPartFailsTheSummary` (część 2 z 3 → `failed` z „Part 2 of 3”, **żaden** plik notatki nie powstaje), `eachCallGetsItsOwnTimeout` (nie jeden na całość), `apiProviderNeverSplits` (`budget == nil`); `ContextErrorTests`: `apiOverflowKeepsTheArrivesLaterSentence`, `localOverflowPointsAtContextWindow`.
- [ ] **Step 2:** `scripts/test.sh --filter "MapReduceTests|PromptTests|ContextErrorTests"` → FAIL.
- [ ] **Step 3:** Zaimplementuj; `NotesModel.generate` wylicza `ContextBudget.resolve(provider:detected: contextFor(provider, model))` dla wybranego dostawcy podsumowania i przekazuje do `NoteGenerator`.
- [ ] **Step 4:** `scripts/test.sh` — zielone.
- [ ] **Step 5: Mutacja:** (a) dołącz `myNotes`/`context` także do części map → `userNotesAndContextAppearOnlyInReduce` ma paść; (b) usuń warunek `suma ≤ inputChars` → `reduceInputNeverExceedsTheBudgetInTheWorstCase` ma paść. Po każdej `git checkout -- Sources/MeetNotesNotes/NoteGenerator.swift`.
- [ ] **Step 6:** Commit: `git add Sources/MeetNotesNotes Sources/MeetNotesApp/NotesModel.swift Tests/MeetNotesNotesTests && git commit -m "F20 T13: map-reduce dla podsumowania z budżetem kontekstu"`. **Przegląd Opusa po zadaniu.**

---

### Task 14: Odbiór 2.0b, dokumenty i przegląd całości (STOP)

**Files:** Create: `docs/superpowers/reports/F20-2.0b-odbior.md`, `docs/superpowers/reports/F20-przeglad-calosci.md`; Modify: `docs/wymagania.md`, `docs/superpowers/ROADMAP.md`, `CLAUDE.md` (stan), `docs/superpowers/BACKLOG.md`

- [ ] **Step 1:** Odbiór na sprzęcie: dla każdego dostępnego serwera (Ollama, llama.cpp, oMLX) korekta + notatka z krótkiego i z długiego transkryptu (map-reduce); serwer wyłączony → komunikat z nazwą serwera; model „thinking" → brak bloku w notatce; **sieć wyłączona**: pełny przebieg lokalny z 2.0a + 2.0b na jednym presecie („Fully local"). Jakość map-reduce wobec ścieżki jednoprzebiegowej (notatka tego samego spotkania, ocena użytkownika).
- [ ] **Step 2:** Dokumenty: `docs/wymagania.md` — wpis o magazynie FluidAudio i wariantach, Ollama/oMLX/llama.cpp jako lokalne role tekstowe; **nie** poprawiamy twierdzenia o Parakeecie „na dysku" (jest prawdziwe); `ROADMAP.md` — przenieś pozycje „Długie transkrypty" i „Lokalny ASR" do „zamknięte w 2.0", dodaj „2.1+ wbudowany `llama-server`"; `CLAUDE.md` — Stan i nowy moduł w liście kodu; `BACKLOG.md` — uwagi z przeglądu.
- [ ] **Step 3:** Przegląd całości (Opus xhigh, osobna sesja, tylko do odczytu + `scripts/test.sh`): zgodność ze specem i recenzją F20 (R1–R14), anty-cele, mutacje.
- [ ] **Step 4: STOP** — użytkownik zatwierdza scalenie. Commit dokumentów: jawne ścieżki, `git commit -m "F20 T14: odbiór 2.0b, dokumenty, przegląd całości"`.
