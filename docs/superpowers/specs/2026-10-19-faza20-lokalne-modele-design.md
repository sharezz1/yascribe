# Faza 2.0 „Lokalne modele" — design

> Status: **po recenzji F20 (`docs/superpowers/reports/F20-recenzja-design.md`), do przeglądu użytkownika**, 2026-10-20 (pierwsza wersja 2026-10-19). Powstał w wątku brainstormingu; decyzje
> użytkownika w §3 są dosłowne, wszystko oznaczone **[moja decyzja]** to wybór autora do
> sprawdzenia. Następny krok po akceptacji: plan w `docs/superpowers/plans/` (skill writing-plans).
> **Kodu aplikacji nie piszemy do akceptacji speca i planu.** Spiki S0–S2 (§7) to pomiary, nie kod produktu.
> **2026-10-20: S0 wykonany — GO dla 2.0a** (`docs/superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md`); §13 rozstrzygnięty przez Opusa z delegacji
> użytkownika (`docs/superpowers/reports/F20-decyzje-opusa.md`), a §3.5, §4.2, §4.3, §7, §11.6, §11.7, §11.10 poprawione według faktów z S0.
> **2026-10-20: S2 wykonany** (`docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md`, commit `38ac47f`); wartości i kształt 2.0b rozstrzygnął Opus
> z delegacji użytkownika — **§14** (zastępuje „jeden `inputChars`” z §11.9 i wykrywanie przez `/api/show` z §5.2/§11.1).
>
> Wejścia: `docs/wymagania.md` §0, §2, §4; `docs/superpowers/ROADMAP.md` (sekcje „Faza 2", „Nieprzypisane");
> spec 1.5 (decyzja 20, §10); kod: `Sources/MeetNotesProviders/{Provider,Preset,Probe,ProviderSetup,OpenAICompatibleClient}.swift`,
> `Sources/MeetNotesTranscription/{TranscriptionRunner,Transcript,LanguageGuard}.swift`,
> `Sources/MeetNotesNotes/{Corrector,NoteGenerator}.swift`. Przegląd aplikacji open source: §9.
> Interfejs aplikacji po angielsku; opisy w repo po polsku.

## 1. Cel

Dodać **lokalną ścieżkę obok API**, nie zamiast niego: transkrypcja na tym Macu (Parakeet) oraz
korekta i podsumowanie lokalnym modelem tekstowym. Użytkownik wybiera w presecie, rola po roli,
czy dana rola idzie do API, czy lokalnie. Obie ścieżki mają działać równorzędnie i pozostać
wymienne bez zmian w reszcie aplikacji (nagrywanie, szablony, notatki, kalendarz).

Kryterium sukcesu (sprowadzone do testu na sprzęcie): przy wyłączonej sieci nagrywam spotkanie
PL, aplikacja je transkrybuje (Parakeet), poprawia i robi notatkę lokalnym modelem; ten sam
preset z rolami przestawionymi na API daje ten sam przebieg bez innych zmian.

Powód („dlaczego lokalnie") nie jest częścią tego speca — to osobna funkcja obok API, a nie
odpowiedź na konkretną usterkę API.

## 2. Cele, nie-cele, anty-cele

**Cele**
- **2.0a** — lokalny ASR: Parakeet TDT v3 w procesie przez FluidAudio, jako nowy rodzaj dostawcy
  wybieralny w presecie jak OpenRouter czy ElevenLabs; pobieranie modelu z zarządzaniem w Settings.
- **2.0b** — lokalny model tekstowy dla ról korekty i podsumowania przez serwer lokalny:
  **Ollama, llama.cpp (`llama-server`) albo oMLX**. Dobra obsługa „serwer nie działa", czasów
  odpowiedzi i małych okien kontekstu (§5).
- Zostawić furtkę na wbudowany model (§8) bez budowania go teraz.

**Nie-cele (nie w 2.0)**
- **Wbudowany model tekstowy pobierany i uruchamiany przez aplikację** (llama-server jako sidecar
  zarządzany przez aplikację) → **2.1 albo dalej**, decyzja użytkownika; nie priorytet.
- Diaryzacja lokalna, słownik/word boosting, transkrypt na żywo, AEC offline, Cohere Transcribe
  lokalnie, dyktowanie — zostają w ROADMAP pod swoimi numerami.
- Embeddingi lokalne dla archiwum (faza 3).
- Zmiana kształtu danych na dysku poza opcjonalnymi polami (lekcja E6).

**Anty-cele (porażka, nawet gdy „działa")**
- 🔴 **Ciche przełączenie na API przy awarii lokalnej.** Gdy lokalna rola zawiedzie, przebieg
  kończy się widocznym błędem lub jawną luką; użytkownik sam wybiera ponowienie innym presetem.
  Nic z lokalnej roli nie wychodzi do chmury bez jego decyzji.
- 🔴 **Pobieranie modelu bez zgody** (rozmiar i źródło widoczne przed startem; nigdy w tle przy starcie aplikacji).
- 🔴 **Zmyślone treści wyglądające na wiedzę** (W§2): lokalny ASR nie może obejść strażnika języka;
  lokalny model korekty nie może przemycić zmian poza bramką `CorrectionRules.accepts`.
- Ciche obcięcie transkryptu przez małe okno kontekstu modelu (Ollama domyślnie ~4k tokenów) —
  notatka „z początku spotkania" udająca całość.

## 3. Decyzje użytkownika (dosłownie)

1. „wersja lokalna ma być osobną funkcjonalnością obok API" (2026-10-19).
2. Kolejność: najpierw lokalny Parakeet dla transkrypcji, potem lokalny model do poprawiania
   tekstu i pisania summary; razem „faza 2.0".
3. „2.0b to ollama lub oMLX. ale nie chcę zamykać sobie furtki żeby ściągać i używać jakiegoś innego modelu."
4. „w fazie 2.1 albo dalszej. to nie jest priorytet. w 2.0 będziemy używali lokalnego ollama, albo llama.cpp, albo oMLX."
5. Aplikacja pobiera model lokalnego ASR sama, po zgodzie użytkownika. **Stan dysku 2026-10-20 (sprawdzony):** w magazynie FluidAudio leży
   `parakeet-tdt-0.6b-v3-coreml` (461 MB, komplet, zapis 2026-10-19 14:10), a także v2 i `parakeet-eou-streaming`; użytkownik wspominał, że model
   usunął — ktoś lub coś pobrało go ponownie. Spec **nie zakłada** ani obecności, ani braku modelu (patrz §4.2, szew testowy).
   **Poprawka po S0 (§7.2 raportu):** ta kopia pochodzi ze starszej generacji FluidAudio (folder `-coreml`, plik `JointDecision.mlmodelc`); przypięta
   wersja 0.17.7 szuka `parakeet-tdt-0.6b-v3` z `JointDecisionv3.mlmodelc`, więc dla aplikacji model na tej maszynie **nie istnieje** (status `missing`),
   mimo że wagi są bajt w bajt te same. Pierwsze „Download” pobierze drugą kopię (483 MB = 461 MiB) — decyzja w §13, pkt 3.

## 4. 2.0a — lokalny ASR (Parakeet przez FluidAudio)

### 4.1 Szew w kodzie (stan zbadany 2026-10-19)
`TranscriptionRunner` przyjmuje `any TranscriptionClient` (`transcribe(wav:model:language:shape:)`),
a `Provider.api` wybiera klienta (`OpenAICompatibleClient` albo `ElevenLabsClient`). `LanguageHandling.filtered`
już istnieje i w komentarzu wskazuje „Parakeet przez FluidAudio — faza 2". Okna, bramka energii,
filtr echa/przesłuchu, scalanie i wznawianie chunków **nie zmieniają się**.

### 4.2 Zakres
- `ProviderKind.fluidAudio` (nowa wartość; `Provider.kind` jest już opcjonalne — E6). Wiersz w Settings
  „On this Mac · Parakeet" jako gotowy dostawca (`ProviderPreset`), bez klucza i bez adresu
  (`baseURL` techniczny, np. `local://fluidaudio` **[moja decyzja]**, bo `Provider.baseURL` jest wymagane).
- **Miejsca w kodzie, które nowy rodzaj dostawcy zmienia (nie tylko enum):**
  1. `AppModel.providerWithKey` — bramka „brak klucza" dziś wpuszcza tylko OpenAI-compatible na `localhost/127.0.0.1/::1`; host `fluidaudio`
     by ją **oblał** i przebieg by nie powstał. Zmiana: **jeden** predykat „nie wymaga klucza" (loopback + `*.localhost` z §11.5 **albo** `.fluidAudio`),
     zamiast drugiej listy hostów.
  2. `AppModel.loadModels` — gałąź jak dla ElevenLabs: stała lista (`parakeet-tdt-0.6b-v3`), bez sieci.
  3. `ProviderPreset.ready`/`matching` — rozpoznanie po `kind`, nie po adresie; bez tego zapisany dostawca pokaże się drugi raz jako „Custom".
  4. `ProbeRunner.textClient` (`as? OpenAICompatibleClient`) zostaje `nil` dla klienta lokalnego: sonda korekty/notatki powie „does only speech-to-text"
     — to **pożądane**, nie „naprawiać".
- **Izolacja zależności:** FluidAudio występuje **wyłącznie** w jednym nowym module adaptera (kryterium 3.9 z `docs/plan.md` §3); reszta aplikacji
  widzi tylko `TranscriptionClient`. Ułatwia też S0 i `scripts/test.sh`.
- Klient lokalny implementujący `TranscriptionClient`: audio jako WAV (kontrakt klienta) dekodowany do próbek
  16 kHz i przekazany do FluidAudio; wynik → `TranscriptionResult` ze znacznikami słów (czasy z tokenów).
  Kształt `audioTranscriptions`. Nie robić zmiany kontraktu runnera, jeśli dekodowanie WAV okaże się
  wystarczająco tanie (pomiar w S0) **[moja decyzja]**.
- Okna zostają ≤59 s mimo braku limitu lokalnie — ziarno wznawiania i brak zmiany runnera **[moja decyzja]**;
  rozważyć podniesienie, jeśli pomiar S1 pokaże zysk jakości na dłuższych oknach. **Decyzja §13 pkt 2:** w 2.0a okna zostają 59 s także przy
  ryzyku przekroczenia celu 3.7 (S0 ekstrapoluje 62–106 s dla 85 min na jednym torze); czas jest mierzony i raportowany, nie bramkuje.
  Okno krótsze niż 300 ms (FluidAudio rzuca `invalidAudioData`) daje pusty wynik, nie lukę.
- **Język:** Parakeet v3 wykrywa język sam (25 języków europejskich, w tym PL). Zgodnie z W§2 ścieżka dostaje jawny
  język z presetu, a strażnik języka z 1.5 (`Merger` woła `LanguageGuard` zawsze, gdy `language != nil`) pilnuje wyniku. Wskazówka języka w FluidAudio
  jest tylko **skryptowa** (odsiewa tokeny spoza alfabetu), więc nie odróżnia PL od EN — „dekoder przycina wynik" znaczy tylko to.
  **`ProbeRunner.probe` dla `provider.kind == .fluidAudio` ustawia `LanguageHandling.filtered` bez klasyfikacji** **[moja decyzja]** (dzisiejsza
  `classifyLanguage` nie zwraca `.filtered` nigdy, a bez tej gałęzi badge pokazałby „can't be enforced" wbrew temu speca). „Auto" nadal tylko
  awaryjnie i z ostrzeżeniem.
- **Zarządzanie modelem** (Settings → karta modelu, wzór: Meetily `meetily-modele-lokalne.png`; mechanika po FluidVoice
  `PrivateAIModelArtifact`): nazwa, rozmiar (**483 MB = 461 MiB**, z `ModelManifest.totalBytes`, nie na sztywno), „Download" / pasek postępu / „Ready" / „Remove";
  lokalizacja w magazynie FluidAudio (`~/Library/Application Support/FluidAudio/Models`, wspólny z innymi aplikacjami), folder modelu
  **`parakeet-tdt-0.6b-v3`** (nazwa narzucona przez pin 0.17.7). Brak modelu = preset
  z lokalnym ASR nie startuje przebiegu i mówi dlaczego, z przyciskiem pobrania. Gdy model już jest **w folderze `parakeet-tdt-0.6b-v3`**, „Download" nic
  nie robi — upstream wraca od razu przy `modelsExist` (S0: 2,6 ms). **Poprawka po S0:** kopia `parakeet-tdt-0.6b-v3-coreml` (starsza generacja
  biblioteki, dziś na tej maszynie) **nie** jest rozpoznawana ani używana i zostaje nietknięta; karta mówi to wprost (§13, pkt 3).
  **Ładowanie wyłącznie `AsrModels.loadLocal(from:)`** (brak pliku = błąd lokalny, zero sieci); `AsrModels.load(from:)` i `downloadAndLoad` potrafią po
  cichu dociągać brakujące pliki z HF — zakazane (anty-cel „pobieranie bez zgody”). Pobieranie wyłącznie `AsrModels.download(to:)` po akcji użytkownika.
  **Postęp pobierania** liczy adapter (surowy `fractionCompleted` FluidAudio spada 3× — S0 §7.3): faza pobierania przeskalowana i monotoniczna,
  kompilacja jako nieokreślone „Preparing model…”.
  **Integralność [moja decyzja, potwierdzona S0]:** upstream sprawdza tylko *obecność* plików, nie hash, więc nie obiecujemy sumy kontrolnej „z API". Karta modelu
  pokazuje nazwę, rozmiar i wariant („Multilingual"); przy ładowaniu porównujemy listę plików i rozmiary z przypiętym manifestem (S0 §5: 23 pliki,
  483 257 242 B; pliki nadmiarowe — np. inny enkoder innej aplikacji — są ignorowane) (kryterium 3.8: podmieniony plik → odmowa z przyczyną).
  **Znany sufit:** podmiana o identycznym rozmiarze nie jest wykrywana; rewizja HF nie jest przypięta (`"main"`), więc zmiana modelu upstream kończy się
  po świeżym pobraniu widocznym błędem „differs from the version this build expects” (nie „corrupted”), nigdy cichym użyciem innego modelu.
  **Szew testowy [moja decyzja]:** katalog magazynu wstrzykiwany do adaptera (domyślnie wspólny), żeby ścieżki „brak modelu / pobieranie / błąd" dało się
  odebrać bez kasowania 461 MB z wspólnego magazynu.
- **Migawka przebiegu:** `RunSnapshot`/`RunInput` dostają **opcjonalne** pole `modelFingerprint` (rozmiary + hash `config.json`), żeby wznowienie po
  zmianie modelu w magazynie przez inną aplikację nie mieszało okien z dwóch modeli w jednym transkrypcie (E6: tylko pola opcjonalne).
- **Cykl życia:** model ładowany na początku przebiegu i zwalniany po jego zakończeniu **[moja decyzja]**. Właściciel: klient lokalny jest `actor`em
  trzymającym `AsrManager` z `load()`/`unload()` (FluidAudio ma `cleanup()`), a `AppModel.transcribe` woła `unload` w `defer`; alternatywa „model żyje
  tyle co aplikacja" odpada ze względu na profil pamięci na 16 GB.
  pierwsze uruchomienie po pobraniu może długo kompilować się na ANE („Preparing model…" — to nie jest zawieszenie). **Zmierzone w S0:** ~19–20 s na M4
  przy pierwszym `loadLocal` w danym pliku wykonywalnym/identyfikatorze paczki (cache ANE ~77 MB w `~/Library/Caches/<id>/`; zapewne wraca po
  aktualizacji systemu), potem ~0,1 s; tekst UI zostaje ostrożny („up to a minute”). `loadLocal` jest synchroniczne — poza MainActor. Nie trzymać
  `AsrModels` po `AsrManager.loadModels`, inaczej `cleanup()` nie zwalnia pamięci (S0 §5).
- **Sonda i karta modelu:** sonda ASR (istniejący `ProbeRunner` na klipach) działa na lokalnym kliencie bez zmian
  koncepcyjnych; wynik pokazany jak dla API (works, kształt, obsługa języka).
- **Migawka przebiegu** (`RunSnapshot`) zapisuje dostawcę i model jak zawsze; w razie potrzeby nowe pola tylko opcjonalne.

### 4.3 Ryzyka do zmierzenia przed planem (S0, S1 w §7)
Znane już z recenzji F20: FluidAudio upstream jest **Apache-2.0**, deklaruje `.macOS(.v14)` (bez konfliktu z naszym 15.0) i zwraca `ASRResult`
z czasami tokenów. Zostaje do zmierzenia: czy buduje się samymi Command Line Tools pod Swift 6.4 i z jakimi ostrzeżeniami współbieżności; czy
`scripts/bundle.sh` (kopiuje wyłącznie binarkę, bez `Frameworks/`) poradzi sobie z jego `binaryTarget` (`NemoTextProcessing.xcframework`); jakość PL (WER na korpusie spotkań) vs `mai-transcribe-2`; halucynacje na ciszy;
zachowanie na mieszanym PL+EN (powiązane z niezamkniętym pomiarem T11).
**Wynik S0 (2026-10-20):** build samymi CLT — tak (0 ostrzeżeń współbieżności FluidAudio, a SwiftPM i tak wycisza ostrzeżenia zależności); `bundle.sh` — bez
zmian (xcframework to statyczna biblioteka w pliku wykonywalnym, `otool -L` czysty); pierwsze `swift package resolve` wisi na pęku kluczy bez
`--disable-keychain` (§13, pkt 4). Jakość PL, cisza i PL+EN zostają dla S1.

## 5. 2.0b — lokalny model tekstowy (Ollama / llama.cpp / oMLX)

### 5.1 Szew w kodzie
`Corrector` i `NoteGenerator` biorą `OpenAICompatibleClient` — a wszystkie trzy serwery mówią po `/v1/*`,
więc **lokalny model to zwykły `Provider` z adresem `localhost`**, bez nowego typu klienta (zgodnie z komentarzem w kodzie
o odstępstwie od natywnego dialektu Ollamy). Istnieje już `ProviderPreset.ollama`. Praca polega na obsłudze lokalności,
nie na nowym transporcie.

### 5.2 Zakres
- **Gotowi dostawcy w Settings:** Ollama (`http://localhost:11434/v1`, istnieje), **llama.cpp** (`http://localhost:8080/v1`,
  domyślny port `llama-server`), **oMLX** (`http://localhost:8000/v1` — domyślny port z `~/Library/Application Support/oMLX/config.json`
  na tej maszynie, **do potwierdzenia w S2**). Bez klucza; w opisie „correction and summary", ASR zostaje do sondy (autorytet, nie deklaracja).
  „Custom endpoint" dalej pozwala na dowolny inny serwer lub model — to jest furtka z decyzji 3.
- **Lokalność jako własność dostawcy:** `isLocal` wyprowadzane z adresu (loopback) **[moja decyzja]**; używane przez UI
  (znacznik „On this Mac" przy roli, „Fully local" na presecie, gdy wszystkie role lokalne) i do rozsądnych limitów czasu.
- **Serwer nie działa / model nie załadowany:** wykrywanie i czytelny komunikat z nazwą serwera i podpowiedzią (jak uruchomić),
  nie surowy błąd sieci; w Settings przycisk „Check" (lista modeli z `/v1/models`, istniejące odkrywanie + sonda).
- **Limity czasu — dwa, oba do podniesienia:** miękki (`withDeadline`: `NoteGenerator.timeout` 180 s, `Corrector.batchTimeout` 120 s) **i transportowy**.
  `OpenAICompatibleClient.request` ma `timeoutInterval` 120 s mierzony jako bezczynność łącza, a `chat` używa domyślnej wartości; przy odpowiedzi
  niestreamowanej serwer milczy do końca generacji, więc lokalny 8B stuknie 120 s **przed** limitem miękkim. Zmiana: `chat(model:system:user:timeout:)`
  (limit transportowy wyższy od miękkiego) **[moja decyzja]**; wartości z S2, który mierzy też **czas do pierwszego bajtu**.
- **Modele „thinking":** wiele lokalnych modeli (Qwen, DeepSeek) zwraca blok rozumowania. Odpowiedź czatu musi zostać oczyszczona
  (`<think>…</think>` i pole `reasoning_content`), żeby nie trafiło do notatki ani nie zepsuło parsowania numerowanych linii korekty.
  Kod dziś tego nie obsługuje.
- **Małe okno kontekstu** (anty-cel): dla ról lokalnych transkrypt dłuższy niż budżet modelu jest **dzielony na części (map-reduce)**
  dla podsumowania; korekta już dzieli na partie po znakach (`CorrectionBatches`). To realizuje punkt ROADMAP „Długie transkrypty"
  z fazy 2 (spec 1.5, decyzja 20). Źródło budżetu: wykryty kontekst modelu, gdy serwer go podaje (Ollama `/api/show`, llama.cpp `/props`),
  w przeciwnym razie nastawialny, konserwatywny domyślny **[moja decyzja]**. **Zasady (z recenzji F20):** (1) **jeden** mechanizm budżetu dla korekty
  i notatki — `Corrector.maxBatchChars` (dziś 6000 znaków ≈ 2–3 tys. tokenów, za dużo przy `num_ctx` Ollamy ~4k, a po obcięciu `parse` odrzuca całą
  partię) wyprowadzany z tego samego limitu co podział notatki; (2) dla Ollamy budżet = `num_ctx` ustawiony przez użytkownika, bo `/api/show` zwraca
  maksymalny kontekst **modelu**, nie efektywny; (3) wykrywanie może budżet tylko **obniżyć**, nigdy podnieść ponad domyślny; (4) `/api/show` i `/props`
  leżą poza `/v1`, a `Provider.baseURL` zawiera `…/v1` — plan musi to uwzględnić. Czy Ollama obcina wejście po cichu — dziś założenie, rozstrzyga S2.
  **[po S2 — §14]** Ollama **nie** obcina wejścia (HTTP 400 „exceeds the available context size”); ciche obcięcie jest po stronie **wyjścia**
  (HTTP 200, `finish_reason: "length"`). `/api/show` zwraca maksimum modelu, więc odpada; źródła efektywnego kontekstu: Ollama `/api/ps`, llama.cpp `/props`.
  Zasada (1) „jeden mechanizm” zostaje, ale z dwiema regułami rezerwy (§14 pkt 4).
  Bez map-reduce dla API.
- **Jakość:** `CorrectionRules.accepts` (bramka numerów i zmian) i generowanie notatki zostają bez zmian; małe modele będą częściej
  odrzucane — licznik odrzuceń widoczny jak dziś, bez „łatania ślepo".
- Preset może mieszać: ASR lokalny + notatka w API i odwrotnie (role są niezależne — `RoleAssignment` per rola).

## 6. Zakres UI (skrót; szczegóły w planie, z zachowaniem języka wizualnego B — `docs/design/macos.md` §11)
- Settings → Providers: nowy wiersz „On this Mac · Parakeet" (ze stanem modelu), llama.cpp i oMLX w liście gotowych; „Check" dla serwerów lokalnych.
- Edytor presetu: znacznik lokalności przy roli, ostrzeżenie przy braku modelu/serwera, plakietka „Fully local".
- Karta spotkania/notatki: pokazuje, że przebieg był lokalny (jak dziś nazwa modelu/dostawcy), i czytelny błąd zamiast cichego fallbacku.
- Interfejs po angielsku.

## 7. Kolejność, spiki i bramki (STOP należy do użytkownika)

| Krok | Zawartość | Wynik |
|---|---|---|
| **S0** (spike, throwaway) | FluidAudio w osobnym pakiecie testowym. Kryterium **wykonywalne**: (a) `swift build` samymi CLT przechodzi; (b) `scripts/test.sh` przechodzi z nową zależnością (plugin makr, liczenie `@Test`); (c) `scripts/bundle.sh` składa `.app`, `otool -L` nie pokazuje zależności z `.build`, aplikacja się uruchamia; (d) próbki → tekst z czasami słów; (e) koszt dekodowania WAV i pierwsze uruchomienie (ANE). Pierwsza zależność zewnętrzna w `Package.swift` | **STOP: go/no-go dla 2.0a** (no-go: opcje z §11.2) — **wykonany 2026-10-20: GO** (pin FluidAudio 0.17.7, `.v3`, `.int8`) |
| **S1** (pomiar) | PL (i para PL+EN): jakość Parakeet vs `mai-transcribe-2`, halucynacje na ciszy, RTF; wynik zasila decyzję T11. **Materiał i referencja — rozstrzygnięte w §13 pkt 1** (poprawka: `.devdata/sessions` ma 15 sesji / ~18,5 min, ale `~/GCX/meeting notes/` ma nagrania 60, 27 i 24 min oraz kilka 9–15 min). Porównanie dwóch ASR-ów to **zgodność**, nie WER, i tak się nazywa, dopóki nie ma tekstu referencyjnego. Uruchamiany po T6 przez CLI (ten sam runner co aplikacja) | raport w `docs/superpowers/spikes/` |
| **2.0a** | implementacja wg planu | odbiór na sprzęcie (sieć off) |
| **S2** (pomiar) | Ollama, llama.cpp, oMLX na tym Macu (M4, 16 GB): 2–3 modele ≤8B Q4 na transkrypcie ~60 min (poprawka: nagranie 60 min istnieje w `~/GCX/meeting notes/` — T9 może zamiast sklejki użyć jego transkryptu z lokalnego Parakeeta po 2.0a, bez API; wybór wykonawcy T9): czas całości **i czas do pierwszego bajtu**, kontekst (w tym jeden przebieg z wejściem dłuższym niż `num_ctx`: czy Ollama obcina po cichu), „thinking", jakość korekty (odsetek odrzuceń) i notatki | **STOP: wybór domyślnych limitów i modeli rekomendowanych** |
| **2.0b** | implementacja wg planu | odbiór na sprzęcie |

Sprzęt do pomiarów: Apple M4, 16 GB RAM, macOS 27.0.1. `llama-server` 0.7.0 (Homebrew, działa, port 8080); **oMLX uruchamiany z `oMLX.app` 0.7.0** (port 8000 z `config.json`; CLI z brew 0.3.4 nie startuje — zły interpreter Pythona); **Ollama nie jest zainstalowana** (jest tylko `~/.ollama/models`, 4,8 GB) — instalacja to jawna akcja użytkownika **przed** S2, inaczej raport porównałby dwa serwery, nie trzy.
Ograniczenie 16 GB zawęża rozsądne modele lokalne.

## 8. Furtka na 2.1+ (nie budujemy teraz)
Wbudowany model = **dostawca, którego cyklem życia zarządza aplikacja** (pobranie GGUF z sumą kontrolną i zgodą, start `llama-server`
jako sidecar, health-check, zatrzymanie po bezczynności), mówiący `/v1/*`. Dzięki §5.1 preset, `Corrector` i `NoteGenerator`
nie zauważą różnicy; zmiana ograniczy się do warstwy dostawców i Settings. Wzorce: Meetily (sidecar `llama-helper`, modele Qwen 3.5 2B/4B i
Gemma 3), OpenWhispr (pobierany `llama-server` z `--jinja`, zwalnianie po 5 min bezczynności, rejestr GGUF z adresami).
Licencje obu: MIT (wolno czerpać kod z uwzględnieniem noty); FluidVoice (GPL-3.0) — tylko pomysły, nie kod.

## 9. Co przenosimy z aplikacji open source (sprawdzone na GitHubie 2026-10-19)
- **Meetily** (MIT): karty modeli lokalnych z rozmiarem/„Ready"/„Download"; sidecar i keep-alive (na 2.1).
- **OpenWhispr** (MIT): zwalnianie modelu po bezczynności; rejestr modeli z adresami; ostrzeżenia o kontekście.
- **FluidVoice** (GPL-3.0): pobieranie z postępem i sumą SHA-256, wyładowywanie po bezczynności, rekomendacja zależna od sprzętu.
  Jego „Fluid Intelligence" to zamknięty runtime do czyszczenia dyktowania (głównie EN) — nie ma czego przenosić do notatek.
- Narada, MacParakeet: współdzielą FluidAudio (log `GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md` §6) — potwierdzają ścieżkę ASR.

## 10. Testy i dowody
- Testy automatyczne wyłącznie `scripts/test.sh`; klient lokalny i klient HTTP na atrapach (`test-fake-…` dla literałów kluczy);
  mutacja każdej bramki (nowa: brak modelu = brak przebiegu; oczyszczanie „thinking"; map-reduce; brak cichego fallbacku do API).
- Odbiór na sprzęcie dla obu podfaz (sieć wyłączona), raport w `docs/superpowers/reports/`.
- Mutacje nowych bramek: usunięcie gałęzi `.fluidAudio` w `providerWithKey` → preset z lokalnym ASR nie startuje (test ma paść); sonda dla `.fluidAudio` bez `.filtered`; brak `unload` w `defer`; podmieniony plik modelu przechodzi bez odmowy; `chat` bez własnego limitu transportowego.
- Dokumenty przy planie: `docs/wymagania.md` i `ROADMAP.md` **nie wymagają** poprawki co do Parakeeta (twierdzenie „na dysku” jest dziś prawdziwe); dopisać tylko wpis o magazynie FluidAudio, wariantach (v2 i EOU w tym samym magazynie) oraz `CLAUDE.md` (stan).

## 11. Ustalenia po niezależnym przeglądzie (wszystkie **[moja decyzja]**, do sprawdzenia)

1. **Trzy serwery:** wszystkie trzy to gotowe wpisy w Settings (to tylko adres i opis); S2 mierzy wszystkie trzy. Budżet kontekstu to **jeden
   wspólny mechanizm**: wartość nastawialna u dostawcy z konserwatywnym domyślnym, a wykrywanie (Ollama `/api/show`, llama.cpp `/props`) jest
   dodatkiem „best effort", nie warunkiem. Oba złe kierunki są widoczne: zbyt mały budżet = więcej części (wolniej, ostrzeżenie w notatce o podziale),
   zbyt duży = błąd kontekstu z nazwą modelu (istniejący `ContextError`), nigdy ciche obcięcie, o ile serwer zwraca błąd; wykrycie cichego
   obcinania (Ollama) to jedno z pytań S2. **[po S2 — §14 pkt 1, 4]** wejście: jawny błąd 400 (Ollama, llama.cpp); wyjście: `finish_reason: "length"`
   traktowane jako błąd; wykrywanie: `/props` i `/api/ps`, nie `/api/show`.
2. **S0 i pierwsza zależność zewnętrzna:** FluidAudio byłby pierwszą zależnością SwiftPM w `Package.swift`. S0 sprawdza wpływ na budowanie
   samymi CLT, `scripts/test.sh` (plugin makr, liczenie `@Test`), `scripts/bundle.sh` i próg macOS 15. **No-go = STOP:** wracam do użytkownika
   z opcjami (vendoring, bezpośrednie CoreML, sidecar w rodzaju `parakeet-mlx-server`, rezygnacja z 2.0a). Kolejność jest jedna (§7): S0 → 2.0a → S2 → 2.0b; 2.0b technicznie nie zależy od S0, ale nie zmieniamy harmonogramu.
3. **Awaria lokalnej roli w trakcie przebiegu** (bez fallbacku do API; opiera się na istniejących mechanizmach):
   - **ASR:** ukończone okna zostają, nieudane są jawnymi lukami (`failedChunks`), przebieg jest wznawialny tym samym presetem.
   - **Korekta:** nieudane partie zostają oryginalne i liczą się jako nieudane (jak dziś); transkrypt jest użyteczny bez korekty.
   - **Podsumowanie:** brak notatki, błąd z nazwą modelu; ponowienie tym samym albo innym presetem.
4. **Map-reduce:** etap „map" daje skondensowany transkrypt w **tym samym formacie linii** co wejście (`[m:ss] Me|Them: …`), z zachowanymi nazwami,
   liczbami, decyzjami i zadaniami, bez interpretacji — żeby nie zgubić tożsamości mówcy (W§4). Etap „reduce" używa tego samego renderera i promptu szablonu
   z jednym dopisanym zdaniem, że wejście jest skondensowane; **„My notes" i kontekst użytkownika trafiają tylko do reduce** (nie do każdej części).
   Struktura notatki jest więc ta sama co przy API. Czy jakość wystarcza, rozstrzyga S2; bez tego pomiaru nie ustalamy domyślnych budżetów.
5. **Co znaczy „lokalny":** tylko loopback (`localhost`, `127.0.0.1`, `::1`, `*.localhost`). Adres LAN, tunel czy host zdalny **nie** dostaje
   znaczników „On this Mac" ani „Fully local". Dostawca `fluidAudio` jest wyłączony ze wszystkich ścieżek opartych na adresie (odkrywanie modeli,
   „Check", klucze) — ma własną ścieżkę.
6. **Pobieranie modelu:** po akcji użytkownika, przez pobieranie FluidAudio (opakowujemy jego API, nie piszemy własnego); wspólny magazyn
   FluidAudio, żeby nie dublować 461 MiB, jeśli inna aplikacja go już ma — **tylko gdy ta aplikacja używa tej samej generacji biblioteki** (folder
   `parakeet-tdt-0.6b-v3`); kopia `-coreml` na tej maszynie się nie liczy (S0 §7.2, §13 pkt 3). „Remove" pyta z nazwą lokalizacji (wspólnej z innymi
   aplikacjami) i kasuje **wyłącznie** `parakeet-tdt-0.6b-v3`, nigdy `-coreml`, v2 ani innych folderów.
   Uszkodzone pobranie: wykrywamy przy ładowaniu i proponujemy ponowne pobranie („Download again” = `force: true`, które kasuje folder modelu — więc też
   z potwierdzeniem i nazwą lokalizacji).
7. **Kryterium S1:** brak twardego progu — raport pokazuje **zgodność z `mai-transcribe-2`** (nie WER — brak tekstu referencyjnego; poprawka po §13),
   kompletność względem FluidVoice, halucynacje i RTF, a decyzja jest użytkownika. Lokalny ASR
   jest opcją obok API, nie zamiennikiem, więc wychodzi jako zwykły dostawca niezależnie od wyniku. Osobna bramka ciszy nie jest potrzebna:
   `EnergyGate` odrzuca ciszę przed wysłaniem do ASR (dla API i lokalnie tak samo).

8. **Wznowienie po zmianie modelu (recenzja planu P1):** `AppModel.resume` podaje do runnera zapisany snapshot, więc `RunError.inputMismatch` w aplikacji nie
   zadziała. Osobna bramka `RunGate.checkResume` odmawia wznowienia przebiegu lokalnego ASR, gdy odcisk modelu się zmienił („Start a new transcription"); odcisk
   trafia do migawki tylko dla `.fluidAudio`.
9. **Budżet kontekstu egzekwowany end-to-end (P2, P5):** jeden `inputChars` (tokeny × znaki/token z pomiaru S2 minus rezerwa na prompt i odpowiedź) dla korekty
   i dla map-reduce; wyjście mapy ma limit (`max_tokens`), a suma wyjść mapy musi mieścić się w `inputChars` — inaczej reduce hierarchiczny albo jawny błąd, nigdy
   wysyłka ponad budżet; zbyt długa linia jest dzielona na granicy słowa; limit czasu liczony **na wywołanie**; wykryty kontekst wymaga nazwy modelu (`/api/show`).
   **[zastąpione §14 pkt 4]** zamiast jednego `inputChars` — dwie reguły (stała odpowiedź: notatka/reduce; odpowiedź proporcjonalna do wejścia: korekta/mapa),
   liczone na **całym** prompcie; wykrywanie z `/api/ps` (Ollama, model załadowany) i `/props` (llama.cpp), wołane w chwili użycia.
10. **Model ASR w magazynie (P3, P4, P8):** manifest rozmiarów pochodzi ze świeżego pobrania tym samym pinem (wersja + precyzja enkodera), nie z cudzego magazynu;
    wariant o innych nazwach plików to `unknownVariant`, nie `invalid`; w buildzie DEBUG `MEETNOTES_MODEL_STORE` wskazuje kopię magazynu do odbioru; stan
    „Preparing model…” ma właściciela (`LocalASRPhase`). `Package.resolved` jest commitowany (pin). **Wykonane w S0:** manifest = §5 raportu S0
    (świeże pobranie pinem 0.17.7/`.v3`/`.int8`, dwukrotnie, bajt w bajt identyczne); do testów i odbioru służy kopia tego pobrania w `.devdata/model-store/`
    (§13 pkt 7), nie wspólny magazyn.
11. **Błędy serwera lokalnego (P6):** `timedOut` to nie „serwer nie działa" — komunikat o limicie, mniejszym modelu i Context window; „Start it" tylko dla braku połączenia.

## 12. Decyzje autora do sprawdzenia (poza §11)
Techniczny `baseURL` dostawcy lokalnego; okna ≤59 s; cykl życia modelu ASR (ładuj na przebieg); dekodowanie WAV zamiast zmiany kontraktu;
`isLocal` z adresu; wydłużone limity czasu dla lokalnych; budżet kontekstu (wykryty lub domyślny) i map-reduce w 2.0b; port oMLX 8000
(do potwierdzenia); kolejność S0→2.0a→S2→2.0b.

## 13. Decyzje Opusa z 2026-10-20 (delegowane przez użytkownika)

> Użytkownik przekazał Opusowi decyzje fazy 2.0 na noc 2026-10-20. Pytania z pierwotnego §13 zostają dosłownie (✅ = rozstrzygnięte), pod nimi decyzja.
> Uzasadnienia i odwracalność: `docs/superpowers/reports/F20-decyzje-opusa.md`; tam też lista „Do potwierdzenia rano”.

1. ✅ **Materiał i referencja dla S1.** *(pytanie: „Które nagrania (własne, służbowe) i ile minut? Kto robi tekst referencyjny — ręczne przepisanie fragmentu (np. 5–10 min)
   czy wystarczy „zgodność z `mai-transcribe-2`” (wtedy tak się to nazywa, nie WER)? FLEURS 7,31% (PL) może być tylko zewnętrznym odniesieniem.
   To ten sam brak, który trzyma T11.”)*
   **Decyzja:** bez ręcznego przepisywania (wymagałoby użytkownika). Cztery materiały, wszystkie przetwarzane **lokalnie**, w raporcie tylko liczby:
   (a) **referencja FluidVoice:** `~/Downloads/Testy i uruchomienie grafiku WFM na październik - 2026-09-23.m4a` (1380,8 s, stereo) — dokładnie plik z nagłówka
   `~/Downloads/fluidvoice - bez AI parakeet.txt` (2608 słów treści; `docs/plan.md` podaje ~2450 — raport podaje własne liczenie i metodę); oba kopiowane do
   `.devdata/s1-corpus/`; służy kryteriom 3.2–3.4; (b) **zgodność z `mai-transcribe-2`:** tylko sesje `.devdata/sessions` z istniejącym przebiegiem mai (kopie
   w scratchpadzie), **bez nowych wywołań API**; metryka nazywa się „zgodność/rozbieżność słów względem `mai-transcribe-2`”, nigdy WER; FLEURS tylko jako
   zewnętrzne odniesienie; (c) **szybkość:** nagranie 60 min z `~/GCX/meeting notes/2026-09-22/` (3601 s); (d) **cisza:** odcinki niskiej energii z torów mikrofonu.
   **Niemierzalne bez nowych nagrań użytkownika:** para PL+EN (T11) i kryterium 3.1 (patrz pkt 2) — raport pisze „niezmierzone”, nie „zaliczone”.
2. ✅ **Które kryteria `docs/plan.md` §3 obowiązują dla 2.0a.** *(pytanie: „Propozycja autora: dziedziczymy 3.1 (milczący mikrofon ≤ 2 wypowiedzi),
   3.2 (≤ 2 obcojęzyczne wtręty), 3.3–3.4 (kompletność ≥ 95% słów FluidVoice na pliku z rozdz. 13; mediana ≥ 20 słów/segment), 3.7 (85 min ≤ 60 s, postęp
   monotoniczny), 3.8 (podmieniony plik modelu → odmowa), 3.9 (FluidAudio tylko w module adaptera); 3.5 i 3.6 już spełnia istniejące wiązanie języka i
   strażnik. Które z nich uchylić”)*
   **Decyzja:** obowiązują **3.2, 3.3** (≥ 95 % słów referencji z pkt 1a), **3.4, 3.8, 3.9** oraz **3.6** — mierzone (dwa przebiegi, porównanie tekstu), bo nowy
   silnik nie dziedziczy powtarzalności; **3.5** spełnia istniejące wiązanie języka i strażnik. **3.7:** postęp monotoniczny 0→100 i rozmiar cache ANE to bramki;
   „85 min ≤ 60 s” to **cel mierzony, nie bramka** — pomiar na 60 min, wartość dla 85 min jawnie jako ekstrapolacja z 60 min; okna zostają ≤ 59 s (§4.2), a pozycja
   „większe okna dla lokalnego ASR” idzie do BACKLOG, jeśli użytkownik uzna czas za problem. **3.1** obowiązuje, ale wymaga nagrania na żywo (debata
   z głośników, milczący mikrofon) — w T8 z użytkownikiem; bez niego „niezmierzone”.
3. ✅ *(nowe, z S0 §7.2)* **Magazyn wspólny:** opcja **A** — pin 0.17.7, druga kopia (483 MB) w `…/FluidAudio/Models/parakeet-tdt-0.6b-v3` po kliknięciu „Download”;
   `-coreml` nietknięty i nieużywany. `ModelStore.defaultDirectory` = korzeń magazynu, `modelDirectory` = `<korzeń>/parakeet-tdt-0.6b-v3`. Karta: „Download (483 MB)”,
   lokalizacja, zdanie, że kopia ze starszego układu FluidAudio nie jest używana; „Remove…” kasuje tylko `parakeet-tdt-0.6b-v3`.
4. ✅ *(nowe, z S0 §7.1)* **SwiftPM:** każde polecenie, które może rozwiązywać zależności, z `--disable-keychain` (wyłącza wyłącznie odczyt poświadczeń SwiftPM
   z pęku kluczy, niczego w nim nie zmienia); flaga trafia do skryptów w T3. Zawieszenie > 2 min na „Downloading binary artifact” = STOP, bez ponawiania bez flagi.
5. ✅ *(nowe, z S0 §3.1)* **`scripts/test.sh`:** regex `tests?` — poprawka u źródła, osobny commit w T3.
6. ✅ *(nowe, z S0 §7.3)* **Postęp pobierania** liczy adapter (przeskalowanie fazy pobierania, monotoniczność, kompilacja nieokreślona).
7. ✅ *(nowe)* **Kopia modelu do testów i odbioru:** świeże pobranie z S0 skopiowane do `.devdata/model-store/` (DEBUG `MEETNOTES_MODEL_STORE`) — bez nowego
   pobierania i bez zapisu do wspólnego magazynu. `.int8V2` (568 MB) nie jest porównywany bez zgody użytkownika na pobranie.

## 14. Decyzje Opusa po S2 (delegowane przez użytkownika)

> 2026-10-20, noc. Wejście: raport S2 `docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md` (commit `38ac47f`). Fakty, na których opieram
> decyzje, sprawdzone w surowych wynikach S2 (scratchpad sesji, tylko odczyt): `ollama4k-bonsai-think.log` — tytuł, HTTP 200, `finish: length`,
> `total_tokens` 4096, `content_chars` 0; korekta B1 partia 1 na Ollamie — numery wyjścia 1…49 ciągłe, a wejście miało dziury (18, 22, 32 — llama.cpp
> zachował je i partia przeszła); przebiegi „bez myślenia” wołane z `reasoning_effort: "none"`, a przebiegi ministrala **bez** tego pola (zachowanie pola na
> modelu bez myślenia niezmierzone). Uzasadnienia i odwracalność: `docs/superpowers/reports/F20-decyzje-opusa.md` (część „po S2”); tam też „Do potwierdzenia rano”.
> Wszystkie wartości poniżej dotyczą **wyłącznie dostawców lokalnych** (`Provider.isLocal`); ścieżka API zostaje bez zmian, z wyjątkami — pkt 1 (`finish_reason`) i pkt 3 (numeracja partii).

1. **Ciche obcięcie po stronie wyjścia = błąd.** `OpenAICompatibleClient.chat` czyta `choices[0].finish_reason`; **dokładnie** `"length"` →
   `throw ProviderError.replyCutOff` (nowy przypadek; brak pola, `null` i każda inna wartość przechodzą — API często pola nie podaje). Sprawdzenie stoi
   **przed** oczyszczaniem „thinking” i sprawdzeniem pustej odpowiedzi (rozumowanie, które zjadło kontekst, ma dać „cut off”, nie „empty reply”). Dotyczy
   `chat` dla **wszystkich** dostawców (ucięta notatka z API też nie może udawać całej); **nie** dotyczy wspólnego `chatContent` używanego przez
   `transcribe(.chatAudio)` — ścieżka ASR z API zostaje bez zmian (pozycja do BACKLOG). Skutki: notatka/reduce — `NoteGenerationError.failed` z komunikatem
   `ContextError.describe`; partia korekty — nieudana (zostaje oryginał), `firstError` z tym samym komunikatem; część mapy — nieudana, cała notatka pada
   („Part n of m failed: …”); autotytuł — cicho „Untitled” (jak dziś przy błędzie); sonda — porażka z komunikatem. Komunikat (T10, angielski):
   „<model>'s reply was cut off before the end: it ran out of context or token room. Use a model with a longer context or raise the server's context length.”;
   od T13 wariant lokalny wskazuje pole „Context window” w Settings.
2. **Myślenie wyłączone dla lokalnych.** `chat` dodaje `"reasoning_effort": "none"` do ciała **zawsze, gdy `provider.isLocal`** — dla notatki, reduce, mapy,
   korekty, tytułu i sondy (S2: z myśleniem bonsai-2 jest bezużyteczny w każdej roli). Nigdy dla dostawcy nielokalnego (także LAN/tunel). Gdy serwer
   odrzuci pole — HTTP 400/422, a treść błędu (małe litery) zawiera `reasoning` — **jedno** ponowienie bez pola; przepełnienie kontekstu (treść bez
   `reasoning`) nie jest ponawiane. `ThinkingStripper` zostaje jako obrona (usuwa `<think>…</think>` i `[THINK]…[/THINK]`; niedomknięty blok do końca
   odpowiedzi usuwa w całości); stosowany w `chat`, nie w `chatContent`; pola `reasoning`/`reasoning_content` są ignorowane.
3. **Numeracja korekty ciągła w partii.** `Corrector` numeruje linie każdej partii `1…N` (od nowa w każdej partii) i mapuje numer lokalny `k` z powrotem
   na wypowiedź `batch[k−1]`; `CorrectionBatches.split/render/parse` bez zmian sygnatur. Usuwa klasę błędu „model wypełnił dziury po zaflagowanych
   liniach” (S2 §3.2). Zmiana dotyczy też API (to błąd formatu, nie lokalności).
4. **Budżet kontekstu (`ContextBudget`) — dwie reguły na całym prompcie.**
   - Stałe: `charsPerToken = 2.4` (S2: 2,65 Mistral, 2,9 Qwen; ~10 % zapasu), `defaultTokens = 4096` (domyślna Ollama), `marginTokens = 256`,
     `noteReplyTokens = 2048` (S2: notatki do ~1300 tokenów), `correctionReplyFactor = 1.3`, `mapReplyFactor = 0.5`, limity czasowe rozmiaru:
     `correctionBatchCap = 4000` znaków, `mapPartCap = 8000` znaków (przy dużym kontekście partia/część nie może trwać dłużej niż limit miękki).
   - **Stała odpowiedź (notatka, reduce):** `promptChars(replyTokens:) = Int(Double(tokens − 256 − replyTokens) × 2.4)` — limit znaków **całego**
     promptu (`system.count + user.count`, więc „My notes” i kontekst użytkownika liczą się same). Notatka jednym przebiegiem, gdy prompt ≤
     `promptChars(replyTokens: 2048)`; inaczej map-reduce.
   - **Odpowiedź proporcjonalna (korekta, mapa):** `pairedInputChars(fixedChars:replyFactor:) = Int((Double(tokens − 256) × 2.4 − Double(fixedChars)) / (1 + replyFactor))`
     — limit znaków treści `user`, gdzie `fixedChars` = `system.count`. Partia korekty: `min(4000, pairedInputChars(fixedChars: system.count, replyFactor: 1.3))`;
     część mapy: `min(8000, pairedInputChars(fixedChars: mapSystem.count, replyFactor: 0.5))`. Dla API (`budget == nil`) partia korekty zostaje 6000.
   - `maxTokens(inputChars:replyFactor:) = Int((Double(inputChars) / 2.4 × replyFactor).rounded(.up))`.
   - Wynik ≤ 0 (kontekst za mały nawet na prompt) → jawny błąd „<model>'s Context window (N tokens) is too small for …”, nigdy wysyłka.
   - Przykład 4096: notatka ≈ 4300 znaków promptu (≈ 2,7 tys. znaków transkryptu, ~3,5 min mowy); partia korekty ≈ 3,8 tys.; część mapy ≈ 5,5 tys.
     Przy 16384: prompt notatki ≈ 33,8 tys.; partia 4000; część 8000.
   - **Wybór kontekstu:** `ContextBudget.resolve(provider:detected:)` → `nil` dla nielokalnych i dla `.fluidAudio`; `base = provider.contextTokens ?? 4096`;
     `tokens = min(base, detected ?? base)` — **wykrycie tylko obniża** (zasada speca zostaje). `Provider.contextTokens: Int?` (opcjonalne, E6) wpisuje
     użytkownik w polu „Context window (tokens)” dostawcy lokalnego (zakres 2048…1 048 576, puste = 4096).
   - **Wykrywanie (best effort, w chwili użycia, bez pamięci podręcznej):** adres bez końcowego `/v1` (inny kształt adresu → brak wykrycia);
     najpierw `GET /props` → `default_generation_settings.n_ctx` (llama.cpp, efektywny na slot), potem `GET /api/ps` → `models[]` z nazwą równą modelowi
     (porównanie bez sufiksu `:latest`) → `context_length` (Ollama, tylko model załadowany). `/api/show` **odpada** (maksimum modelu, nigdy nie obniży).
     Limit 5 s, nagłówek klucza, jeśli dostawca go ma; każdy błąd → `nil`. Wołane raz przed przebiegiem korekty i raz przed notatką. „Check” w Settings
     pokazuje wykryty efektywny kontekst („Detected context: N tokens”), żeby użytkownik mógł go przepisać do pola.
5. **Limity (`ChatLimits.for(_ provider:, call: ChatCall)`, `ChatCall` = `note`, `correctionBatch`, `title`, `mapPart`).** Lokalne (miękki/transportowy, s):
   notatka i reduce 600/660, partia korekty 300/330, tytuł 120/150, część mapy 300/330 — transport zawsze ≥ miękki + 30 (bez streamu nagłówki przychodzą
   po całej generacji). API: wartości dzisiejsze bez zmian (notatka 180/120, partia 120/120, tytuł 60/120, mapa 120/120 — nieużywane, API nie dzieli);
   niespójność API „miękki 180 > transport 120” idzie do BACKLOG, nie do tej fazy. `max_tokens` (tylko lokalne; API — brak pola): notatka/reduce 2048,
   partia korekty `maxTokens(inputChars: user.count, replyFactor: 1.3)`, część mapy `maxTokens(inputChars: user.count, replyFactor: 0.5)`, tytuł 64.
   `temperature` (tylko lokalne): korekta i mapa 0.2; notatka i tytuł — domyślna serwera. Prompt mapy zawiera cel długości „at most 40% of the input”.
6. **oMLX i modele.** Preset `omlx` (`http://localhost:8000/v1`) ma `needsKey: false` i nowe pole `ProviderPreset.keyOptional: true`: pole „API key
   (optional)” w arkuszu, puste = bez klucza (pusty klucz nigdy nie trafia do pęku — istniejące `addProvider`/`replaceKey`); klucz wpisuje wyłącznie
   użytkownik. `LocalServerHint`: lokalny + HTTP 401 → prośba o klucz ustawiony w serwerze; lokalny + HTTP 507 → „not enough free memory”. **Aplikacja nie
   rekomenduje żadnego modelu** (brak listy, brak domyślnego): S2 to n=1–2 na komórkę, jedna maszyna pod obciążeniem. W edytorze presetu, gdy rola korekty
   jest lokalna, podpis: „Small local models can change names, numbers or dates while correcting. Compare with the original transcript.” Dokumenty (T14)
   podają wynik S2 jako pomiar, nie rekomendację: bonsai-2 (Q2_0) bez myślenia — poprawny format notatki; lokalna korekta — bez rekomendacji.
7. **Zadania.** T10 rośnie o pkt 1, 2 i `temperature`; T11 o pkt 6; T12 o pkt 3 i dwie reguły z pkt 4 (bez pamięci podręcznej wykrycia i bez closure
   `contextFor`); T13 korzysta z formuł pkt 4–5. Kolejność T10 → T11 → T12 → T13 → T14 bez zmian; T10–T13 nie czekają na kroki użytkownika z T8
   (2.0b technicznie niezależna, §11.2), T14 — czeka na T8. Odbiór T14 sprawdza to, czego S2 nie zmierzył (oMLX, baseline API, `reasoning_effort` na modelu
   bez myślenia, czasy na cichej maszynie) albo zapisuje „niezmierzone” — szczegóły w planie, T14.
