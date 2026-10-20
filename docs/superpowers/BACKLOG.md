# BACKLOG — kosmetyki i drobiazgi (bez rundy poprawek)

Zasada (decyzja użytkownika, 2026-10-12): uwagi kosmetyczne (komentarze, notki, nazwy, styl testów)
trafiają tutaj i czekają; rundy poprawek dotyczą wyłącznie błędów funkcjonalnych i brakujących
testów na bramkach. **Przed S18 jedna sesja K czyści ten plik.**

## Otwarte
- [x] `scripts/test.sh` nie pokrywa skryptów składania *(zrobione w T12: `scripts/check-bundle.sh` w `test.sh`, osobna ścieżka .build/check)* (`bundle.sh`/`run.sh`/`Info.plist`) — bramka podpisu była ręczna i jednorazowa; rozważyć w S16/S18. *(check S14 #3)*
  - **Do decyzji przy S18 / faza 2** — pokrycie wymaga podpisu certyfikatem z pęku kluczy i składania paczki — poza `swift test`; decyzja, czy i jak (np. ad-hoc `MEETNOTES_SIGN_IDENTITY=-` + `plutil -lint`), należy do S18.
- [ ] D3/Info.plist: process tap (dźwięk systemowy) a klucze TCC — plan D3 krok 1 oczekuje panelu „Nagrywanie ekranu i dźwięku systemowego", a w plist nie ma `NSScreenCaptureUsageDescription`; sprawdzić przy D3, ewentualna poprawka plist wróci do D1. *(check S14 #7)*
  - **Do decyzji przy S18 / faza 2** — zależy od wyniku kroku 1 planu D3 na sprzęcie (który panel TCC się pokaże); zmiana plist bez tego pomiaru byłaby zgadywaniem.
- [ ] `Package.swift` `.macOS(15.0)` vs `Info.plist` `LSMinimumSystemVersion 27.0` — rozjazd tolerowany, ale niezweryfikowany. *(check S14 #8)*
  - **Do decyzji przy S18 / faza 2** — wymaga decyzji produktowej (minimalna wersja systemu) i weryfikacji na starszym macOS — nie da się tego sprawdzić na tej maszynie.
- [ ] `MeetNotesApp` nie ma targetu testowego (executable) — logika aplikacji (blokady, `preset.json`, `latestRun`, odtwarzanie) niemieszczalna w testach bez zmiany struktury (biblioteka + testTarget); rozważyć jako zadanie fazy 2 / przy S18. *(check S15 #7)*
  - **Do decyzji przy S18 / faza 2** — zmiana struktury pakietu (biblioteka + testTarget) i bramki liczby testów — poza zakresem sesji czyszczącej.
  - **Stan po 2.0 (gałąź `faza20`):** nadal bez targetu; faza 2.0 dołożyła logikę w `MeetNotesApp`, której testy nie sięgają — `LocalASRSupport` (fazy pobierania,
    blokada „Remove"), arkusz dostawcy w `SettingsView` (parsowanie pola „Context window"), Cancel i postęp w `NotesModel`. Cienką logikę stanu karty modelu
    przeniesiono świadomie do biblioteki (`ModelCardState` w `MeetNotesLocalASR`), żeby miała testy; reszta pozostaje ręczna.
- [ ] `AppModel.reloadSessions()` parsuje journale/transkrypty na MainActorze (init, startRecording, koniec przebiegu) — zawieszenie UI przy pełnym archiwum; `SettingsView.onChange` zapisuje wszystkie pliki przy każdym znaku. *(check S15 #10)*
  - **Do decyzji przy S18 / faza 2** — przeniesienie parsowania poza MainActor i debounce zapisu ustawień to zmiana zachowania aplikacji, nie kosmetyka; przy obecnej liczbie sesji niewidoczne.
- [ ] **Usprawnienie (użytkownik, 2026-10-13): odzyskiwanie odmówionej zgody TCC.** Po kliknięciu „Nie pozwalaj" macOS nie pyta drugi raz o mikrofon / dźwięk systemowy. Potrzebne: (a) instrukcja ręczna w aplikacji (Ustawienia → Prywatność i ochrona → Mikrofon / Nagrywanie ekranu i dźwięku systemowego; albo `tccutil reset Microphone io.github.sharezz1.meetnotes` i `… AudioCapture …`), (b) opcjonalnie przycisk w setupie „Reset permission", który uruchamia `tccutil reset` dla własnego bundle ID i prosi o restart aplikacji.
  - **Faza 2 / po D3** — funkcja produktowa, nie poprawka; wynik D3 pokaże, które panele TCC naprawdę się pojawiają.
- [ ] **Faza 2 (użytkownik, 2026-10-13, design 1.5): wybór mikrofonu przed startem.** `RawMicrophoneSource` bierze tylko domyślne wejście systemu (`CoreAudioDevices.defaultInputDevice()`); wybór urządzenia to zmiana rdzenia (źródło + dziennik + obserwator urządzeń). W 1.5 pigułka tylko **pokazuje** nazwę mikrofonu, wyraźnie, żeby było widać nagrywanie „nie tego".
- [ ] **Faza 2 (decyzja 2026-10-13): transkrypt na żywo i „Resume"** (wznowienie nagrywania do tej samej notatki). Resume = drugi segment sesji (zmiana formatu: wiele `session.started/ended`, luka na osi, offsety ścieżek). Zakładki i pigułka 1.5 mają miejsce na oba.

- [x] **D3/odbiór (2026-10-13): wiersz sesji w toku *(zrobione w T8: `SessionStatus`, porównanie po nazwie katalogu; nagrywana sesja to wiersz Recording)* na liście ze statusem „Recovered".** Podczas
  nagrania lista pokazuje nagrywaną sesję jako osobny wiersz z etykietą „Recovered" (4× w D3: 10:54,
  11:04, 12:24, 12:27). Dwie warstwy: (a) etykieta — `SessionSummary.rebuild` startuje z
  `crashed: true` i zdejmuje je dopiero zdarzenie `session.ended`, a `MeetingsView` sprawdza
  `crashed` jako pierwszy warunek; (b) filtr `s.url != model.recording.directory` nie odsiewa sesji
  w toku — nierówność URL-i **wykluczona doświadczalnie** (test w Swifcie), kandydat pierwszy do
  sprawdzenia: porównywanie po `lastPathComponent`.
  - **Do decyzji przy S18 / faza 1.5** — dotyczy wyświetlania listy (dane sesji są poprawne:
  `journal.jsonl` i `session.json` bez zarzutu); etykieta „Recovered" opisuje „aplikacja padła
  w trakcie", a dostaje ją każde trwające nagranie.
- [x] **D3/odbiór: preset nieczytelny w oknie głównym.** *(zrobione w T8: `RecordCard` z nazwą, językiem i modelem ASR; `PresetMenu` z etykietą tekstową)* Toolbar pokazuje samą ikonę bez nazwy (więc
  kryterium kroku 4 — „chip przy Record pokazuje język" — nie jest widoczne bez rozwijania menu),
  a etykieta dostępności tego elementu to „Edit" (VoiceOver nie powie, jaki preset jest wybrany).
  Nazwa jest widoczna tylko w menu, w pływającym oknie i w trakcie nagrania (wiersz listy + panel).
  - **Faza 1.5** — razem z przeprojektowaniem ekranu i uwagami 1–7 z `reports/S17-uwagi-uzytkownika.md`.
- [ ] **D3/odbiór: „0 min" dla nagrań bez dźwięku systemowego.** Tor `system` prawie pusty
  (12:17 → 0,00 s; 12:27 → 3,72 s przy 60,80 s mikrofonu), a czas trwania wiersza liczony wyłącznie
  z toru `system` (oś sesji, spec rdzenia §6) — przy 10–60 s mowy widać „0 min", a `offsetSeconds`
  mikrofonu sięga −57,08 s. Transkrypcja mowy działa poprawnie.
  - **Do decyzji przy S18 / faza 2** — pytanie o oś/czas trwania dla nagrań bez dźwięku systemowego.
- [x] **D3/odbiór: surowy `OSStatus error 2003334207`** *(zrobione w T12: `OSStatusText`)* w komunikacie o nieotwartym pliku ścieżki —
  sam komunikat jest czytelny (nazywa `mic_raw`), ale kod systemowy nic nie mówi; rozważyć
  tłumaczenie na „plik nie istnieje / jest uszkodzony".
  - **Faza 1.5 / kosmetyka.**
- [x] **D3/odbiór: dwie identyczne nazwy dostawców dozwolone.** *(zrobione w T4: `ProvidersFile.nameError`, blokada w arkuszu Add Provider)* Dostawca jest identyfikowany UUID-em,
  więc funkcjonalnie nieszkodliwe, ale komunikat „No API key for <nazwa>. Remove the provider…" staje
  się niejednoznaczny (nie wiadomo, którego dostawcę usunąć). Propozycja: blokada duplikatu nazwy
  w formularzu.
  - **Faza 1.5** — razem z przeprojektowaniem Settings (uwagi 4–5 użytkownika).

## Aneks S18 (2026-10-13) — przegląd całej gałęzi (pełny raport: `reports/S18-przeglad.md`)

**Rekomendacje dla pozycji strukturalnych (§3 raportu; do zatwierdzenia przez użytkownika):**
- pokrycie skryptów składania (`bundle.sh`/`run.sh`/`Info.plist`) w `test.sh` → **faza 1.5** (tanie: ad-hoc `MEETNOTES_SIGN_IDENTITY=-`, `plutil -lint`, grep kluczy `*UsageDescription`; bramka D1/TCC nie ma dziś żadnego zabezpieczenia przed cichą regresją);
- brak testTargetu aplikacji (`MeetNotesApp`) → **faza 2** (dotyka grafu zależności i bramki liczby testów; blokady i `preset.json` mają pokrycie ręczne z D3);
- `reloadSessions()` na MainActorze + `SettingsView.onChange` → **faza 2** (wydajnościowe, przy obecnej liczbie sesji niewidoczne);
- `.macOS(15.0)` vs `LSMinimumSystemVersion 27.0` → **faza 2** (wymaga decyzji produktowej i weryfikacji na starszym macOS);
- `Info.plist`/TCC (mapowanie process tap) → **faza 2**; „TCC — odzyskiwanie odmówionej zgody" → **faza 2** (zgodnie z decyzją użytkownika).
- 5 pozycji „D3/odbiór" → **faza 1.5** (decyzja użytkownika; Claude wciąga je do planu).

**Nowe pozycje z S18 (raport §2 — lista do planu 1.5):**
1. `AppModel.swift:78-88` + `:90-99` — **jeden uszkodzony plik ustawień kasuje pozostałe**: `load()` ma jeden `do/catch` na cztery pliki, a `save()` pisze wszystkie cztery, więc najbliższy zapis podmienia nieodczytane pliki pustymi domyślnymi (presety, dostawcy, ustawienia, cache sondy). → **NAPRAWIONE w rundzie S18** (commit `404fbb4`: osobny `do/catch` na plik + `<nazwa>.corrupt-<yyyyMMdd-HHmmss>` przed jakimkolwiek `save()` + `lastError` z nazwą pliku; **sprawdzenie ręczne w `.devdata` ✅** — trzy starty z zepsutym `probe-cache.json`, zapis po nich nie ruszył `presets.json`/`providers.json`; szczegóły: `reports/S18-runda.md`). Znany sufit: gdy samo przeniesienie się nie uda, najbliższy `save()` nadpisze ten plik (`ponytail:` w kodzie — wymaga zmiany `save()`, poza zakresem rundy).
2. `SystemAudioCheck.swift:24-35` — gdy `tap.start()` rzuci, funkcja wraca przed `defer { tap.stop() }`; tap procesu i urządzenie zbiorcze z `prepare()` zostają w systemie do końca życia procesu (każde nieudane „Test" w setupie). **→ NAPRAWIONE w T12** (`defer` przed startem, test `systemAudioCheckStopsTheTapWhenStartThrows`).
3. `plans/2026-09-24-faza1-00-przeglad.md:106` + `-04-powloka-aplikacji.md:1190` (D3 krok 2) — nadal zakładają `mic_aec.caf` w każdej sesji, a build nagrywa tylko `system`+`mic_raw` (decyzja S5); kryterium kroku 2 było nie do spełnienia. **→ NAPRAWIONE w T12** (poprawki planów D3 i przeglądu).
4. `SettingsView.swift:25` — `try? model.secrets.get(p.id)` zamienia błąd pęku kluczy w etykietę „No key" (użytkownik może dodać dostawcę ponownie); rozróżnić „brak" od „nie odczytano". **→ NAPRAWIONE w T4** (`KeyStatus`).

**Zweryfikowane przez orkiestratora (2026-10-13):** BLOKUJĄCE #1 (brak testu „model i język żądań = migawka") — mutacja `TranscriptionRunner.swift:122-123` → `model: "MUTANT-NOT-THE-SNAPSHOT", language: nil` **powtórzona przez orkiestratora**: suita nadal `109/109` (mutacja cofnięta, drzewo czyste). Kod na HEAD jest poprawny — runda to wyłącznie dodanie testu.

**Odpowiedzi orkiestratora na pytania raportu (§6):**
- **Q1 (wiersz „Recovered")** — **TAK**: na zrzucie z 12:27 oba wiersze („Recording 00:00:11 · Polski · PL" i „12:27 · 0 min · Recovered") były w **jednej liście**, w tej samej instancji aplikacji — hipoteza drugiej instancji (`open -n`/`swift run`) nie tłumaczy obserwacji; rozjazd między replikacją a obserwacją zostaje do rozstrzygnięcia w fazie 1.5 (pozycja D3/odbiór nr 1).
- **Q2 (klasyfikacja `load()`/`save()`)** i **Q3 (zakres rundy: test także po stronie `resume`)** — decyzja użytkownika (do dopisania po jego odpowiedzi).

## Z przeglądu T5 (2026-10-14, `reports/F15-T5.md`) — drobne, bez rundy poprawek
- [ ] `NoteTitle.parse`/`clean`/`display` dzielą tylko po `"\n"` i obcinają `.whitespaces`: `"# Title\r\n"` daje tytuł z `\r`, a `"# \r"` — tytuł `"\r"` zamiast „Untitled meeting". Obcinać `.whitespacesAndNewlines`. Do tego `clean` obcina cudzysłowy asymetrycznie (`Review of "Plan B"` → `Review of "Plan B`).
- [ ] `NoteTitle.parse`: tekst przed tytułem (np. ostrzeżenie o niespójnym transkrypcie) znika z treści; prompt zabrania tekstu przed `# `, więc rzadkie. Ogrodzenie bloku kodu z tekstem po nim nie jest zdejmowane.
- [ ] `MarkdownBlocks`: tabele rozpadają się na akapit na komórkę, blok kodu i cytat spadają do akapitu, akapit kontynuacji w punkcie dostaje zbędny znacznik. Nic nie ginie; tylko wygląd — prompt „Standard" nie prosi o tabele.
- [x] `RunDirectory.latestRunID` filtruje dopuszczalne znaki, nie wzorzec daty: zabłąkany `runs/notes.txt` albo `--run debug` z CLI wygrywa jako „najnowszy". Zaostrzyć do katalogów i wzorca `…Z`. *(zrobione w `e42c6a8`: tylko wzorzec `AppModel.sessionName`; od retencji decyduje o kasowaniu audio, przegląd całości P2; domyślny runID CLI `…Z` bez `-xxxx` też jest pomijany)*
- [ ] `NotesStore.updateMeta` czyta, zmienia i zapisuje bez serializacji: `AutoTitle.generate` (poza MainActor) i `setManualTitle` (UI) mogą się przeplecieć i autotytuł zgubi ręczny tytuł (okno < 1 ms). Sprawdzić przy T6/T7 (serializacja przez jeden aktor/kolejkę). *(od 1.6 także powiązanie z kalendarzem — przegląd całości B6)*
- [ ] `NotesStore`: brak testu ścieżki „nieudane przeniesienie `.corrupt-…` rzuca i nic nie zapisuje"; okno TOCTOU między `problems()` a odłożeniem (nie gubi danych, wg przeglądu).

## Z przeglądu T6 (2026-10-14, `reports/F15-T6.md`) — drobne, bez rundy poprawek
- [x] **Korekta gubi ogon wypowiedzi z `\n` (D1, najpoważniejsza z drobnych).** *(naprawione po T12: `render` skleja `\n` w spację, test `multiLineUtteranceIsSentAsOneLineSoItsTailIsNotLost` + mutacja)* `CorrectionBatches.render` wysyła `[n] pierwsza linia\nogon`; `parse` pomija linię `ogon` (nie zaczyna się od `[`), więc `fixed[n]` to sam początek i — jeśli ≥60% długości — przechodzi pasmo, a ogon znika z `corrected.json`, z którego korzysta notatka. Realne: `/audio/transcriptions` bez znaczników słów (Merger wstawia surowy `result.text`) albo model zawija linię. Oryginał zostaje, więc to nie utrata danych źródłowych. Poprawka: w `render` zamieniać `\n` na spację (+ test).
- [ ] `Corrector.correct` po `Task.isCancelled` → `break` zwraca `batches = batches.count`, a pominięte partie nie liczą się do `failedBatches`: częściowo poprawiony transkrypt wygląda na sukces (D2; dziś martwa ścieżka — nic nie przerywa `Task`).
- [ ] `AutoTitle.clean` (D4): brak polskiego `„` (U+201E), `‘’`, `«»`; „untitled meeting" małymi literami zapisze się jako tytuł; pierwsza linia „```" albo „<think>" (model rozumujący) zapisze się jako `autoTitle` i `shouldRun` zablokuje kolejne próby na stałe.
- [ ] `ContextError` (D6): fałszywy pozytyw dla 400 „max_tokens exceeds maximum…" (nasz `chat()` max_tokens nie wysyła), fałszywy negatyw dla 413 z domyślnym HTML nginx; oryginalny tekst błędu nie jest dołączany; spec §4.1 mówi „400/413 lub treść", kod „status i słowo" (zachowawczo) i dodaje 422.
- [ ] Gdy wszystkie partie korekty padną (np. 401/402), wynik = oryginał, przyczyna przepada, a T7 i tak zapisze `corrected.json` (D7); spec §7 mówi o komunikacie z Retry. Rozważyć w T7/UI.

## Z przeglądu T10 (2026-10-14, `reports/F15-T10.md`) — drobne, bez rundy poprawek
- [x] **Nazwa mikrofonu w pigułce przestaje być aktualna (D2, sprawdzić w odbiorze T13):** *(naprawione po T12: `micName` odświeżane w sekundowym timerze; do potwierdzenia ręcznie w T13 — zmiana domyślnego wejścia w trakcie nagrania)* `micName` czytane raz przy starcie, a `RawMicrophoneSource` podąża za zmianą domyślnego wejścia (np. AirPods podłączone w trakcie) — pigułka dalej pokazuje stary mikrofon, dokładnie ten przypadek, który miała wyłapać decyzja 4. Rozwiązanie: odświeżać `micName` razem z `levels` (co 0,25 s `defaultInputName()`) albo z `deviceChanged` z dziennika.
- [ ] Pigułka rozwija się w dół i nic jej nie ogranicza do widocznego obszaru ekranu (D1); `NSHostingView` nadpisuje `setContentSize` wysokością treści, więc wartości 64/230 są tylko chwilowe — usunąć albo zastąpić `sizingOptions`.
- [ ] `levels` trzyma ostatnią porcję bez końca: tor, który stanął lub padł, nadal pokazuje ✓ (D4; z założenia „ostatnia porcja"). Rozważyć wygaszanie po N sekundach bez porcji.
- [ ] Zwinięta pigułka nie ma wskaźnika poziomu, który wymienia spec §5.3 (D5; plan to przepisał). `PillState.expanded` przeżywa koniec nagrania — następne nagranie startuje rozwinięte (D7). Test `levelsAreKeptPerTrackAndReadableAfterTheEnd` ma jedno źródło i nie odróżnia „klucz tylko dla torów z porcją" (D6; wpływ na UI zerowy).

## Z przeglądu fazy 1.6 (2026-10-19, `reports/F16-przeglad.md`)

- [ ] **Poczekalnia Teams (spec §6 pkt 2) niezmierzona i bez decyzji.** Ekran przed dołączeniem może trzymać mikrofon ≥ 12 s; przy włączonym auto-starcie nagranie ruszyłoby przed wejściem na spotkanie. Pomiar sondą audio (`MEETNOTES_PROBE=audio`) albo zapisane odstępstwo. *(uwaga 1)*
- [x] Testy „cisza przez godzinę" (`manualStopSilencesAutoStartForTheSameCall`, `manualStopDuringAMicBlipStaysQuiet`, dwugodzinna część `dismissedOfferStaysQuietForTheWholeMicSession`) mają tiki co 5–60 s, więc od 44e586f przerwa > 3 s zeruje ciągłość mikrofonu i przechodzą bez wyciszenia; tiki co 1 s. Luka: Stop w chwili krótkiego zwolnienia mikrofonu (`lastInput.keys` → `active` przechodzi cały zestaw). *(uwaga 2)* *(zrobione w `ed629eb`: tiki co 1 s w tych testach i w `ignoredAppsNeverOffer`/`unknownAppsNeverOffer`, część po t0+31 w `dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp`; mutacja bez `mutedFamilies.formUnion(lastInput.keys)` pada na `manualStopDuringAMicBlipStaysQuiet` i `manualStopSilencesAutoStartForTheSameCall`. Testy `dismissed…` dostały blip mikrofonu w `a6341a8`, więc łapią też usunięcie `mutedFamilies.insert(f)` w `dismiss()`, patrz `reports/F15-poprawki-P1-P2-P4.md`)*
- [ ] Start kończący się od razu (`noSources`): zakolejkowany `finish` chowa ofertę mimo poprawki 14ceaa7; powstaje pusta sesja. *(uwaga 3)*
- [ ] Nieudany auto-start zostawia `starting`; gdy rozmowa przechodzi w spotkanie z kalendarza, Start nagra bez powiązanego wydarzenia. *(uwaga 4)*
- [ ] Odpięcie wydarzenia przypiętego przy starcie daje „Untitled meeting" (autotytuł nie powstał); do decyzji. *(uwaga 5)*
- [ ] „Launch at login" pokazuje zapisane ustawienie, nie stan `SMAppService` (np. `.requiresApproval`). *(uwaga 6)*
- [ ] VoiceOver czyta tytuł okna pigułki „Meeting detected"/„Meeting ended?" w trakcie nagrywania. *(uwaga 7)*
- [ ] Potwierdzenie Quit działa tylko z paska menu; Cmd-Q, Dock i wylogowanie w trakcie nagrania dają „Recovered" (sprzed 1.6, auto-start w tle ułatwia trafienie). *(uwaga 8)*

## Z odbioru wyciszania torów (2026-10-19, `reports/F15b-wyciszanie.md`)

- [ ] **Ujemne czasy wypowiedzi „Me” przed pierwszą próbką dźwięku systemowego.** Oś sesji zaczyna pierwsza próbka toru
  `system`, a process tap potrafi dać ją dopiero przy pierwszym dźwięku (sesja `2026-10-19T10-03-38Z-113d`: 28 s po
  mikrofonie; `2026-10-13T10-27-14Z-6d17`: 57 s). Wypowiedź z mikrofonu sprzed tej chwili ma ujemne `start`, a
  `MeetingDetailView.time` formatuje je jako „0:00:-13” (też w Copy; odtwarzanie liczy od złego miejsca). Linie
  wyciszenia już to omijają (`MuteNote`). Do decyzji: oś od początku nagrania (np. `session.started` albo najwcześniejsza
  pierwsza próbka), co zmienia czasy w istniejących transkryptach — albo tylko formatowanie i przycięcie.

## Z wdrożenia „Coming up” (2026-10-19, `reports/F16-coming-up.md`)

- [ ] Decyzje D2–D9 z raportu do potwierdzenia przy odbiorze (D1 potwierdzone 2026-10-19, macos.md §11.5).
- [ ] Strona główna odświeża się po `EKEventStoreChanged` najpóźniej po minucie (`TimelineView(.everyMinute)`); od razu = podpiąć `calendarSource.changes`.
- [ ] Nieaktualny wybór kalendarzy (`calendarSelectionStale`) na stronie głównej wygląda jak „No more meetings today”.
- [ ] Brak migawki linii ostrzeżenia Auto pod nagłówkiem (preset Auto).

## Z fazy 2.0 (2026-10-20, gałąź `faza20`; źródła: [F20-decyzje-opusa](reports/F20-decyzje-opusa.md), przeglądy Opusa w commitach `6b32807` (T4), `a95096e` (T10), `4ff727b` (T12/T13), kod) — bez rundy poprawek

Bez odbioru T8/T14 część poniższych to hipotezy z kodu i recenzji, nie obserwacje z użycia. Pozycje decyzyjne 1–14 („Do potwierdzenia rano") zostają w logu decyzji,
nie są tu kopiowane.

**Lokalny ASR (2.0a)**
- [ ] **Rewizja modelu na Hugging Face niepinowana** (`main`; `ModelRegistry.revisionOverrides` nie przetestowane — wymaga odczytu metadanych HF, S0 §2, §9; decyzja Opusa 7e, pkt 4 „rano").
  Skutek: po ponownym wyeksportowaniu modelu upstream stan karty to „Needs repair" z „Download again" (`force` kasuje folder i pobiera 483 MB), a pobranie kończy się
  błędem „differs from the version this build expects", po którym karta dalej pokazuje „Download again" — **możliwa pętla** (każdy klik = kolejne pobranie). Nic w kodzie jej nie przerywa
  (`ModelStore.download` rzuca, status zostaje `invalid`). Pin rewizji albo osobny stan „upstream changed" bez ponownego pobierania. *(recenzja planu P3 pkt 3 przewidywała ten przypadek)*
- [ ] **`unknownVariant` to ślepy zaułek:** gdy w folderze `parakeet-tdt-0.6b-v3` leży inny wariant (np. `.int8V2`: `Encoder_v2.mlmodelc` zamiast `Encoder.mlmodelc`, S0 §2), karta pokazuje
  „Different variant" **bez żadnej akcji** (`primary = nil`: ani Download, ani Remove) i mówi, że aplikacja go nie ruszy. Użytkownik musi sam skasować folder w Finderze.
- [ ] **`.int8` vs `.int8V2`** (upstream: `.int8V2` „naprawia zepsute tokeny", 568 MB) — jakości nie porównano; wymaga zgody na kolejne pobranie (decyzja 2, pkt 2 „rano").
- [ ] **Sufit integralności:** podmiana pliku wag o tym samym rozmiarze nie jest wykrywana (wag, 480 MB, nie hashujemy; odcisk w migawce obejmuje treść małych plików — `6b32807`).
  Dokumenty (spec §4.2, §10, decyzja 7e) mówią jeszcze „hash `config.json`" — kod hashuje treść wszystkich plików poza `weight.bin`; do ujednolicenia.
- [ ] **Większe okna dla lokalnego ASR** — tylko jeśli czas przeszkadza: okna zostają ≤ 59 s (ziarno wznawiania); kryterium 3.7 „85 min ≤ 60 s" jest celem mierzonym, nie bramką.
  S0 daje jedynie ekstrapolację (62–106 s dla 85 min z jednego toru, najdłuższe nagranie w pomiarze 9,5 min); realny pomiar 60 min planowano w S1 (niewykonany).
- [ ] **Niezmierzone (czeka na użytkownika lub S1/T8):** jakość PL vs `mai-transcribe-2` i kompletność wobec FluidVoice (S1), halucynacje na ciszy, para PL+EN (T11), 3.1 (milczący
  mikrofon, nagranie na żywo), pierwsze „Preparing model…" w `.app` po pobraniu, przebieg przy wyłączonej sieci.

**Lokalny model tekstowy (2.0b)**
- [ ] **Użytkownik nie może wyczyścić zapisanego klucza oMLX:** `AppModel.replaceKey` przy pustym polu niczego nie robi (pusty = „zostaw"/tylko weryfikuj), a `Edit key…` z pustym polem testuje
  zapisany klucz. Usunięcie klucza = usunięcie dostawcy. Potrzebny jawny „Remove key".
- [ ] **`ProviderPreset.all` vs `ready`:** dwie listy gotowych dostawców — `all` (z `custom`, bez `onThisMac`) używają tylko testy, aplikacja bierze `ready`; łatwo je rozjechać
  przy kolejnym dostawcy. Zostawić jedną.
- [ ] **Komunikat ucięcia w `Corrector` używa starej rady:** `Corrector` woła `ContextError.describe` bez `maxTokens`, więc partia ucięta na własnym limicie wyjścia (1,3× wejścia)
  dostaje radę „Raise the Context window…" zamiast „reply hit the output limit", którą po `4ff727b` mają notatka i reduce (część mapy ma osobny komunikat).
- [ ] **Postęp przez niestrukturalne `Task { @MainActor … }`** (`NotesModel` — „part n of m"; `AppModel` — postęp transkrypcji) — kolejność dostarczenia nie jest gwarantowana, więc licznik teoretycznie może się
  cofnąć (nieobserwowane). Pobieranie modelu (`LocalASRSupport`) pilnuje monotoniczności przez `max`; generowanie notatki i postęp sesji nie.
- [ ] **Niespójność API: notatka — limit miękki 180 s > transportowy 120 s** (`ChatLimits.for`, ścieżka API bez zmian w 2.0; plan T14).
- [ ] **`finish_reason: "length"` w `transcribe(.chatAudio)`:** `chatContent` jest wspólny z `chat`, ale ścieżka ASR z API świadomie nie sprawdza pola (decyzja 8) — ucięta odpowiedź nadal przechodzi jako transkrypt.
- [ ] **Bramka korekty nie łapie zmian dat i liczb** (`CorrectionRules.accepts` = pasmo długości): S2 — `bonsai-2` zmienił „pierwszego grudnia" na „pierwszy stycznia". Dodatkowa bramka
  (porównanie liczb/dat) albo wyłączenie lokalnej korekty do czasu mocniejszego modelu — decyzja użytkownika (pkt 9 „po S2"); na razie tylko podpis ostrzegawczy w edytorze presetu.
- [ ] **Wykrycie kontekstu podnoszące budżet przy pustym polu:** dziś wykrycie (`/props`, `/api/ps`) tylko obniża budżet; „Check" pokazuje wykrytą wartość, ale przy pustym polu budżet to 4096. Propozycja S2
  (bezpieczna, bo przepełnienie i ucięcie są jawnymi błędami) — decyzja użytkownika (pkt 11 „po S2"). Z 4096 notatka > ok. 3,5 min mowy idzie przez map-reduce.
- [ ] **Map-reduce tylko dla dostawców lokalnych:** API nadal bez dzielenia długich transkryptów (komunikat „arrives later"); ROADMAP trzyma tę część jako otwartą.
- [ ] **Niezmierzone:** oMLX (jedyny model MLX nie mieści się w pamięci — HTTP 507; czasy, thinking, jakość, przepełnienie kontekstu), baseline API (ta sama notatka i korekta przez API — wymaga klucza
  i wysyłki nagrania do chmury, tylko na polecenie użytkownika), `reasoning_effort` na modelu bez „thinking" (ponowienie bez pola jest w kodzie, ale nie zmierzono, kiedy działa),
  czasy na cichej maszynie (S2 przy load do 107), n=1–2 na komórkę jakości, `temperature` 0,2 (wpływ), tokenizery Gemma/Llama (znaki na token).
- [ ] **Przebiegi `mai-transcribe-2` na nagraniach służbowych z `~/GCX`** (zgodność na dłuższym materiale) — wysyłka do chmury i koszt; tylko na polecenie użytkownika.
- [ ] **Plan fazy 2.0:** pola `- [ ]` przy T11 i T12 są nieodhaczone mimo commitów `fb12fe2` i `ffebac4`; T1, T8, T14 faktycznie niewykonane. Do uporządkowania przy odbiorze.

## Zapisane (dla kroniki)

- 2026-10-12 — `RunError.inputMismatch`: komentarz + „progi przesłuchu" → `0dd84ef`.
- 2026-10-12 — test przesłuchu: zakres z sekund + `#expect(mic.count >= …)` → `0dd84ef`.
- 2026-10-13 — S16: `scripts/test.sh` — usunięte zbędne `rm -f "$OUT"` (sprząta `trap`); wzorzec zacieśniony do prefiksów z `Tests/` (`mn-((fit|session|tr)-)?<UUID>`), komentarz opisuje, że `mn-corpus-<UUID>` nie pasuje.
- 2026-10-13 — S16: CLI `transcribe` — błędy użycia (zły katalog sesji, `--language`, `--shape`/`--run`) przed budową klienta; brak `journal.jsonl` → „to nie katalog sesji", kod 64.
- 2026-10-13 — S16: CLI `client()` (models/probe/transcribe) — baseURL bez `http://`/`https://` albo bez hosta → „zły adres … podaj pełny adres", kod 64.
- 2026-10-13 — S16: CLI `transcribe` — postęp `NN% (okna d/N)` od startu pętli (licznik widoczny przed pierwszym oknem), `fflush`.
- 2026-10-13 — S16: CLI `probe` — `--language` bez wartości → kod 64 (wspólny helper `CLI.value`, używany też przez `transcribe`).
- 2026-10-13 — S16: CLI `session-from-file` — istniejący `journal.jsonl` sprawdzany przed czytaniem audio; komunikat z podpowiedzią „świeży katalog na każdy plik korpusu" (nadal odmowa, kod 1).
- 2026-10-13 — S16: oś sesji vs offsety plików — notka w pomocy CLI („czas w pliku ścieżki = czas na osi − przesunięcie z summarize").
- 2026-10-13 — S16: `AppModel.startRecording` — zapis `preset.json` przez do-catch → `lastError` (nagranie trwa dalej).

## Z przeglądu całości faza15 (2026-10-19, `reports/F15-przeglad-calosci.md`) — bez rundy poprawek

- [ ] **B1.** `SessionRecorder.setMuted` liczy tor `stalled30s`, `allZeros60s` albo z błędem zapisu jako nagrywający, więc da się wyciszyć jedyny żywy tor; zgodne dosłownie z §11.5, do rozważenia przy fazie 2.
- [ ] **B2.** Wyciszenie toru, który nie wystartował (np. mikrofon bez zgody), zwraca `false` i pigułka pokazuje „Nothing is being recorded”; sprawdzić, czy pigułka w ogóle pokazuje przełącznik dla takiego toru.
- [ ] **B3.** Awaria aplikacji w trakcie kopiowania przenoszenia zostawia częściową kopię w celu; ponowna próba dostaje „Choose an empty folder”, a sprzątanie działa tylko w ścieżce błędu, nie po restarcie.
- [ ] **B4.** Widok spotkania ma dwie osie czasu: `TrackProblem` liczy przez `offsetSeconds + frame/sampleRate`, a `MuteNote` przez `SessionClock` (z dryfem); przy długim nagraniu różnica może sięgać sekund.
- [ ] **B5.** `NotesModel.runCorrection` zapisuje `corrected.json` przez `try?`, więc błąd zapisu ginie po cichu; skutek łagodny, lepiej zgłosić przez `report`.
- [ ] **B6.** Wyścig `NotesStore.updateMeta` ma od 1.6 więcej piszących (powiązanie z kalendarzem przy starcie, link i unlink, autotytuł poza MainActor, ręczny tytuł); przegrany zapis może zgubić powiązanie wydarzenia, nie tylko tytuł.
- [ ] **B7.** Pierwsze uruchomienie po aktualizacji z fazy 1 stosuje domyślne 30 dni bez pytania R1; faza 1 nie kasowała nic, więc pierwsze audio zniknie ok. 2026-11-12 (patrz „Dla użytkownika” w raporcie).
- [ ] **B8.** `EndDetector`: gdy pytanie wisi z sygnału `silence`, a potem przychodzi `callReleased`, treść pytania się nie zmienia (`shown != nil` → `nil`); kosmetyka.
- [ ] Domyślny `runID` CLI (`2026-10-14T10-00-00Z`, bez `-xxxx`) nie pasuje do wzorca `latestRunID` (P2, `e42c6a8`): sesja transkrybowana tylko z CLI nie pokaże transkryptu w aplikacji; kierunek bezpieczny dla retencji. Rozważyć dopisanie sufiksu w CLI.
