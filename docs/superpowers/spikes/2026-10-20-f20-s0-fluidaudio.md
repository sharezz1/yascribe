# F20 S0 — FluidAudio w naszym toolchainie (raport spiku)

> Spike jednorazowy (Task 0 planu `docs/superpowers/plans/2026-10-20-faza20-lokalne-modele.md`, spec §4.3/§7/§11.2). Wykonał agent
> (Sonnet 5.5), 2026-10-20, Apple M4 / 16 GB / macOS 27.0.1 (26A434), Swift 6.4 (swiftlang-6.4.0.34.1), **tylko Command Line Tools**.
> Pakiet sondy i wszystkie eksperymenty leżały **poza repo** (scratchpad sesji, katalog `f20-s0/`); `Package.swift`, `Package.resolved`,
> `Sources/`, `Tests/` repo **nie były ruszane**. Kryteria (b) i (c) wykonano na **kopii** repo (`rsync`, bez `.build`, `.devdata`, `.git`).
> Raport nie zawiera treści nagrań ani transkryptów — tylko długości, liczby i czasy. Jedyne teksty, które widać, to zdanie
> **syntetyczne** (macOS `say -v Zosia`), użyte do pokazania kształtu wyniku.

## 1. Rekomendacja: **GO** dla 2.0a (z pięcioma uwagami wejściowymi dla T3/T4)

Wszystkie pięć kryteriów (a)–(e) spełnione, z dowodem wykonywalnym. FluidAudio buduje się samymi CLT, nie psuje `scripts/test.sh`,
nie dokłada żadnej zależności dynamicznej do `.app`, a Parakeet v3 transkrybuje polski z czasami słów z RTFx 50–120 na tym Macu.

Znaleziska, które **zmieniają plan** (szczegóły w §7; to nie są blokery, ale T3/T4 muszą je uwzględnić):

1. **🔴 Pierwsze `swift package resolve` na czystym katalogu zawiesza się na pobieraniu `binaryTarget`** (`NemoTextProcessing.xcframework`),
   bo SwiftPM czyta **pęk kluczy** (`SecItemCopyMatching` → `securityd`) i czeka bez końca. Obejście: `swift package --disable-keychain resolve`
   (5 s). Dotyczy też `swift build`/`swift test` na świeżym klonie, dopóki artefakt nie jest w `.build`. Nie klikałem żadnych okien
   uprawnień ani nie dotykałem pęku kluczy; przyczynę ustaliłem ze stosu wątku (`sample`) i potwierdziłem flagą.
2. **🔴 Model leżący dziś we wspólnym magazynie NIE zostanie rozpoznany przez ten pin.** FluidAudio 0.17.7 szuka folderu
   `parakeet-tdt-0.6b-v3` i pliku `JointDecisionv3.mlmodelc`; na tym Macu jest `parakeet-tdt-0.6b-v3-coreml` z `JointDecision.mlmodelc`
   (starsza wersja biblioteki). `AsrModels.modelsExist` → `false` dla obu nazw w tym magazynie. Wagi są **bajt w bajt te same**
   (SHA-256 4 plików `weight.bin` zgodne), ale „Download” dociągnie drugą kopię ~461 MB. Spec §3.5/§4.2/§11.6 („gdy model już jest, Download nic nie robi”) jest
   prawdziwy tylko dla magazynu zapisanego tą samą generacją biblioteki. **Decyzja użytkownika** (§7.2).
3. **`scripts/test.sh` źle liczy cel z dokładnie 1 testem** (regex `[0-9]+ tests` nie łapie „1 test”) → kod 4 / wynik NIEWAŻNY (§3 (b)). Nowy cel testowy
   `MeetNotesLocalASRTests` musi mieć ≥ 2 testy albo regex trzeba poprawić (`tests?`).
4. **Postęp pobierania z FluidAudio nie jest monotoniczny** (resetuje się 3× — jedno wywołanie na komponent) i nie ma sensownych liczników plików;
   pasek w T3/T7 trzeba liczyć w adapterze (§7.3).
5. **🔴 `AsrModels.load(from:)` i `downloadAndLoad` mogą po cichu dociągać brakujące pliki z HF** (ta sama ścieżka co `download`). Adapter ma ładować **wyłącznie `AsrModels.loadLocal`** (brak pliku =
   `AsrModelsError.modelNotFound`, zero sieci) — inaczej łamie anty-cel „pobieranie bez zgody” (§7.5).

## 2. Pin (jeden, do `Package.swift` w T3)

| Element | Wartość |
|---|---|
| FluidAudio | `https://github.com/FluidInference/FluidAudio.git`, `.package(url:…, exact: "0.17.7")` (najnowszy tag w dniu pomiaru; tag adnotowany 2437bf2a65dc070eabf24e339f9d5a9723a5a8bf (obiekt tagu), commit **503b4bd1bbf7220882de39fe8ae6716aae4132da** — hashe upstreamu, nie z tego repo, stąd bez backticków dla `check-hashes.sh`) |
| Licencja | Apache-2.0 |
| Model | `AsrModelVersion.v3` — HF `FluidInference/parakeet-tdt-0.6b-v3-coreml` (wielojęzyczny, 25 języków europejskich, w tym PL) |
| Precyzja enkodera | `ParakeetEncoderPrecision.int8` (domyślna; plik `Encoder.mlmodelc`, w rzeczywistości paletyzacja 6-bit LUT — `config.json` mówi „labeled int8 historically”). Inne: `.int8V2` (`Encoder_v2.mlmodelc`, 568 MB, „naprawia #760: zepsute tokeny przy pewnym prawym kontekście”), `.int4`. **Nie porównywałem jakości** `.int8` z `.int8V2` (każde to osobne pobieranie ≥ 0,5 GB, poza zgodą spiku) — to pytanie dla S1 |
| `text-processing-rs` | **v0.3.1** — `binaryTarget` `NemoTextProcessing.xcframework.zip` (87 267 919 B), checksum `5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa` (zweryfikowany `shasum -a 256` na pobranym pliku) |
| Manifest SwiftPM | używany jest `Package@swift-6.2.swift` (tools 6.2+, z cechą `NemoTextProcessing`); minimalna platforma FluidAudio `.macOS(.v14)` (u nas 15.0 — bez konfliktu) |

`Package.resolved` (wygenerowany w pakiecie sondy i w kopii repo, identyczny):

```json
{
  "originHash" : "638730670cbce3d9eb3fc9009e2bb1fab16c1be6711d9aeb346560bbc68da54c",
  "pins" : [
    { "identity" : "fluidaudio", "kind" : "remoteSourceControl",
      "location" : "https://github.com/FluidInference/FluidAudio.git",
      "state" : { "revision" : "503b4bd1bbf7220882de39fe8ae6716aae4132da", "version" : "0.17.7" } }
  ],
  "version" : 3
}
```

(`originHash` zależy od zestawu zależności całego pakietu; w repo po dodaniu zależności będzie inny — wartość istotna to `revision`. `binaryTarget` nie trafia do
`Package.resolved`, bo jest przypięty sumą kontrolną w manifeście FluidAudio.)

**Model nie jest przypięty do commita na HF.** `ModelNames.Repo.revision` zwraca `"main"` dla Parakeeta (tylko diarizer ma przypięty commit). Dlatego integralność
musi iść z **naszego manifestu** (§5), a nie z „wersji modelu”. Biblioteka ma `ModelRegistry.revisionOverrides` (przypięcie rewizji HF) i `repoOverrides` (lustro) —
**nie testowałem** ich (nie znam hasha commita HF); do sprawdzenia w T3, jeśli chcemy pin na rewizję. Wersja HF „dziś” jest identyczna z kopią z 2026-10-19 (SHA-256 wag).

## 3. Tabela kryteriów (a)–(e)

| # | Kryterium | Wynik | Dowód (komenda → wynik) |
|---|---|---|---|
| (a) | `swift build` samymi CLT | **TAK** | Pakiet sondy `f20-s0/probe` (tools 6.0, platforma 15.0, jedna zależność FluidAudio 0.17.7): `swift package --disable-keychain resolve` → 5,5 s; `swift build --disable-keychain` (czysty, debug) → **Build complete, 1:30**; `swift build -c release` → **Build complete, 2:16**. Ostrzeżenia: jedyne to szum linkera (`search path '…/CommandLineTools/Developer/Library/Frameworks' not found`, `…/Developer/usr/lib`) i moje własne (`variable never mutated` w kodzie sondy, już naprawione). **Ostrzeżenia FluidAudio zmierzone osobno:** SwiftPM wycisza ostrzeżenia zależności w zwykłym buildzie, więc skompilowałem kopię checkoutu jako pakiet główny (`rsync` checkoutu do katalogu poza `.build`, `swift build --disable-keychain --target FluidAudio` → Build complete, 54 s; w `Package*.swift` brak `swiftLanguageMode`/`unsafeFlags`, czyli **tryb Swift 6**): **62 unikatowe ostrzeżenia** (76 linii z duplikatami), z czego **0 dotyczących współbieżności** (`Sendable`/izolacja/aktory/data race — dwa trafienia regexu to fałszywe, komunikat o sprawdzeniu dostępności macOS). Kategorie: 36× przestarzały interfejs CBLAS z Accelerate (deprecated w macOS 13.3), 6× `switch must be exhaustive`, 6× niewykorzystana inicjalizacja, 4× zbędne sprawdzenie dostępności, 4× niewykorzystany wynik, reszta drobna. W naszym buildzie te ostrzeżenia **nie pojawiają się** (SwiftPM je wycisza), więc `swift build` w repo nie dostanie szumu. Nasz kod wołający aktorów FluidAudio (`await manager.transcribe(… decoderState: &state …)`) kompiluje się w trybie 6 bez ostrzeżeń |
| (b) | `scripts/test.sh` z nową zależnością | **TAK** (po jednej poprawce, §3.1) | Na kopii repo: dodano `.package(url:…, exact: "0.17.7")`, cel `MeetNotesLocalASR` (importuje `FluidAudio`), cel testowy `MeetNotesLocalASRTests`, dopisano zależność do `MeetNotesApp`. `scripts/test.sh` (z 2 testami w nowym celu) → **`test.sh: 357/357 testów uruchomionych i zaliczonych`**, kod wyjścia 0, bez kodu 3 (plugin makr), `check-bundle: OK`. Czas 41 s (przyrostowo) / 2:14 (pierwszy przebieg z budową zależności). Ostrzeżenia w logu: wyłącznie istniejące w repo (`SystemAudioCheck.swift:51`, `MeetingTuningApplyingTests.swift:7`), nic z nowego modułu |
| (c) | `bundle.sh` + `otool -L` + start | **TAK** | Na kopii: `MEETNOTES_SIGN_IDENTITY=- MEETNOTES_APP=… scripts/bundle.sh` → `.app` złożona, `codesign --verify --strict` OK (ad-hoc — celowo, by nie sięgać po certyfikat „MeetNotes Dev” w pęku kluczy). Zawartość: `Info.plist`, `MacOS/MeetNotesApp` (39,96 MB, debug), `Resources/AppIcon.icns`, `_CodeSignature` — **bez `Frameworks/`**. `otool -L`: **zero bibliotek spoza `/usr/lib` i `/System/Library`**; zero wystąpień `.build` w zależnościach. (Istnieją wpisy `LC_RPATH` do `.build/out/Products/Debug/PackageFrameworks` — **takie same ma już dzisiejsza `.app` z repo**, to nie nowa zależność.) `NemoTextProcessing.xcframework` to **statyczna biblioteka Rust** zlinkowana do pliku wykonywalnego: w paczce nie ma żadnego osobnego pliku, `bundle.sh` nie wymaga zmian. Start: (1) `MeetNotesApp` uruchomiona z kopii `.app` z `MEETNOTES_DATA_DIR=<pusty temp>` żyła po 8 s (RSS 111 MB; zabita przeze mnie) — okno nie było oglądane; (2) ta sama `.app` w trybie sondy (zmienne `MEETNOTES_S0_*`) **załadowała Parakeet i przetranskrybowała WAV w środku paczki**: `OK samples=190514 words=23` (zdanie syntetyczne) oraz `words=82` na nagraniu mikrofonu 128 s |
| (d) | próbki `[Float]` 16 kHz → tekst + czasy słów | **TAK** | §4 — `AsrManager.transcribe(_:decoderState:language:)` → `ASRResult.tokenTimings` → `buildWordTimings(from:)`; spójność: `słowa złączone spacją == ASRResult.text` w **każdym** oknie (0 niezgodności) na zdaniu syntetycznym, mikrofonie 128 s i torze systemowym 128 s; czasy monotoniczne (`start ≤ end`, rosnące) |
| (e) | koszt dekodowania WAV, pierwsze uruchomienie, powtórne, pamięć, RTF | **zmierzone** | §6 |

### 3.1 Dlaczego (b) najpierw dał kod 4
Pierwszy przebieg na kopii dał `test.sh: uruchomiono 355 testów, a w Tests/ jest 356 deklaracji @Test. Wynik NIEWAŻNY` (kod 4), mimo że wszystkie testy przeszły:
nowy cel miał jeden test, a swift-testing pisze `Test run with 1 test in 0 suites` (liczba pojedyncza), czego `grep -oE 'Test run with [0-9]+ tests'` w `scripts/test.sh` nie łapie.
To **usterka skryptu, nie zależności**; po dodaniu drugiego testu 357/357. Dla T3: albo ≥ 2 testy w każdym nowym celu (T3 i tak ich ma), albo poprawka `tests?` (osobny, mały commit).

## 4. Jak z próbek `[Float]` powstają słowa z czasami (kryterium (d))

Przepływ w sondzie (i w `MeetNotesLocalASR` dla T4):

1. WAV 16 kHz mono Int16 (kontrakt `TranscriptionClient`, ten sam format, który buduje `WAVEncoder.wav`) → `[Float]` (`Int16 / 32768`) własnym dekoderem; pomija się nagłówek RIFF po szukaniu chunku `data` (nie zakładać 44 bajtów — `afconvert` pisze dłuższy nagłówek).
2. `var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)` — **nowy stan na okno** (okna są niezależne, tak jak dziś w runnerze).
3. `let r = try await manager.transcribe(samples, decoderState: &state, language: .polish)` → `ASRResult` (`text`, `confidence`, `duration`, `processingTime`, `tokenTimings: [TokenTiming]?`).
4. `TokenTiming` = `{ token: String, tokenId: Int, startTime, endTime: TimeInterval, confidence: Float }` — czasy **względem początku podanych próbek** (okna), w sekundach.
5. **Scalanie tokenów w słowa:** `buildWordTimings(from: r.tokenTimings ?? []) -> [WordTiming]` — funkcja **publiczna w FluidAudio** (nie piszemy własnej). Token zaczynający się od znacznika granicy słowa SentencePiece `▁` (lub spacji) otwiera nowe słowo, pozostałe doklejają się do bieżącego;
   słowo = od `startTime` pierwszego tokenu do `endTime` ostatniego; pomija `""`, `<blank>`, `<pad>`; znacznik `▁` jest zdejmowany. **Interpunkcja zostaje przyklejona do słowa** (`dobry,`, `kwartał,`, `15.30.`) — tak jak w `ASRResult.text`.
   `WordTiming = { word: String, startTime, endTime }` → mapowanie na nasze `TranscribedWord(word:start:end)`; przesunięcie o początek okna robi runner/adapter.
6. Przykład (zdanie syntetyczne, 11,78 s): `0.00–0.32 Dzień`, `0.32–0.88 dobry,`, `0.88–1.28 dzisiaj`, `1.28–1.92 omawiamy`, `1.92–2.32 budżet`, … `9.92–10.08 o`, `10.16–11.60 15.30.` (23 słowa). Model sam zapisał „piętnastej trzydzieści” jako `15.30.` — formatowanie liczb to cecha modelu, nie ITN.
7. `language:` — `FluidAudio.Language` (np. `.polish`, `"pl"`); wskazówka **tylko skryptowa** (filtr alfabetu Latin/Cyrillic w dekoderze, v3). Na nagraniu 128 s wynik z `pl` i bez wskazówki ma tę samą liczbę słów (68). Zgodnie ze specem to **nie** wiąże języka — strażnik z 1.5 zostaje.

## 5. Magazyn modelu (świeże pobranie tym samym pinem do pustego katalogu)

Pobrano `AsrModels.download(to: <pusty katalog>/parakeet-tdt-0.6b-v3, version: .v3, encoderPrecision: .int8)` — **dwukrotnie** (dwa puste katalogi; drugi raz po to, by zapisać zdarzenia postępu). Oba wyniki **bajt w bajt identyczne** (`diff -rq`). Źródło: `https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml` (`ModelRegistry.baseURL`: nadpisywalny zmiennymi środowiskowymi `REGISTRY_URL` / `MODEL_REGISTRY_URL`, a w kodzie `ModelRegistry.repoOverrides`).

**Katalog docelowy:** folder na dysku to **`<katalog nadrzędny>/parakeet-tdt-0.6b-v3`** (`Repo.folderName` zdejmuje `-coreml`). Argument `to:` jest interpretowany tak: *rodzic* tego URL-a = korzeń magazynu, a pliki idą do `<rodzic>/<folderName>`
(`repoPath(from:) = directory.deletingLastPathComponent().appending(folderName)`). Dlatego dla szwu testowego T3 wystarczy podać `…/magazyn/parakeet-tdt-0.6b-v3`; wartość zwracana to ten podany URL.
Nic nie zapisano poza katalogami testowymi (wspólny magazyn: `mtime` bez zmian, zawartość `ls` bez zmian — tylko odczyt).

Rozmiar: **483 257 242 B = 460,87 MiB = 483 MB** (spec: „461 MB” — zgodne w MiB), 23 pliki, `du` ≈ 470–480 MB.

```json
{
  "folder": "parakeet-tdt-0.6b-v3",
  "variant": "v3 / encoderPrecision int8 (Encoder.mlmodelc)",
  "totalBytes": 483257242,
  "files": [
    {"path": "Decoder.mlmodelc/analytics/coremldata.bin", "size": 243},
    {"path": "Decoder.mlmodelc/coremldata.bin", "size": 554},
    {"path": "Decoder.mlmodelc/metadata.json", "size": 3427},
    {"path": "Decoder.mlmodelc/model.mil", "size": 13110},
    {"path": "Decoder.mlmodelc/weights/weight.bin", "size": 23604992, "sha256": "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41"},
    {"path": "Encoder.mlmodelc/analytics/coremldata.bin", "size": 243},
    {"path": "Encoder.mlmodelc/coremldata.bin", "size": 485},
    {"path": "Encoder.mlmodelc/metadata.json", "size": 2921},
    {"path": "Encoder.mlmodelc/model.mil", "size": 959769},
    {"path": "Encoder.mlmodelc/weights/weight.bin", "size": 445187200, "sha256": "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"},
    {"path": "JointDecisionv3.mlmodelc/analytics/coremldata.bin", "size": 243},
    {"path": "JointDecisionv3.mlmodelc/coremldata.bin", "size": 521},
    {"path": "JointDecisionv3.mlmodelc/metadata.json", "size": 3453},
    {"path": "JointDecisionv3.mlmodelc/model.mil", "size": 11775},
    {"path": "JointDecisionv3.mlmodelc/weights/weight.bin", "size": 12642764, "sha256": "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e"},
    {"path": "Preprocessor.mlmodelc/analytics/coremldata.bin", "size": 243},
    {"path": "Preprocessor.mlmodelc/coremldata.bin", "size": 486},
    {"path": "Preprocessor.mlmodelc/metadata.json", "size": 2841},
    {"path": "Preprocessor.mlmodelc/model.mil", "size": 28181},
    {"path": "Preprocessor.mlmodelc/weights/weight.bin", "size": 491072, "sha256": "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"},
    {"path": "config.json", "size": 475, "sha256": "97f19ecccd0fdc730d76fb918090fa8bc64bce8ea4ad43715d5e9c2c7350db66"},
    {"path": "parakeet_v3_vocab.json", "size": 151122, "sha256": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"},
    {"path": "parakeet_vocab.json", "size": 151122, "sha256": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"}
  ]
}
```

Różnice względem modelu we wspólnym magazynie (`parakeet-tdt-0.6b-v3-coreml`, zapis 2026-10-19 14:10, starsza generacja biblioteki): nazwa folderu (`-coreml`), `JointDecision.mlmodelc` zamiast `JointDecisionv3.mlmodelc`; **SHA-256 wszystkich czterech `weight.bin` identyczne**,
`config.json` ten sam tekst. Czyli ten sam model, inne nazwy — i `modelsExist` tego nie rozpozna (§1 pkt 2).

**Czy pobieranie można skierować do podanego katalogu?** Tak (jw.). **Czy wraca od razu przy istniejącym modelu?** Tak: `AsrModels.download(to:)` na istniejącym magazynie zwróciło w **2,6 ms**, bez sieci (wcześniejsze `modelsExist` → `return`); `force: true` kasuje docelowy katalog i pobiera od nowa.
**Weryfikacja przy pobieraniu:** biblioteka porównuje rozmiar każdego pliku z rozmiarem z listingu HF (obsługuje wznawianie `If-Range`/ETag), **nie liczy hasha**; `modelsExist` sprawdza tylko obecność plików, `isModelValid` ładuje modele na `cpuOnly` (działa tylko dla domyślnego katalogu). Spec §4.2 jest tu zgodny z rzeczywistością.
**Czy `cleanup()` zwalnia pamięć?** Tak (§6): po załadowaniu 30,7 MB (baza 2,1 MB), po `cleanup()` 23,7 → 18,4 → **9,4 MB** w ciągu 6 s, o ile nikt inny nie trzyma struktury `AsrModels` (w sondzie z `models` żyjącym w zasięgu spadek był mniejszy: 109,7 → 54,8 MB, a w trybie całego pliku 89 → 89 MB). Dla T4: **nie przechowywać `AsrModels`** poza `loadModels`.

## 6. Pomiary (kryterium (e)); build **release**, o ile nie napisano inaczej

Materiał: nagrania z `.devdata/sessions` skonwertowane `afconvert` do WAV 16 kHz mono Int16 w scratchpadzie (tor mikrofonu 128,3 s i 569,2 s; tor systemowy 128,3 s) + zdanie syntetyczne 11,8 s. Treści nie drukowano.

| Pomiar | Wynik |
|---|---|
| **Dekodowanie WAV Int16 → `[Float]`** (prosta pętla, `Data` w pamięci) | **1,6 ms** dla 128 s audio, **7–8 ms** dla 569 s (~0,8 ms na okno 59 s). Wobec ~1,2 s transkrypcji okna to **< 0,1 %** → kontrakt `TranscriptionClient` (WAV) **zostaje**, bez zmiany runnera (spec §4.2 [moja decyzja] potwierdzona). (Uwaga: `WAVEncoder` mnoży przez 32767, więc dekoder powinien dzielić przez 32767, nie 32768 — różnica 3·10⁻⁵, bez znaczenia.) |
| **Świeże pobranie do pustego katalogu** (sieć + kompilacja) | **44,0 s** (1. raz), **40,1 s** (2. raz): listing HF 2,6 s, pobieranie bajtów ≈ 20 s (~23 MB/s), potem „compiling”: `Encoder` 17,6–21,6 s, pozostałe < 0,2 s |
| **Pierwsze ładowanie w nowym pliku wykonywalnym** (kompilacja ANE) — `AsrModels.load` | **18,8–19,4 s** (3 różne pliki wykonywalne: sonda debug, sonda release, kopia pliku), **20,3 s** w kopii `.app`; w tym czasie RSS dochodzi do **489–535 MB** |
| **Ponowne ładowanie** (ten sam plik wykonywalny) | **0,09 s** (nowy proces), **0,08–0,09 s** (kolejne cykle `load → cleanup → load` w jednym procesie), 0,64–0,74 s po przebudowie pliku o tej samej nazwie |
| `AsrManager.loadModels` po załadowaniu | 0,01 s |
| **Pierwsze `transcribe` po ciepłym ładowaniu** | 0,19 s (11,8 s audio); 0,4–1,3 s (okno 59 s) |
| **RTF / RTFx** (okna ≤ 59 s, jak runner) | mikrofon 128 s: **0,015–0,021** (RTFx 48–65); tor systemowy 128 s: 0,0094–0,0099 (RTFx 101–106); mikrofon 569 s (10 okien): **0,0122** (RTFx 82) |
| RTF, cały plik w jednym wywołaniu (`transcribe([Float])` dzieli wewnętrznie) | mikrofon 569 s: **0,0085** (RTFx 118), 4,83 s; liczba słów 1092 vs 1095 w oknach 59 s |
| Build debug (informacyjnie) | zdanie 11,8 s: RTFx 61 — debug jest użyteczny do testów, nie do pomiaru |
| **Pamięć szczytowa** (`/usr/bin/time -l`, „peak memory footprint”) | 66 MB (zdanie, debug) · 86 MB (128 s, okna) · **134 MB** (569 s, okna i cały plik); `maximum resident set size` 136–186 MB w ciepłych przebiegach, **489–535 MB tylko przy pierwszym ładowaniu** (kompilacja) |
| `cleanup()` | zob. §5 (spadek do ~9 MB w 6 s przy braku innych referencji) |

**Czego te liczby nie mówią:** liczniki procesu (`phys_footprint`, RSS) **nie obejmują pamięci rezydentnej na ANE/GPU** (wagi enkodera ~445 MB są mapowane/kopiowane przez CoreML poza tymi licznikami) — realny koszt unified memory modelu jest większy niż „134 MB”.
Nie mierzyłem go systemowo (`vm_stat`/`memory_pressure`). Do decyzji o profilu na 16 GB (spec §4.2, cykl życia) wystarczy rząd: **kilkaset MB na czas przebiegu**, zwalniane przez `cleanup()`.

**Ekstrapolacja kryterium 3.7 (`docs/plan.md`: 85 min ≤ 60 s) — to NIE pomiar** (najdłuższe nagranie, jakie mam, to 9,5 min): przy RTFx 82 w oknach 59 s wychodzi ~62 s, przy RTFx 48–65 — 78–106 s (**poza progiem**), przy całym pliku w jednym wywołaniu (RTFx 118) ~43 s.
Wniosek dla T1/T4: jeśli 3.7 ma obowiązywać, okno 59 s (zachowane dla wznawiania) może go nie spełniać; kosztem jest granularność wznawiania (spec §4.2: „rozważyć podniesienie, jeśli S1 pokaże zysk”).

**Pamięć podręczna ANE jest per plik wykonywalny:** `~/Library/Caches/<nazwa pliku>/com.apple.e5rt.e5bundlecache` (po ~77 MB na każdy z moich plików wykonywalnych). Pierwsze ładowanie w **każdym nowym pliku/ścieżce** to ~19 s, kolejne — 0,1 s. Dla aplikacji: cache jest pod identyfikatorem paczki
(`~/Library/Caches/io.github.sharezz1.meetnotes/…`), więc pierwsze uruchomienie transkrypcji po instalacji/zmianie ścieżki to ~20 s „Preparing model…” (spec §4.2 już to zakłada — „bywa kilka minut”: tu 20 s). Nie wiem, kiedy system ten cache wyrzuca (po aktualizacji systemu to na pewno).

## 7. Znaleziska wymagające decyzji lub uwzględnienia w T3/T4

### 7.1 Zawieszenie `swift package resolve` na `binaryTarget` (pęk kluczy)
- Objaw: po `Downloading binary artifact …NemoTextProcessing.xcframework.zip` SwiftPM wisi bez końca (obserwowane od ≥ 4 do 18 min do ręcznego przerwania, 5 prób: `swift build`, `swift package resolve` ×2, z osobnym `--cache-path`, z `traits: []`). `curl` i `URLSession` pobierają ten sam plik w 1,5–2,6 s, `lsof` nie pokazuje żadnego gniazda w procesie SwiftPM.
- Przyczyna (ze stosu wątku `swift-package`, `sample`): `SecItemCopyMatching → SecKeychainItemCopyContent → … → mach_msg` — SwiftPM wyszukuje poświadczenia hosta w **pęku kluczy macOS** i czeka na odpowiedź `securityd` (najpewniej niewidoczne dla agenta okno zgody; **nie sprawdzałem, czy okno było na ekranie, i niczego nie klikałem**).
- Obejście: `swift package --disable-keychain resolve` → `Downloaded … (4.14s)`, 5,5 s razem. Po tym zwykłe `swift build`/`scripts/test.sh`/`bundle.sh` działają (artefakt jest w `.build/artifacts`).
- Konsekwencja: (1) T3 w kroku z dodaniem zależności ma użyć `swift package --disable-keychain resolve`; (2) **na czystym klonie / po `rm -rf .build` (zalecane przy kodzie 3 `test.sh`)** artefakt trzeba pobrać ponownie. Zaobserwowałem zawieszenie wyłącznie wtedy, gdy artefaktu nie było jeszcze w globalnym cache SwiftPM, a każdy udany `resolve` szedł z `--disable-keychain`; **nie wiem**, czy zapełniony cache globalny (`~/Library/Caches/org.swift.swiftpm/artifacts`) omija ścieżkę pęku kluczy — celowo nie powtarzałem `resolve` bez flagi (każda próba to kolejne zapytanie do `securityd`). Ostrożnie: dopisać `--disable-keychain` do `CLAUDE.md` (Uruchamianie) i do kroku „kod 3: `rm -rf .build`”;
  (3) `scripts/*.sh` nie przekazują tej flagi — nie zmieniałem ich w spiku (decyzja do T3: albo dopisek w dokumentacji, albo `--disable-keychain` w `test.sh`/`bundle.sh`).

### 7.2 Magazyn wspólny a ten pin — decyzja użytkownika
Opcje: **(A, rekomendowana)** zostać przy pinie 0.17.7 i zaakceptować, że „Download” pobierze drugą kopię (461 MB) do `…/FluidAudio/Models/parakeet-tdt-0.6b-v3`; karta modelu w Settings pokazuje to wprost (rozmiar, lokalizacja), a stara kopia
`-coreml` zostaje dla innych aplikacji. **(B)** przypiąć starszy tag FluidAudio zapisujący `-coreml` — odradzam: starszy kod, `JointDecision` bez `v3`, inne API, nie sprawdzałem żadnego. **(C)** własny odczyt z folderu `-coreml` przez `AsrModels.loadLocal(from:…)` — nie zadziała bez zmiany nazwy pliku `JointDecision`
(biblioteka szuka `JointDecisionv3.mlmodelc`); nie robić. Spec §3.5/§4.2/§11.6 do poprawki: „gdy model już jest” dotyczy folderu `parakeet-tdt-0.6b-v3`.

### 7.3 Postęp pobierania (T3/T7)
`ProgressHandler = @Sendable (DownloadProgress) -> Void`, `DownloadProgress { fractionCompleted: Double; phase: DownloadPhase }`, `DownloadPhase = .listing | .downloading(completedFiles:, totalFiles:) | .compiling(modelName:)`. Zdarzeń było **7481** (jedno na kilkadziesiąt KB). Przebieg:
`listing` (0–2,6 s) → `downloading 0/23` z ułamkiem **0 → 0,5** (bajty; etykieta plików **nie rośnie**, zostaje `0/23`, potem `0/0`) → `compiling Preprocessor` 0,5 → 1,0 → **skok do 0,5** → `compiling Encoder` 0,5 → 1,0 (17,6 s) → skok → `Decoder` → skok → `JointDecisionv3` → 1,0. Czyli
**3 spadki ułamka**, a „pobrane” kończy się na 0,5. Adapter ma liczyć własny postęp: bajty (np. suma rozmiarów plików na dysku względem `totalBytes` z manifestu) dla fazy pobierania, a „Preparing model…” (nieokreślony) dla `compiling`; nie wystawiać surowego `fractionCompleted`.

### 7.4 Cecha `NemoTextProcessing` (opcjonalna oszczędność)
Tylko ITN/TTS używa tego silnika (`ITN/TextNormalizer.swift`, `TTS/*`); ścieżka ASR — nie. Można go wyłączyć: `.package(url:…, exact: "0.17.7", traits: [])` — wymaga **`swift-tools-version:6.1+`** w naszym `Package.swift` (dziś 6.0; `package(url:exact:traits:)` jest od 6.1). Zmierzone: plik wykonywalny sondy **10,3 MB zamiast 18,7 MB** (−8,4 MB), brak zależności dynamicznych w obu wariantach. **Ale `swift package resolve` i tak pobiera artefakt** (wariant `traits: []` — „Fetching binary artifact … from cache”, katalog w `.build/artifacts`), więc problem z 7.1 zostaje.
Rekomendacja: **nie wyłączać** (podnoszenie tools-version i zmiana semantyki zależności dla 8 MB; ASR działa tak samo). Wariant sprawdzony tylko do poziomu „buduje się i linkuje”, bez uruchamiania ASR.

### 7.5 Pozostałe uwagi
- **🔴 `AsrModels.load(from:)` potrafi pobierać** (z kodu, nie uruchamiałem, żeby nie pobierać): ładuje komponenty przez `ModelHub.loadModels(…)`, tę samą ścieżkę, której używa `download`; brakujący komponent (np. skasowany plik) zostałby dociągnięty z HF **bez pytania** —
  to wprost anty-cel „pobieranie bez zgody”. **Adapter ma używać `AsrModels.loadLocal(from:version:encoderPrecision:)`** („bez pobierania i bez rozwiązywania repozytorium; brakujące pliki kończą się błędem lokalnie”). Sprawdzone: na magazynie z usuniętym `JointDecisionv3.mlmodelc`
  `loadLocal` rzuca natychmiast `AsrModelsError.modelNotFound("JointDecisionv3.mlmodelc", <URL>)`; na pełnym magazynie ładuje w 0,09–0,34 s (ciepło) i daje identyczny wynik (68 słów, 0 niezgodności słów z tekstem, RTFx 43–58 w okna 59 s na tym samym 128 s nagraniu). Pobieranie tylko przez `download(to:…)` po akcji użytkownika.
- **Parakeet v3 na PL jest użyteczny** na nagraniach 128–569 s (liczba słów rozsądna, zdanie syntetyczne zapisane poprawnie z polskimi znakami). **Jakości względem `mai-transcribe-2` nie oceniałem** (to S1); cisza/halucynacje, para PL+EN — S1.
- Plik testowy `scripts/test.sh` kasuje stare `mn-*` w `$TMPDIR` — nie dotyczy spiku.

## 8. Lista API FluidAudio dla `FluidAudioEngine` (T3/T4) — dokładne nazwy z 0.17.7

Zweryfikowane kompilacją i uruchomieniem w sondzie i w kopii `.app`. Wszystko w module `FluidAudio` (`import FluidAudio`), w repo importować **tylko** w `MeetNotesLocalASR`.

```swift
import FluidAudio
import CoreML   // tylko jeśli potrzebny MLComputeUnits/MLModelConfiguration; domyślnie niepotrzebny

// --- wersja i precyzja (pin) ---
let version: AsrModelVersion = .v3
let precision: ParakeetEncoderPrecision = .int8          // .int8V2, .int4 istnieją

// --- magazyn ---
AsrModels.defaultCacheDirectory(for: .v3) -> URL          // …/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3
AsrModels.modelsExist(at: URL, version: .v3, encoderPrecision: .int8) -> Bool   // tylko OBECNOŚĆ plików; at: = <korzeń>/parakeet-tdt-0.6b-v3
ModelNames.ASR.requiredModelsV3(precision: .int8) -> Set<String>  // ["Preprocessor.mlmodelc","Encoder.mlmodelc","Decoder.mlmodelc","JointDecisionv3.mlmodelc"]

// --- pobranie (TYLKO po akcji użytkownika) ---
@discardableResult
try await AsrModels.download(
    to: URL?,                          // rodzic = korzeń magazynu; pliki w <rodzic>/parakeet-tdt-0.6b-v3
    force: Bool = false,               // true = kasuje katalog docelowy
    version: AsrModelVersion = .v3,
    encoderPrecision: ParakeetEncoderPrecision = .int8,
    progressHandler: ProgressHandler? = nil   // @Sendable (DownloadProgress) -> Void; uwagi w §7.3
) -> URL

// --- ładowanie: TYLKO loadLocal (bez sieci, brak pliku = błąd lokalny) ---
let models = try AsrModels.loadLocal(          // synchroniczne, throws; ciepło 0,09–0,34 s, zimno ~19 s (ANE)
    from: URL,                         // <korzeń>/parakeet-tdt-0.6b-v3 (to samo, co `to:` w download)
    version: AsrModelVersion = .v3,
    configuration: MLModelConfiguration? = nil,
    encoderPrecision: ParakeetEncoderPrecision = .int8,
    encoderComputeUnits: MLComputeUnits? = nil)   // rzuca AsrModelsError.modelNotFound(nazwa, URL) / .loadingFailed(String)
// NIE używać AsrModels.load(from:…) ani downloadAndLoad: przechodzą przez ModelHub.loadModels i mogą dociągać brakujące pliki z HF (§7.5)

// --- transkrypcja ---
let manager = AsrManager(config: ASRConfig = .default, models: AsrModels? = nil)   // actor
try await manager.loadModels(models)               // 0,01 s po load; NIE przechowywać `models` dalej
let layers = await manager.decoderLayerCount       // Int (2 dla v3)
var state = TdtDecoderState.make(decoderLayers: layers)        // nowy na okno
let r: ASRResult = try await manager.transcribe(samples /* [Float] 16 kHz mono */,
                                                decoderState: &state,
                                                language: Language? = nil)   // np. .polish; tylko filtr skryptu
// r.text, r.confidence, r.duration, r.processingTime, r.rtfx, r.tokenTimings: [TokenTiming]?
// TokenTiming { token, tokenId, startTime, endTime, confidence }

// --- słowa z czasami ---
let words: [WordTiming] = buildWordTimings(from: r.tokenTimings ?? [])   // WordTiming { word, startTime, endTime } — funkcja publiczna

// --- zwolnienie ---
await manager.cleanup()                            // asrModels = nil, czyści cache MLArray; pamięć spada, jeśli nikt nie trzyma AsrModels
// błędy: ASRError (.notInitialized, .invalidAudioData [< 300 ms audio], .processingFailed(String), .modelLoadFailed, …)
```

Mapowanie na repo: `LanguageCode.rawValue` → `Language(rawValue:)` (`nil` dla nieobsługiwanego → przekazać `nil` i polegać na strażniku); `WordTiming` → `TranscribedWord(word:, start:, end:)`; `r.text` zgodny ze słowami złączonymi spacją (0 niezgodności w pomiarach), więc `TranscriptionResult.text` można brać z `r.text`.
Minimalne audio: < 300 ms → `ASRError.invalidAudioData` (nie sprawdzałem zachowania na ciszy/krótkich oknach; `EnergyGate` i tak odsiewa ciszę przed wysyłką).

Wersja biblioteki w czasie działania: **brak publicznej stałej** (nie znalazłem `version`/`libraryVersion`) — odcisk modelu (`modelFingerprint`) i `Package.resolved` są jedynym śladem; wersję biblioteki zapisać stałą w adapterze (`"0.17.7"`) i pilnować testem zgodności z `Package.resolved`.

## 9. Czego NIE zweryfikowano

- Okna GUI aplikacji (nie oglądano; tylko proces żyje 8 s i tryb sondy w `.app`), brak testu z podpisem „MeetNotes Dev” (celowo ad-hoc, bez dotykania pęku kluczy).
- Pamięć rezydentna na ANE (§6), zachowanie po restarcie systemu / wyrzuceniu cache ANE (czy ~19 s wraca po aktualizacji systemu — zakładam, że tak).
- Jakość PL względem `mai-transcribe-2`, cisza/halucynacje, para PL+EN, `.int8` vs `.int8V2` (S1).
- Kryterium 3.7 (85 min) — tylko ekstrapolacja z 9,5 min.
- `ModelRegistry.revisionOverrides` (przypięcie rewizji HF), zachowanie `download` przy braku sieci i przy przerwanym pobraniu (wznawianie `If-Range` jest w kodzie, nie wykonywałem).
- Zachowanie przy `traits: []` poza zbudowaniem i zlinkowaniem.
- **Pobranie → pierwsze ładowanie w jednym, niezmienionym pliku wykonywalnym:** sondę przebudowano między `download` a `run`, więc nie wiem, czy użytkownik po ~40 s pobierania płaci jeszcze raz ~19 s kompilacji ANE przy pierwszym `loadLocal`
  (kompilacja `Encoder` w trakcie `download` ~18–22 s prawdopodobnie rozgrzewa cache dla tego pliku, ale nie sprawdzałem) — ma znaczenie dla tekstu „Preparing model…” w T7.
- Start GUI kopii `.app` użył **prawdziwego identyfikatora paczki** (`io.github.sharezz1.meetnotes`), więc dzielił domenę `UserDefaults` i katalog cache z aplikacją użytkownika; uruchomiona z pustym `MEETNOTES_DATA_DIR`, bez interakcji, podpis ad-hoc, zabita po 8 s.
  Cache ANE założony w tym katalogu usunięto (niżej).
- Dwukrotne pobranie modelu (§5) było jedynym „dodatkowym” pobraniem ponad jedno wymagane — drugie po to, by zapisać zdarzenia postępu; oba do pustych katalogów w scratchpadzie.
- Ślady poza scratchpadem: cache SwiftPM (`~/Library/Caches/org.swift.swiftpm`, repozytorium FluidAudio ~370 MB + artefakt xcframework) — **zostawiony** (zwykły cache narzędzia). Cache ANE/URL, który założyły moje pliki wykonywalne
  (`~/Library/Caches/probe`, `probe-copy`, `t` oraz `…/io.github.sharezz1.meetnotes/com.apple.e5rt.e5bundlecache` założony przez kopię `.app` 2026-10-20 02:01) — **usunięty**. Wspólny magazyn FluidAudio, pęk kluczy, TCC, Ustawienia systemowe — nietknięte.

## 10. Jak powtórzyć (poza repo)

```
# pakiet sondy: Package.swift = tools 6.0, platforms [.macOS("15.0")], .package(url: FluidAudio, exact: "0.17.7")
swift package --disable-keychain resolve            # BEZ flagi pierwsze pobranie binaryTarget może zawisnąć (§7.1)
swift build -c release --disable-keychain
probe download <pusty_katalog>                       # AsrModels.download(to: <pusty>/parakeet-tdt-0.6b-v3, .v3, .int8)
probe run <katalog> <plik.wav 16 kHz mono Int16> pl 59   # okna 59 s; wypisuje tylko metryki
probe exists|unload|reload|paths <katalog>           # czas download przy istniejącym modelu / cleanup / cykl load-cleanup-load / modelsExist (tylko odczyt)
# kopia repo: rsync -a --exclude .build --exclude .devdata --exclude .git ./ <scratchpad>/repo-copy/; w niej: Package.swift + cel MeetNotesLocalASR (+2 testy),
# swift package --disable-keychain resolve && scripts/test.sh ; MEETNOTES_SIGN_IDENTITY=- MEETNOTES_APP=… scripts/bundle.sh
```
