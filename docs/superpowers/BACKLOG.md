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
  S0 dał ekstrapolację 62–106 s dla 85 min (jeden tor, najdłuższe nagranie 9,5 min); T8 ekstrapolował liniowo z 9,5 min **64–71 s** (powyżej celu; dwa tory, obciążona maszyna); S1 zmierzył 60 min i
  ekstrapoluje **~31 s** (28–35 s) dla 85 min przy poprawnym offsecie toru mikrofonu, ale **55–83 s** gdy filtr przesłuchu nie trafia (offset 0 → 108 okien zamiast 54). Wszystkie trzy to ekstrapolacje,
  nie pomiar 85 min; wartość zależy od przesłuchu/offsetu — patrz też pozycja o offsecie niżej.
- [ ] **Niezmierzone (czeka na użytkownika):** para PL+EN (T11), 3.1 (milczący mikrofon, nagranie na żywo), pierwsze „Preparing model…" w `.app` po pobraniu, przebieg przy wyłączonej sieci
  (S1 i T8 zmierzyły resztę: kompletność 102,7 %, zgodność z mai ~83 %, cisza — 1 słowo / 4,9 min szumu pokoju; szczegóły w raportach).
- [ ] **Filtr przesłuchu działa tylko przy poprawnym offsecie toru mikrofonu** (S1 §7: z offsetem 0 „me" = 190 wypowiedzi, z poprawnym 0,38 s — 8; podwaja też czas przebiegu: 108 okien zamiast 54).
  W aplikacji offset mierzy rejestrator; odbiór na żywo (3.1) musi go sprawdzić. Brak automatycznej kontroli sensowności offsetu.
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
- [ ] **Plan fazy 2.0:** pola `- [ ]` przy T11, T12 i T14 są nieodhaczone mimo commitów `fb12fe2`, `ffebac4` i `a8ad702`. Do uporządkowania przy scaleniu.

**Z odbioru 2.0b i przeglądu całości (T14, 2026-10-20; [odbiór](reports/F20-2.0b-odbior.md), [przegląd](reports/F20-przeglad-calosci.md) §4–§5) — ryzyka bez decyzji**
- [ ] **Tytuł z modelem, który potrzebuje > 64 tokenów, kończy się cicho jako „Untitled”:** `ChatLimits .title` wysyła `max_tokens` 64; `genesys-ministral3` na Ollamie nie kończy jednej linii w 64 tokenach
  (`length` → `replyCutOff` → brak tytułu, 33 s), więc dla tego modelu na Ollamie tytuł nie powstaje nigdy (na llama.cpp: 24 tokeny, tytuł poprawny). Zgodne z decyzją 8, ale bez śladu w UI.
- [ ] **Hook pre-commit ufa hashom z gałęzi `worktree-agent-*`:** `scripts/check-hashes.sh` uznaje hash istniejący na **jakiejkolwiek** gałęzi; po sprzątaniu worktree hash z niescalonej gałęzi przestanie
  przechodzić dopiero przy następnym commicie. Zawęzić do przodków `HEAD`/`master`/`faza*` albo ostrzegać o hashach tylko z `worktree-agent-*`.
- [ ] **Lokalna korekta może zmienić daty i liczby:** `CorrectionRules.accepts` to tylko pasmo długości; S2 — „pierwszego grudnia” → „pierwszy stycznia” (`bonsai-2`); w T14 liczby, nazwiska i miesiące w syntetycznej partii nietknięte (Ollama i llama.cpp),
  ale to n = 1 na komórkę. Bramka liczb/dat jest **tylko tutaj** (nie w kodzie); decyzja użytkownika (pkt 9 „po S2”) — dziś wyłącznie podpis ostrzegawczy w edytorze presetu.
- [ ] **Ponowienie bez `reasoning_effort` także po `think` w treści błędu** (`OpenAICompatibleClient.swift:147`: `reasoning` **albo** `think`) — szerzej niż spec §14 pkt 2 (`reasoning`); nieszkodliwe, do dopisania w specu.
- [ ] **`isLocal` szerszy niż tekst speca i `wymagania.md`:** kod (po `a95096e`) uznaje całe `127.0.0.0/8` i `0.0.0.0` (z testami), dokumenty wymieniają `localhost`, `127.0.0.1`, `::1`, `*.localhost`. Od tego zależą
  `requiresKey` i wysyłka `reasoning_effort`; do ujednolicenia w dokumentach (albo zawężenia kodu).
- [ ] **Cel 3.7 „85 min ≤ 60 s” nie jest zmierzony:** T8 ekstrapoluje z 9,5 min **64–71 s** (powyżej celu), S1 z 60 min **~31 s** przy poprawnym offsecie i 55–83 s przy złym; dodatkowo przesłuch/zakłócenia
  dwóch torów zmieniają liczbę okien. Szczyt pamięci rośnie z długością audio (1,17 GB przy 60 min dwóch torów; ok. 1,6 GB dla 85 min — ekstrapolacja). Patrz „Większe okna dla lokalnego ASR”.
- [ ] **Końcowy map-reduce 60 min przy kontekście 16384 niezmierzony end-to-end** (limit czasu odbioru): przy 4096 i 8192 `bonsai-2` kończy jawnym błędem, szacunek dla 16384 to 25–30 min i dojście do 2. poziomu mapy i reduce
  (zmierzona osobno tylko gęstość wejścia: 2,84 znaku/token). Jakość map-reduce wobec jednego przebiegu ocenia użytkownik.
- [x] **Ciche obcięcie wejścia przez Ollamę (`bonsai-2`) — obrona wdrożona (T14b, `606ee39`):** porównanie `usage.prompt_tokens` z długością promptu dla dostawców lokalnych; do czasu wdrożenia dotyczy pola „Context window” wyższego niż kontekst serwera
  przy niezaładowanym modelu oraz oMLX. Decyzja (a)/(b)/(c) z przeglądu §5 pkt 1 — użytkownika. Po wdrożeniu odhaczyć i dopisać hash.
- [x] **Funkcja (użytkownik, 2026-10-21): zmiana modelu dla podsumowania bezpośrednio w zakładce Summary.** Dziś model podsumowania zmienia się tylko przez preset (Settings → Presets).
  Przy porównywaniu jakości (np. z myśleniem i bez, albo dwóch modeli) trzeba wychodzić do Settings i wracać. Oczekiwane: wybór modelu (i przełącznika „Thinking") przy przycisku generowania notatki,
  ponowne wygenerowanie tą samą drogą. Do rozstrzygnięcia przy projekcie: czy wybór zmienia preset sesji, czy tylko jeden przebieg (zapisany w `notes/meta.json` albo `summary.json`: pole `model` już jest).
  - **Faza 2.0.1** (decyzja użytkownika 2026-10-22). Rozszerzone o korektę („Improve transcript"); zapis przy sesji w `notes/meta.json`, działa od następnego uruchomienia. Specyfikacja: `specs/2026-10-22-zmiana-modelu-w-spotkaniu-design.md`, plan: `plans/2026-10-22-faza201-zmiana-modelu.md`.
  - **Zrobione w kodzie (PR #20, 592/592):** chip „Model · <id> ⌄” w pasku Summary i obok „Improve transcript”, popover (Use preset, dostawca, model, Thinking), zapis w `notes/meta.json` (`modelOverrides`), linie „Made with …” i „Corrected with …”. **Użytkownik potwierdził na żywo 2026-10-22: zmiana modelu działa przy regeneracji Summary i transkryptu („Improve transcript”) oraz pozostałe punkty odbioru (restart zachowuje wybór, „Use preset”, zagnieżdżony popover, wznowienie z własnym modelem korekty); PR #19 `bed13d5` i #20 `0409a3f` scalone.** Zakres odbioru: (zmiana modelu → Regenerate; restart zachowuje wybór; „Use preset”; „Improve transcript” innym modelem na sesji z gotową korektą).
  - **Decyzje wykonawcze (do wglądu):** prompt korekty zostaje z presetu; „Improve transcript” działa po udanej korekcie, gdy sesja ma własny model korekty (nadpisuje `corrected.json`); trwający przebieg zostaje przy modelu z chwili startu; chip korekty widać zawsze, gdy jest transkrypt; „Corrected with …” pokazuje się, gdy poprawiony tekst powstał innym modelem niż ten w chipie.
- [ ] **PRIORYTET WYSOKI (użytkownik, 2026-10-22): mikrofon łapie dźwięk z głośników i duplikuje go jako „Me”**, choć mówi to rozmówca. Pozycja już istnieje jako „AEC offline" (ROADMAP „Nieprzypisane", [F15-T13 uwagi, A #2](reports/F15-T13-uwagi-uzytkownika.md)) i jako uwaga o offsecie filtra przesłuchu (wyżej); podnoszę priorytet.
  Dowód (spotkanie 2026-10-21, 16 min, 135 wypowiedzi): 58 linii „Me", z czego **32 oznaczył filtr tekstowy** (`EchoFilter`, `echoOfThem`; wyłączone z notatki i korekty, w widoku opisane), a **kolejne ok. 5 krótkich** (np. „No niby tak,", „yy") ma identyczny tekst jak linia „Them" w oknie 12 s i **nie jest oznaczone**. Filtr działa na tekście, więc krótkie wypowiedzi i różnice w rozpoznaniu go mijają.
  Kierunek (decyzja użytkownika): AEC offline na torach (`system` jako odniesienie dla `mic_raw`) zamiast zgadywania po tekście; filtr tekstowy zostaje siatką bezpieczeństwa. Powiązane: wybór mikrofonu i rdzeń nagrywania.
- [ ] **PRIORYTET WYSOKI (znalezione 2026-10-22, spotkanie „[spotkanie dzienne]", sesja `2026-10-22T06-45-33Z-ec0b`): na słuchawkach Bluetooth tor `system` ma 3× za mało audio i złą prędkość.** W pliku 352 s audio na 1025 s nagrania (mikrofon: 1024,5 s, kompletny); stosunek zegara sesji do pliku stały, 3,0 (10 s pliku na 30 s zegara), efektywna częstotliwość toru ok. 16,5 kHz przy deklarowanych 48 kHz. Transkrypt „Them": 6 wypowiedzi, 6 słów („Mm.", „."); głosów rozmówców brak.
  Hipoteza (z danych zegara, **bez odsłuchu i bez ASR**): słuchawki (jedno urządzenie `00-02-3C-8D-E0-50` jako wejście i wyjście) przeszły w tryb rozmowy (HFP, 16 kHz), a tap dalej dostarczał 16 kHz, choć format zapisano z początku jako 48 kHz. `SystemTapSource.swift:77` i `:92` czytają `CoreAudioDevices.tapFormat` raz, przy starcie; zmiany nie śledzą.
  **Dowód od użytkownika (2026-10-22, test poczekalni Teams):** pigułka Recording pokazuje „Microphone: Sound Blaster JAM V2" (słuchawki), a Teams w tym samym momencie używa „Mikrofon (MacBook Air) (Built-in)" i „Głośniki (MacBook Air) (Built-in)". Kod potwierdza przyczynę: aplikacja nagrywa **domyślne** urządzenia systemu (`defaultInputDevice`, `defaultOutputDevice`, `SystemTapSource.build()`; nazwa w pigułce z `defaultInputName()`), a nie te, których używa spotkanie. Otwarcie mikrofonu słuchawek mogło przełączyć je w tryb rozmowy (HFP), co zgadza się z hipotezą 16 kHz. To wzmacnia pozycję „wybór mikrofonu przed startem" (spec 1.5 decyzja 4) i dodaje wybór wyjścia dla toru `system`.
  **Pomiar kontrolny (2026-10-22, sesja `2026-10-22T07-31-04Z-82c4`, test poczekalni „[spotkanie testowe]", 1693 s):** start na słuchawkach (`00-02-3C-8D-E0-50`), tor `system` bez ani jednej klatki i `track.failed: stalled30s` w 30,1 s; w 139,5 s `device.changed` obu torów na `BuiltInMicrophoneDevice`/`BuiltInSpeakerDevice` (domyślne urządzenia przełączone na MacBooka — wniosek z dziennika, bez potwierdzenia użytkownika), `track.recovered` i pierwsza klatka w tej samej chwili. Po przełączeniu oba tory zdrowe: stosunek zegara do pliku 1,0, efektywnie 47998 Hz i 16000 Hz, po 6–7 dziur (ok. 1 s razem), „Them" 79 wypowiedzi, 3371 słów, cały czas spotkania; lokalny Parakeet. Zgadza się z hipotezą (urządzenie wbudowane działa, słuchawki nie), ale **poczekalni to nie rozstrzyga**: pierwsze 139 s tor systemowy był podpięty do złego urządzenia, więc „cisza w poczekalni" i „zły tap" są nie do rozdzielenia. Do powtórzenia z domyślnymi urządzeniami ustawionymi na MacBooka od startu. Dobra wiadomość: odzyskiwanie po zmianie urządzenia zadziałało (`track.recovered`).
  **Potwierdzone przez użytkownika (2026-10-22):** słuchawki wyłączone ręcznie, dźwięk sam przeszedł na MacBooka; Wispr Flow pokazuje kilkanaście tekstów z początku rozmowy, których w transkrypcie Yascribe nie ma (zero osi czasu = pierwsza klatka toru `system`, 139,5 s po starcie), a **pigułka przez te 109 s nic nie pokazała** (`stalled30s` trafia tylko do dziennika, `SessionRecorder.swift:171`; w UI widać go dopiero po nagraniu, w szczegółach spotkania). Uwaga do projektu alarmu: na wbudowanych urządzeniach tor `system` też daje 0 klatek, gdy nic nie gra (sesje `49df`, `e9f3`, `b96d`), więc cisza w poczekalni to prawdopodobnie też stall; alarm musi mówić „brak dźwięku, wyjście: <nazwa>", nie „błąd".
  Drugi objaw tej samej sesji: mikrofon 79 dziur (razem 14,4 s) i tor systemowy 92 dziury (15,6 s), najgęściej ok. 766.–812. s zegara; w tekście „Me" brak ok. 48 s (755 s → 803 s).
  Do zrobienia: potwierdzić hipotezę (np. `system.caf` odczytany jako 16 kHz przez lokalny Parakeet), naprawić (ponowne czytanie formatu tapa albo przeliczanie), dopisać test (tap z formatem innym niż zapisany; mutacja bramki), ostrzeżenie w widoku, gdy tor ma wyraźnie mniej audio niż trwa sesja. Zobacz też „Tor systemowy bez ani jednej próbki" (PR #13): to inny przypadek, tor bez klatek.
  **Zrobione (PR faza22-pill-system-audio, 2026-10-22):** pigułka pokazuje nazwę wyjścia w wierszu „System audio", a po 30 s bez klatek „No system audio yet · <nazwa wyjścia>" (informacja, nie ostrzeżenie; znika po `track.recovered`). Zostaje: wybór urządzeń przed startem, pomiar na słuchawkach, formatu tapa czytany raz.
  **Zrobione (faza 2.0.2, 2026-10-23, scalona w PR #23, `c33bd48`):** pomiar M1/M2b, format tapa czytany z urządzenia zbiorczego, układ `tapOnly` domyślnie, nasłuch częstotliwości z odroczoną przebudową, ostrzeżenie o złej prędkości toru, podpowiedź o słuchawkach w pigułce i menu wejścia. **Odbiór M4 (sesja `2f1c`, słuchawki jako wejście i wyjście): tor `system` 79,3 mln klatek, 47 998,9 Hz, 164 wypowiedzi „Them".** Zostaje: przypadek `08f6` (0 klatek) niewyjaśniony, menu wejścia i fałszywy alarm pigułki niezmierzone, B i poczekalnia Teams niezmierzone. Szczegóły: `spikes/2026-10-22-f202-s0-sluchawki.md`.
  **Przegląd gałęzi 2.0.2 (2026-10-23), odłożone drobne:** tekst „same headset / call mode” w `TrackProblem` nie sprawdza Bluetooth (USB-owy zestaw też ma jeden UID na wejście i wyjście); po zniknięciu wybranego wejścia `preferredUID` zostaje, więc ponowne podłączenie słuchawek cicho wraca na nie (decyzja D2 do potwierdzenia); `inputDevices` listuje urządzenia przy każdym odświeżeniu widoku (ok. 4 razy na sekundę); `RawMicrophoneSource.select` otwiera urządzenie synchronicznie na wątku głównym (przy przełączeniu HFP może zawiesić interfejs); brak migawki otwartego menu wejścia.
  - **Faza 2.0.2 „Nagrywanie na słuchawkach"** (decyzja użytkownika 2026-10-22). W zakresie: pomiar na słuchawkach, format tapa czytany raz (`SystemTapSource.swift:77`, `:92`), ostrzeżenie, gdy tor ma wyraźnie mniej audio niż trwa sesja; pigułka z PR #17 jest pierwszym krokiem tej fazy. Do ustalenia z użytkownikiem: czy wybór mikrofonu i wyjścia przed startem (spec 1.5 decyzja 4) wchodzi do 2.0.2, czy ma osobną fazę. **Pomiar S0 wykonany 2026-10-22:** `spikes/2026-10-22-f202-s0-sluchawki.md` (wejście+wyjście na słuchawkach: tor `system` bez klatek; samo wyjście na słuchawkach: 44,1 kHz zapisane jako 48 kHz, plik ok. 8,8 % za szybki; samo wejście na słuchawkach: tor zdrowy). Specyfikacji i planu jeszcze nie ma. Powiązane: wybór mikrofonu, AEC offline.

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
