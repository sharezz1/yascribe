# Faza 2.0 „Lokalne modele" — design

> Status: **po recenzji F20 (`docs/superpowers/reports/F20-recenzja-design.md`), do przeglądu użytkownika**, 2026-10-20 (pierwsza wersja 2026-10-19). Powstał w wątku brainstormingu; decyzje
> użytkownika w §3 są dosłowne, wszystko oznaczone **[moja decyzja]** to wybór autora do
> sprawdzenia. Następny krok po akceptacji: plan w `docs/superpowers/plans/` (skill writing-plans).
> **Kodu aplikacji nie piszemy do akceptacji speca i planu.** Spiki S0–S2 (§7) to pomiary, nie kod produktu.
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
  rozważyć podniesienie, jeśli pomiar S1 pokaże zysk jakości na dłuższych oknach.
- **Język:** Parakeet v3 wykrywa język sam (25 języków europejskich, w tym PL). Zgodnie z W§2 ścieżka dostaje jawny
  język z presetu, a strażnik języka z 1.5 (`Merger` woła `LanguageGuard` zawsze, gdy `language != nil`) pilnuje wyniku. Wskazówka języka w FluidAudio
  jest tylko **skryptowa** (odsiewa tokeny spoza alfabetu), więc nie odróżnia PL od EN — „dekoder przycina wynik" znaczy tylko to.
  **`ProbeRunner.probe` dla `provider.kind == .fluidAudio` ustawia `LanguageHandling.filtered` bez klasyfikacji** **[moja decyzja]** (dzisiejsza
  `classifyLanguage` nie zwraca `.filtered` nigdy, a bez tej gałęzi badge pokazałby „can't be enforced" wbrew temu speca). „Auto" nadal tylko
  awaryjnie i z ostrzeżeniem.
- **Zarządzanie modelem** (Settings → karta modelu, wzór: Meetily `meetily-modele-lokalne.png`; mechanika po FluidVoice
  `PrivateAIModelArtifact`): nazwa, rozmiar (~460 MB), „Download" / pasek postępu / „Ready" / „Remove";
  lokalizacja w magazynie FluidAudio (`~/Library/Application Support/FluidAudio/Models`, wspólny z innymi aplikacjami). Brak modelu = preset
  z lokalnym ASR nie startuje przebiegu i mówi dlaczego, z przyciskiem pobrania. Gdy model już jest (jak dziś na tej maszynie), „Download" nic
  nie robi — upstream wraca od razu przy `modelsExist`.
  **Integralność [moja decyzja]:** upstream sprawdza tylko *obecność* plików, nie hash, więc nie obiecujemy sumy kontrolnej „z API". Karta modelu
  pokazuje nazwę, rozmiar i wariant („Multilingual"); przy ładowaniu porównujemy listę plików i rozmiary z przypiętym manifestem dla wersji modelu
  (kryterium 3.8: podmieniony plik → odmowa z przyczyną). Pełny hash tylko, jeśli S0 pokaże, że manifest z HF jest tani w utrzymaniu.
  **Szew testowy [moja decyzja]:** katalog magazynu wstrzykiwany do adaptera (domyślnie wspólny), żeby ścieżki „brak modelu / pobieranie / błąd" dało się
  odebrać bez kasowania 461 MB z wspólnego magazynu.
- **Migawka przebiegu:** `RunSnapshot`/`RunInput` dostają **opcjonalne** pole `modelFingerprint` (rozmiary + hash `config.json`), żeby wznowienie po
  zmianie modelu w magazynie przez inną aplikację nie mieszało okien z dwóch modeli w jednym transkrypcie (E6: tylko pola opcjonalne).
- **Cykl życia:** model ładowany na początku przebiegu i zwalniany po jego zakończeniu **[moja decyzja]**. Właściciel: klient lokalny jest `actor`em
  trzymającym `AsrManager` z `load()`/`unload()` (FluidAudio ma `cleanup()`), a `AppModel.transcribe` woła `unload` w `defer`; alternatywa „model żyje
  tyle co aplikacja" odpada ze względu na profil pamięci na 16 GB.
  pierwsze uruchomienie po pobraniu może długo kompilować się na ANE („Preparing model…" z postępem — tu bywa
  kilka minut; to nie jest zawieszenie).
- **Sonda i karta modelu:** sonda ASR (istniejący `ProbeRunner` na klipach) działa na lokalnym kliencie bez zmian
  koncepcyjnych; wynik pokazany jak dla API (works, kształt, obsługa języka).
- **Migawka przebiegu** (`RunSnapshot`) zapisuje dostawcę i model jak zawsze; w razie potrzeby nowe pola tylko opcjonalne.

### 4.3 Ryzyka do zmierzenia przed planem (S0, S1 w §7)
Znane już z recenzji F20: FluidAudio upstream jest **Apache-2.0**, deklaruje `.macOS(.v14)` (bez konfliktu z naszym 15.0) i zwraca `ASRResult`
z czasami tokenów. Zostaje do zmierzenia: czy buduje się samymi Command Line Tools pod Swift 6.4 i z jakimi ostrzeżeniami współbieżności; czy
`scripts/bundle.sh` (kopiuje wyłącznie binarkę, bez `Frameworks/`) poradzi sobie z jego `binaryTarget` (`NemoTextProcessing.xcframework`); jakość PL (WER na korpusie spotkań) vs `mai-transcribe-2`; halucynacje na ciszy;
zachowanie na mieszanym PL+EN (powiązane z niezamkniętym pomiarem T11).

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
| **S0** (spike, throwaway) | FluidAudio w osobnym pakiecie testowym. Kryterium **wykonywalne**: (a) `swift build` samymi CLT przechodzi; (b) `scripts/test.sh` przechodzi z nową zależnością (plugin makr, liczenie `@Test`); (c) `scripts/bundle.sh` składa `.app`, `otool -L` nie pokazuje zależności z `.build`, aplikacja się uruchamia; (d) próbki → tekst z czasami słów; (e) koszt dekodowania WAV i pierwsze uruchomienie (ANE). Pierwsza zależność zewnętrzna w `Package.swift` | **STOP: go/no-go dla 2.0a** (no-go: opcje z §11.2) |
| **S1** (pomiar) | PL (i para PL+EN): jakość Parakeet vs `mai-transcribe-2`, halucynacje na ciszy, RTF; wynik zasila decyzję T11. **Materiał i referencja — otwarte, decyzja użytkownika (§13):** `.devdata/sessions` ma 15 sesji / ~18,5 min (najdłuższa 9,4 min), więc nagrania ~60 min nie ma; porównanie dwóch ASR-ów to **zgodność**, nie WER, i tak się nazywa, dopóki nie ma tekstu referencyjnego | raport w `docs/superpowers/spikes/` |
| **2.0a** | implementacja wg planu | odbiór na sprzęcie (sieć off) |
| **S2** (pomiar) | Ollama, llama.cpp, oMLX na tym Macu (M4, 16 GB): 2–3 modele ≤8B Q4 na transkrypcie ~60 min (do wytworzenia, np. sklejenie sesji — §13): czas całości **i czas do pierwszego bajtu**, kontekst (w tym jeden przebieg z wejściem dłuższym niż `num_ctx`: czy Ollama obcina po cichu), „thinking", jakość korekty (odsetek odrzuceń) i notatki | **STOP: wybór domyślnych limitów i modeli rekomendowanych** |
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
   obcinania (Ollama) to jedno z pytań S2.
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
   FluidAudio, żeby nie dublować 460 MB, jeśli inna aplikacja go już ma. „Remove" pyta z nazwą lokalizacji (wspólnej z innymi aplikacjami).
   Uszkodzone pobranie: wykrywamy przy ładowaniu i proponujemy ponowne pobranie.
7. **Kryterium S1:** brak twardego progu — raport pokazuje WER, halucynacje i RTF obok `mai-transcribe-2`, a decyzja jest użytkownika. Lokalny ASR
   jest opcją obok API, nie zamiennikiem, więc wychodzi jako zwykły dostawca niezależnie od wyniku. Osobna bramka ciszy nie jest potrzebna:
   `EnergyGate` odrzuca ciszę przed wysłaniem do ASR (dla API i lokalnie tak samo).

8. **Wznowienie po zmianie modelu (recenzja planu P1):** `AppModel.resume` podaje do runnera zapisany snapshot, więc `RunError.inputMismatch` w aplikacji nie
   zadziała. Osobna bramka `RunGate.checkResume` odmawia wznowienia przebiegu lokalnego ASR, gdy odcisk modelu się zmienił („Start a new transcription"); odcisk
   trafia do migawki tylko dla `.fluidAudio`.
9. **Budżet kontekstu egzekwowany end-to-end (P2, P5):** jeden `inputChars` (tokeny × znaki/token z pomiaru S2 minus rezerwa na prompt i odpowiedź) dla korekty
   i dla map-reduce; wyjście mapy ma limit (`max_tokens`), a suma wyjść mapy musi mieścić się w `inputChars` — inaczej reduce hierarchiczny albo jawny błąd, nigdy
   wysyłka ponad budżet; zbyt długa linia jest dzielona na granicy słowa; limit czasu liczony **na wywołanie**; wykryty kontekst wymaga nazwy modelu (`/api/show`).
10. **Model ASR w magazynie (P3, P4, P8):** manifest rozmiarów pochodzi ze świeżego pobrania tym samym pinem (wersja + precyzja enkodera), nie z cudzego magazynu;
    wariant o innych nazwach plików to `unknownVariant`, nie `invalid`; w buildzie DEBUG `MEETNOTES_MODEL_STORE` wskazuje kopię magazynu do odbioru; stan
    „Preparing model…" ma właściciela (`LocalASRPhase`). `Package.resolved` jest commitowany (pin).
11. **Błędy serwera lokalnego (P6):** `timedOut` to nie „serwer nie działa" — komunikat o limicie, mniejszym modelu i Context window; „Start it" tylko dla braku połączenia.

## 12. Decyzje autora do sprawdzenia (poza §11)
Techniczny `baseURL` dostawcy lokalnego; okna ≤59 s; cykl życia modelu ASR (ładuj na przebieg); dekodowanie WAV zamiast zmiany kontraktu;
`isLocal` z adresu; wydłużone limity czasu dla lokalnych; budżet kontekstu (wykryty lub domyślny) i map-reduce w 2.0b; port oMLX 8000
(do potwierdzenia); kolejność S0→2.0a→S2→2.0b.

## 13. Otwarte — wymaga decyzji użytkownika (blokuje S1, a przez nią plan 2.0a)

1. **Materiał i referencja dla S1.** Które nagrania (własne, służbowe) i ile minut? Kto robi tekst referencyjny — ręczne przepisanie fragmentu (np. 5–10 min)
   czy wystarczy „zgodność z `mai-transcribe-2`” (wtedy tak się to nazywa, nie WER)? FLEURS 7,31% (PL) może być tylko zewnętrznym odniesieniem.
   To ten sam brak, który trzyma T11.
2. **Które kryteria `docs/plan.md` §3 (Etap 3, lokalny ASR) obowiązują dla 2.0a.** Propozycja autora: dziedziczymy 3.1 (milczący mikrofon ≤ 2 wypowiedzi),
   3.2 (≤ 2 obcojęzyczne wtręty), 3.3–3.4 (kompletność ≥ 95% słów FluidVoice na pliku z rozdz. 13; mediana ≥ 20 słów/segment), 3.7 (85 min ≤ 60 s, postęp
   monotoniczny), 3.8 (podmieniony plik modelu → odmowa), 3.9 (FluidAudio tylko w module adaptera); 3.5 i 3.6 już spełnia istniejące wiązanie języka i
   strażnik. Które z nich uchylić — decyzja użytkownika.
