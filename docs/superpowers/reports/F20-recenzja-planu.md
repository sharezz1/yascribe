# Recenzja planu fazy 2.0 „Lokalne modele" (2026-10-20)

> **Cel recenzji:** `docs/superpowers/plans/2026-10-20-faza20-lokalne-modele.md`
> (`sha256 4af6b502…4f3c`, 348 linii, jeszcze niecommitowany), argumentowany ze speca v2
> (`sha256 d3c35826…c6a`, 246 linii). Recenzja tylko do odczytu — w repo powstał wyłącznie ten plik.
>
> **Werdykt: do poprawy** — 2 blokery (P1–P2), 7 rzeczy do domknięcia przed wykonaniem (P3–P9),
> 4 drobne (P10–P13). Plan jest wykonawczy i dobrze mapuje spec; blokery dotyczą dwóch mechanizmów,
> które plan sam obiecuje (odcisk modelu, budżet kontekstu), a które w obecnym kształcie nie działają
> w aplikacji albo nie są egzekwowane.
>
> Oznaczenia: 🔴 blokuje wykonanie · 🟡 do domknięcia przed startem zadania · 🟢 drobne.

## Co jest dobre (nie ruszać)

- **Mapowanie spec → zadania jest 1:1.** Każdy punkt §4.2 i §5.2 ma właściciela: R1→T2, `.filtered`→T5,
  cykl życia→T4/T6, limity→T10, budżet→T12, map-reduce→T13, dokumenty→T14. Nie ma „robimy gdzieś".
- **Izolacja FluidAudio w osobnym module** (`MeetNotesLocalASR`, jedyne `import FluidAudio`) z testem
  `grep` na kryterium 3.9 — to jest właściwy szew i dobra decyzja, nie kosmetyka.
- **Spiki mają kryteria wykonywalne, nie deklaratywne:** T0 (a)–(e) to `swift build`, `test.sh`,
  `bundle.sh`, `otool -L`, uruchomienie aplikacji. Lepsze niż spec, który pytał „czy się buduje?".
- **Każda bramka ma mutację i nazwany test**, a mutacje dotyczą właściwej rzeczy (`isLocal` → bramka
  klucza, `store.status()` → odmowa przebiegu, `min`→`max` → budżet, my notes w map → reduce).
  To dokładnie ten styl, który projekt stosuje od fazy 1.
- **T2 naprawia R1 jednym predykatem** (`requiresKey = !isLocal`) zamiast drugiej listy hostów —
  zgodnie z §4.2 i §11.5. Testy lokalności pokrywają `::1`, `*.localhost`, LAN i ElevenLabs na loopbacku.
- **T8/T14 mają STOP i „sieć off"**, a T1/T9 są świadomie odcięte od kodu (S1 bramkuje raport, nie
  implementację). Kolejność jest jedna (§7/§11.2), bez dwóch harmonogramów z recenzji F20.

## Relacja do recenzji F20 (spec v1 → v2)

Spec został przepisany po recenzji: **R1–R14 są zamknięte w v2** i sprawdziłem to punkt po punkcie —
`providerWithKey` (§4.2 pkt 1), dwa limity czasu (§5.2), korpus i referencja S1 (§7 + §13),
cztery miejsca `ProviderKind` (§4.2 pkt 2–4), sonda `.filtered` (§4.2), budżet z zasadami (1)–(4)
(§5.2), kontrakt map-reduce (§11.4), cykl życia jako actor (§4.2), Ollama/oMLX w §7, Parakeet
na dysku i „nie poprawiać dokumentów" (§3, §10), `CorrectionRules.accepts`, brak sumy kontrolnej
(manifest rozmiarów), `modelFingerprint` (§4.2), jedna kolejność (§11.2). Plan nie musi wracać do
tamtych punktów — **zostają tylko rzeczy nowe, specyficzne dla planu**, poniżej.

---

## 🔴 Blokery

### P1. Odcisk modelu jest sprawdzany w warstwie, której aplikacja nie używa (T4/T6, Review Focus #5)

**Gdzie:** plan T4 (test `resumeWithChangedModelFingerprintIsRejected`, s. 163), T6 (przekazanie
`modelFingerprint`, s. 203), Review Focus #5 (s. 42); spec §4.2 („wznowienie po zmianie modelu…
nie mieszało okien").

**Dowód:** `AppModel.resume` (`AppModel.swift:574-582`) ładuje `input.json` i podaje **zapisany**
snapshot do runnera:

```swift
guard let input = try? JSONFile.load(RunInput?.self, from: …input, default: nil) else { … }
run(sessionURL: item.url, runID: runID, snapshot: input.snapshot, client: c)
```

Runner porównuje zapisane wejście z **tym samym** snapshotem (`TranscriptionRunner.swift:97-101`),
więc `RunError.inputMismatch` nie może wystąpić. Drugą drogą też nie: `transcribe` zawsze tworzy
nowy `runID` (`AppModel.swift:563`, `Self.sessionName(Date())`), a świeży przebieg nie porównuje
się z żadnym starym `input.json`. Wniosek: `inputMismatch` jest osiągalny tylko z CLI przy
reużyciu `--run`; test T4 przechodzi na warstwie runnera, a obietnica „wznowienie po zmianie modelu
nie miesza okien" **nie jest prawdziwa w aplikacji**. To ten sam wzorzec, który recenzja F20
wytknęła sondzie: bramka istnieje, ale nie na ścieżce, którą idzie użytkownik.

**Naprawa:**
1. Czysta funkcja w `MeetNotesLocalASR`: `RunGate.checkResume(snapshot:currentFingerprint:currentProvider:)`
   — odmowa, gdy `provider.api == .fluidAudio` i odcisk (albo model) różni się od zapisanego;
   komunikat „The on-device model changed since this run. Start a new transcription.".
2. Wywołanie w `AppModel.resume` **przed** `run(...)`; test w `RunGateTests` (poza `RunnerTests`).
3. Przy okazji: w `transcribe` przekazuj `store.fingerprint()` tylko dla `provider.api == .fluidAudio`
   — dziś plan robi to bezwarunkowo, więc przebieg API dostaje w migawce hash lokalnego modelu.
4. **Mutacja w T4 (s. 167) nie da czerwieni.** „Wyjęcie pola z `Codable`" nie zmienia `Equatable`
   w pamięci — test konstruuje dwa snapshoty i porównuje je bez kodowania, więc zostanie zielony.
   Mutacja musi łamać równość, np. `self.modelFingerprint = nil` w `init` (wtedy dwa różne odciski
   są równe → test pada). Inaczej bramka mutacyjna ocenia coś innego, niż deklaruje.

### P2. Budżet kontekstu nie jest egzekwowany na wyjściu mapy ani na wejściu reduce (T12/T13)

**Gdzie:** plan T12 (s. 304: `maxChars = tokens × 2`), T13 (s. 327–332: splitter, `mapPrompt`,
warunek wejścia w `generate`, test `singleOversizedLineStaysAlone`).

**Dowód:**
- Dziś `NotePromptBuilder` skleja **wszystkie** linie bez limitu (`NotePrompt.swift:38-46,52-58`), więc
  map-reduce jest jedyną ochroną. Plan tnie tylko **wejście** (`TranscriptSplitter`), a wyjście mapy
  nie ma żadnego limitu — reduce dostaje sumę skrótów.
- Rachunek dla celu z S2: 60 min ≈ 50 tys. znaków; budżet 4096 tokenów × 2 = 8192 znaki → ~7 części.
  Prompt mapy każe zachować nazwy, liczby, decyzje i format `[m:ss] Me|Them:`, więc 8B zwróci
  realnie 2–4 tys. znaków na część → reduce dostaje **15–30 tys. znaków**, czyli 2–4× budżet.
  Ollama, która może obcinać po cichu (to jedno z pytań S2), wytnie ogon i notatka będzie
  „z początku spotkania". To jest dokładnie anty-cel ze speca §2, tylko przeniesiony o jeden etap.
- `singleOversizedLineStaysAlone` (s. 332) **świadomie** przepuszcza linię większą niż budżet.
  Jedna długa wypowiedź (monolog bez pauz 1,2 s — `Merger.utteranceGap`) omija cały mechanizm.
- Brak limitu czasu na wywołanie: `NoteGenerator.timeout` jest jeden dla całego `generate`; przy
  n+1 wywołaniach 600 s dzieli się na wszystkie i mapa padnie w środku.

**Naprawa:**
1. Twardy limit na wywołanie map (`max_tokens`/`maxOutputChars`) i **warunek** `reduceInput ≤ budget.inputChars`
   sprawdzany w kodzie, z testem na najgorszym przypadku (7 części × maks. wyjście).
2. Jeśli reduce nadal się nie mieści: reduce hierarchiczny albo jawny błąd („raise Context window") —
   **nigdy** wysyłka większa niż budżet.
3. Dzielenie zbyt długiej linii po słowach, z powtórzonym prefiksem `[m:ss] Me:`; `singleOversizedLineStaysAlone`
   zamienić na `oversizedLineIsSplitAtWordBoundary` (albo jawny błąd, jeśli linii nie da się podzielić).
4. Jeden `inputChars` (budżet minus rezerwa na prompt) wspólny dla `Corrector` i splittera — dziś
   `Corrector` dostaje rezerwę 50% (s. 306), a splitter żadnej, choć oba jedzą ten sam budżet.
5. Limit czasu **na wywołanie** map/reduce, nie na całość.

---

## 🟡 Do domknięcia przed startem zadania

### P3. T3 (magazyn modelu): trzy niespójności i jedna pułapka

**Dowód / naprawa:**
1. **Konstruktor bez `Downloader`.** Interfejs (s. 136): `init(directory: URL = ModelStore.sharedDirectory)`,
   a krok 1 (s. 139) mówi „atrapa pobierania przez wstrzyknięty `Downloader`" — nie ma czym wstrzyknąć.
   Dodaj parametr (`download: @Sendable … = fluidAudioDownloader`) albo testy pobierania nie powstaną.
2. **`status()` nie może raportować `.downloading(fraction:)`.** `ModelStore` to `struct`; stan
   pobrania w toku żyje poza wartością. Albo `actor`/`class` z polem in-flight, albo `.downloading`
   tylko w `LocalASRSupport` (UI), a `status()` zwraca `missing/ready/invalid`.
3. **Manifest ze współdzielonego magazynu to pułapka.** S0 krok 3 (s. 83) bierze listę plików
   z **istniejącego** katalogu `parakeet-tdt-0.6b-v3-coreml` — utworzonego przez inną aplikację,
   może inną precyzją enkodera (`encoderPrecision`) i inną wersją FluidAudio. Jeśli nasz pinned
   `downloadAndLoad(version: .v3, encoderPrecision: …)` wyprodukuje inne rozmiary, poprawny model
   dostanie `.invalid` i użytkownik wpadnie w pętlę „Download again". Przypnij wersję **i** precyzję
   w jednym miejscu i zrób manifest ze **świeżego pobrania tą samą wersją** (S0 krok 2), nie z cudzego
   magazynu. Wariant nieznany → osobny komunikat, nie „invalid".
4. **Nazwy testów.** Krok 1 (s. 139) nazywa test `wrongFileSizeIsInvalidWithTheFileName`, a Review
   Focus #1 i ten sam krok mówią `tamperedModelFileIsRefusedWithReason`; mutacja (s. 143) wskazuje
   pierwszą nazwę. Jedna nazwa — inaczej bramka mutacyjna ocenia test, którego nie ma.

### P4. T8(b) nie ma czym wskazać kopii magazynu w aplikacji

**Dowód:** katalog jest wstrzykiwany tylko w bibliotece (`ModelStore(directory:)`); aplikacja tworzy
`ModelStore()` z `sharedDirectory` (s. 137). T8 krok 2(b) (s. 231) mówi „podmieniony plik w **kopii**
magazynu", ale w aplikacji nie ma ścieżki, która wskaże kopię — chyba że użytkownik podmieni plik
w prawdziwym współdzielonym magazynie, czego robić nie wolno (używają go cztery inne aplikacje).

**Naprawa:** deweloperski override w `ModelStore.sharedDirectory` (np. `MEETNOTES_MODEL_STORE`,
czytany tylko w buildzie dev) i opis w T3; w przeciwnym razie (b) zostaje testem bibliotecznym
i trzeba to napisać wprost w T8.

### P5. `ContextProbe.detect(provider:http:)` nie ma modelu, a `detected` nie ma drogi do `NotesModel`

**Dowód:**
- Ollama `POST /api/show` wymaga `{"model": …}`; bez nazwy modelu nie zapytasz. Sygnatura (s. 305)
  musi mieć `model: String` (llama.cpp `GET /props` bez zmian).
- Plan mówi „wykrycie wołane raz przy ładowaniu listy modeli i trzymane w pamięci" (s. 310), ale cache
  żyje w `AppModel`, a `NotesModel` dostaje **tylko closures** (`NotesModel.swift:27-35`: `clientFor`,
  `presetFor`, `presetsInfo`…). Bez nowego `contextFor: (UUID, String) -> Int?` (klucz provider+model)
  T13 nie ma skąd wziąć `detected`.
- `maxChars = tokens × 2` (s. 304) to górna granica dla polskiego (BPE schodzi do ~1,5–2 znaków/token).
  Zmierz znaki/token w S2 albo zejdź do 1,5; inaczej budżet jest o 20–30% za duży i wracamy do P2.

### P6. `LocalServerHint` myli timeout z „serwer nie działa"

**Dowód:** plan s. 283 mapuje `URLError.timedOut` na „Can't reach \(name) at \(address). Start it and
try again." — a `timedOut` to najczęściej **działający** serwer, który nie zdążył (transport 120 s,
za duży kontekst, model 8B). Użytkownik dostanie instrukcję restartu sprawnego procesu, zamiast
„zmniejsz model / podnieś limit / zmniejsz Context window". To dokładnie klasa błędu, którą T10 ma
usunąć („nie surowe `URLError`"), tylko przeniesiona w sugestię.

**Naprawa:** rozdzielić: `cannotConnectToHost`/`cannotFindHost` → „start it"; `timedOut` → „didn't
answer within N s — try a smaller model, a larger timeout, or a lower Context window";
`networkConnectionLost` → „the server dropped the connection".

### P7. `Package.resolved` poza commitami — wbrew polityce repo

**Dowód:** `.gitignore` ma komentarz „Package.resolved celowo NIE jest ignorowany: przypinamy dokładne
wersje zależności (FluidAudio wydaje ~raz w tygodniu)". T3 (s. 144) i T6 (s. 206) commitują
`Package.swift` i katalogi, ale nie lockfile; przy zakazie `git add -A` plik zostanie nieśledzony.
Do tego T0 ma podać „wersję przypiętą do commitu/tagu" (s. 79) — bez `Package.resolved` to nie jest
pin, tylko intencja.

**Naprawa:** `git add … Package.resolved` w T3 oraz w raporcie S0: tag/commit FluidAudio **i** wersja
`text-processing-rs` (binaryTarget `NemoTextProcessing.xcframework` ma własny numer wydania).

### P8. „Preparing model…" nie ma właściciela

**Dowód:** spec §4.2 (s. 116) wymaga komunikatu na czas kompilacji ANE („tu bywa kilka minut; to nie
jest zawieszenie"). `ModelStatus` (s. 135) ma tylko `missing/downloading/ready/invalid`, a `load()`
jest leniwy w pierwszym `transcribe` (s. 159). Po starcie przebiegu UI pokaże 0% postępu przez
kilka minut — dokładnie to, przed czym spec ostrzega.

**Naprawa:** stan `.preparing` w `ModelStatus` (albo `LocalASRSupport.isPreparing`) ustawiany przez
T6 przed pierwszym `load()` i mapowany w T7; test `cardStateMapsEveryStatus` dostaje przypadek.

### P9. S2 bez punktu odniesienia jakości i z materiałem „sklejonym"

**Dowód:** T9 krok 2 (s. 246) mierzy odsetek odrzuceń i notatkę, krok 4 (s. 248) rekomenduje modele —
ale nie ma baseline'u. „Jakość notatki" bez porównania z obecnym presetem API jest opinią; odsetek
odrzuceń `CorrectionRules.accepts` = 0 dla API, więc liczba bez kontekstu nic nie mówi. Do tego
materiał do jakości to sklejka sesji (s. 245): powtórzony tekst zaniża odrzucenia i zawyża spójność.

**Naprawa:** (a) ta sama notatka z obecnego presetu API jako baseline (użytkownik ocenia różnicę);
(b) sklejka tylko do czasu/kontekstu, do jakości i odrzuceń — różne sesje (nawet krótsze);
(c) w raporcie podaj odrzucenia jako odsetek linii, nie partii.

---

## 🟢 Drobne

### P10. `AutoTitle` poza T10 — trzeci wołający `chat`
`AutoTitle.generate` ma `timeout: 60` i woła `client.chat(...)` (`AutoTitle.swift:54-58`); dla
lokalnego modelu (zimny start, thinking) tytuł zwykle po cichu nie powstanie → „Untitled meeting".
Albo podaj mu `ChatLimits.for(provider, role: .summary)` z `NotesModel` (`NotesModel.swift:147-153`),
albo napisz w T10, że to świadome.

### P11. T11: `Preset.swift` brak w `Files`, choć mutacja go dotyka
Mutacja (s. 289) robi `git checkout -- Sources/MeetNotesProviders/Preset.swift`, a `Files` (s. 279)
tego pliku nie wymienia — `isFullyLocal` jest tam nową funkcją. Dopisz do `Files` (commit i tak
bierze cały katalog, więc to porządek, nie ryzyko).

### P12. T7: „Download (461 MB)" na sztywno
Rozmiar bierz z `ModelManifest` (suma rozmiarów plików) — inaczej UI skłamie po zmianie wersji
modelu albo precyzji enkodera.

### P13. T13: `ContextError.describe` nie rozróżnia API od lokalnego
Plan (s. 334) każe usunąć „Splitting long transcripts arrives later" — ale map-reduce jest **tylko**
dla lokalnych, więc dla API to zdanie jest nadal prawdziwe. Przekaż flagę (`isLocal`) albo zostaw
je dla ścieżki API.

---

## Czego nie sprawdziłem

- Czy FluidAudio buduje się samymi CLT i czy `bundle.sh` (kopiuje tylko binarkę) przeżyje
  `binaryTarget` — to treść T0; nie uruchamiałem (wymagałoby dodania zależności do repo).
- Czy Ollama obcina wejście po cichu i jakie `num_ctx` naprawdę działa — S2.
- Jakość PL, halucynacje na ciszy, RTF — S1.
- Ile realnie znaków zwróci mapa na część (P2) — to zależy od modelu i promptu; dlatego P2 wymaga
  testu na najgorszym przypadku, nie założenia.
- Czy `defer { await … }` w miejscu z anulowaniem zadania zawsze doczeka `release()` — sprawdziłem
  kompilację i proste wykonanie (`a, b, defer-ran`), nie anulowanie w połowie.

## Sprawdzone u źródła (skrót dowodów)

| Twierdzenie planu / założenie | Wynik |
|---|---|
| `WAVEncoder` daje 16 kHz mono Int16 (format dla `WAVDecoder`) | ✅ `WAVEncoder.swift:22` |
| Klipy sondy są w tym samym formacie (inaczej lokalna sonda padnie) | ✅ nagłówek klipu PL: fmt 1, 1 kanał, 16000 Hz, 16 bitów |
| `defer { await … }` się nie kompiluje (pierwotna teza recenzenta) | ❌ **wycofane** — Swift 6.4 kompiluje i wykonuje po wyjściu z zakresu |
| `await (client as? ReleasableClient)?.release()` się kompiluje | ✅ `swiftc -swift-version 6 -typecheck` |
| `URL.host()` dla `[::1]`, `*.localhost`, `local://fluidaudio` | ✅ `::1`, `llm.localhost`, `fluidaudio` — testy T2 są poprawne |
| `AppModel.resume` porównuje odcisk modelu | ❌ podaje zapisany snapshot — P1 |
| `transcribe` tworzy nowy `runID` przy każdym przebiegu | ✅ `AppModel.swift:563` |
| `NotesModel` dostaje zależności tylko przez closures | ✅ `NotesModel.swift:27-35` — P5 |
| `.gitignore` pinuje `Package.resolved` | ✅ komentarz w `.gitignore` — P7 |
| `Snapshots.swift` istnieje (T7/T11 go modyfikują) | ✅ `Sources/MeetNotesApp/Snapshots.swift` |
| Katalogi testowe `mn-<UUID>` zgodne z `scripts/test.sh` | ✅ |
| Referencja do kryterium 3.3 istnieje (FluidVoice, 26 min) | ✅ `~/Downloads/fluidvoice - bez AI parakeet.txt` (2628 słów) + audio w `GCX/meeting notes/2026-09-23/WFM/` — przenieś referencję do spików, `~/Downloads` bywa czyszczony |
| Parakeet v3 w magazynie (461 MB) | ✅ z recenzji F20 |
| Ollama niezainstalowana | ✅ plan to wie (T9 warunki wstępne) |

## Skrót do wklejenia (autorowi / na czat, ≤1500 znaków)

Recenzja planu F20 (`4af6b502…`): do poprawy. 2 blokery:

1. **P1 odcisk modelu sprawdzany tam, gdzie aplikacja go nie używa.** `AppModel.resume` (574-582)
   podaje zapisany snapshot do runnera, a `transcribe` zawsze robi nowy `runID` — `inputMismatch`
   nie wystąpi. Review Focus #5 jest nieprawdziwy. Dodaj `RunGate.checkResume` (snapshot vs
   `store.fingerprint()`) w `resume` + test; fingerprint tylko dla `.fluidAudio`.
2. **P2 budżet kontekstu nieegzekwowany end-to-end.** Splitter tnie wejście, wyjście mapy bez limitu,
   reduce dostaje sumę skrótów (60 min ≈ 7 części × 2–4 tys. znaków > 8 tys.) → Ollama obcina po
   cichu; `singleOversizedLineStaysAlone` omija budżet; brak limitu czasu na wywołanie. Dodaj cap
   na map, warunek `reduceInput ≤ budget.inputChars`, dzielenie długiej linii, jeden `inputChars`.

Ważne: T3 init bez `Downloader` + manifest ze współdzielonego magazynu + dwie nazwy testu; T8(b) brak
override katalogu w aplikacji; `ContextProbe` bez modelu i bez drogi do `NotesModel`; `LocalServerHint`
myli `timedOut` z „serwer nie działa"; `Package.resolved` poza commitami; brak stanu „Preparing model…";
S2 bez baseline'u jakości.

Drobne: `AutoTitle` poza T10; `Preset.swift` brak w T11 Files; 461 MB na sztywno; `ContextError`
dla API.

Sprawdzone: WAV 16k mono (encoder i klipy), async `defer` kompiluje się na 6.4 (teza wycofana),
host `::1`/`*.localhost` OK, referencja 3.3 istnieje.

Pełne: `docs/superpowers/reports/F20-recenzja-planu.md`.
