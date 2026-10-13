# BACKLOG — kosmetyki i drobiazgi (bez rundy poprawek)

Zasada (decyzja użytkownika, 2026-10-12): uwagi kosmetyczne (komentarze, notki, nazwy, styl testów)
trafiają tutaj i czekają; rundy poprawek dotyczą wyłącznie błędów funkcjonalnych i brakujących
testów na bramkach. **Przed S18 jedna sesja K czyści ten plik.**

## Otwarte
- [ ] `scripts/test.sh` nie pokrywa skryptów składania (`bundle.sh`/`run.sh`/`Info.plist`) — bramka podpisu była ręczna i jednorazowa; rozważyć w S16/S18. *(check S14 #3)*
  - **Do decyzji przy S18 / faza 2** — pokrycie wymaga podpisu certyfikatem z pęku kluczy i składania paczki — poza `swift test`; decyzja, czy i jak (np. ad-hoc `MEETNOTES_SIGN_IDENTITY=-` + `plutil -lint`), należy do S18.
- [ ] D3/Info.plist: process tap (dźwięk systemowy) a klucze TCC — plan D3 krok 1 oczekuje panelu „Nagrywanie ekranu i dźwięku systemowego", a w plist nie ma `NSScreenCaptureUsageDescription`; sprawdzić przy D3, ewentualna poprawka plist wróci do D1. *(check S14 #7)*
  - **Do decyzji przy S18 / faza 2** — zależy od wyniku kroku 1 planu D3 na sprzęcie (który panel TCC się pokaże); zmiana plist bez tego pomiaru byłaby zgadywaniem.
- [ ] `Package.swift` `.macOS(15.0)` vs `Info.plist` `LSMinimumSystemVersion 27.0` — rozjazd tolerowany, ale niezweryfikowany. *(check S14 #8)*
  - **Do decyzji przy S18 / faza 2** — wymaga decyzji produktowej (minimalna wersja systemu) i weryfikacji na starszym macOS — nie da się tego sprawdzić na tej maszynie.
- [ ] `MeetNotesApp` nie ma targetu testowego (executable) — logika aplikacji (blokady, `preset.json`, `latestRun`, odtwarzanie) niemieszczalna w testach bez zmiany struktury (biblioteka + testTarget); rozważyć jako zadanie fazy 2 / przy S18. *(check S15 #7)*
  - **Do decyzji przy S18 / faza 2** — zmiana struktury pakietu (biblioteka + testTarget) i bramki liczby testów — poza zakresem sesji czyszczącej.
- [ ] `AppModel.reloadSessions()` parsuje journale/transkrypty na MainActorze (init, startRecording, koniec przebiegu) — zawieszenie UI przy pełnym archiwum; `SettingsView.onChange` zapisuje wszystkie pliki przy każdym znaku. *(check S15 #10)*
  - **Do decyzji przy S18 / faza 2** — przeniesienie parsowania poza MainActor i debounce zapisu ustawień to zmiana zachowania aplikacji, nie kosmetyka; przy obecnej liczbie sesji niewidoczne.
- [ ] **Usprawnienie (użytkownik, 2026-10-13): odzyskiwanie odmówionej zgody TCC.** Po kliknięciu „Nie pozwalaj" macOS nie pyta drugi raz o mikrofon / dźwięk systemowy. Potrzebne: (a) instrukcja ręczna w aplikacji (Ustawienia → Prywatność i ochrona → Mikrofon / Nagrywanie ekranu i dźwięku systemowego; albo `tccutil reset Microphone io.github.sharezz1.meetnotes` i `… AudioCapture …`), (b) opcjonalnie przycisk w setupie „Reset permission", który uruchamia `tccutil reset` dla własnego bundle ID i prosi o restart aplikacji.
  - **Faza 2 / po D3** — funkcja produktowa, nie poprawka; wynik D3 pokaże, które panele TCC naprawdę się pojawiają.

- [ ] **D3/odbiór (2026-10-13): wiersz sesji w toku na liście ze statusem „Recovered".** Podczas
  nagrania lista pokazuje nagrywaną sesję jako osobny wiersz z etykietą „Recovered" (4× w D3: 10:54,
  11:04, 12:24, 12:27). Dwie warstwy: (a) etykieta — `SessionSummary.rebuild` startuje z
  `crashed: true` i zdejmuje je dopiero zdarzenie `session.ended`, a `MeetingsView` sprawdza
  `crashed` jako pierwszy warunek; (b) filtr `s.url != model.recording.directory` nie odsiewa sesji
  w toku — nierówność URL-i **wykluczona doświadczalnie** (test w Swifcie), kandydat pierwszy do
  sprawdzenia: porównywanie po `lastPathComponent`.
  - **Do decyzji przy S18 / faza 1.5** — dotyczy wyświetlania listy (dane sesji są poprawne:
  `journal.jsonl` i `session.json` bez zarzutu); etykieta „Recovered" opisuje „aplikacja padła
  w trakcie", a dostaje ją każde trwające nagranie.
- [ ] **D3/odbiór: preset nieczytelny w oknie głównym.** Toolbar pokazuje samą ikonę bez nazwy (więc
  kryterium kroku 4 — „chip przy Record pokazuje język" — nie jest widoczne bez rozwijania menu),
  a etykieta dostępności tego elementu to „Edit" (VoiceOver nie powie, jaki preset jest wybrany).
  Nazwa jest widoczna tylko w menu, w pływającym oknie i w trakcie nagrania (wiersz listy + panel).
  - **Faza 1.5** — razem z przeprojektowaniem ekranu i uwagami 1–7 z `reports/S17-uwagi-uzytkownika.md`.
- [ ] **D3/odbiór: „0 min" dla nagrań bez dźwięku systemowego.** Tor `system` prawie pusty
  (12:17 → 0,00 s; 12:27 → 3,72 s przy 60,80 s mikrofonu), a czas trwania wiersza liczony wyłącznie
  z toru `system` (oś sesji, spec rdzenia §6) — przy 10–60 s mowy widać „0 min", a `offsetSeconds`
  mikrofonu sięga −57,08 s. Transkrypcja mowy działa poprawnie.
  - **Do decyzji przy S18 / faza 2** — pytanie o oś/czas trwania dla nagrań bez dźwięku systemowego.
- [ ] **D3/odbiór: surowy `OSStatus error 2003334207`** w komunikacie o nieotwartym pliku ścieżki —
  sam komunikat jest czytelny (nazywa `mic_raw`), ale kod systemowy nic nie mówi; rozważyć
  tłumaczenie na „plik nie istnieje / jest uszkodzony".
  - **Faza 1.5 / kosmetyka.**
- [ ] **D3/odbiór: dwie identyczne nazwy dostawców dozwolone.** Dostawca jest identyfikowany UUID-em,
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
1. `AppModel.swift:78-88` + `:90-99` — **jeden uszkodzony plik ustawień kasuje pozostałe**: `load()` ma jeden `do/catch` na cztery pliki, a `save()` pisze wszystkie cztery, więc najbliższy zapis podmienia nieodczytane pliki pustymi domyślnymi (presety, dostawcy, ustawienia, cache sondy).
2. `SystemAudioCheck.swift:24-35` — gdy `tap.start()` rzuci, funkcja wraca przed `defer { tap.stop() }`; tap procesu i urządzenie zbiorcze z `prepare()` zostają w systemie do końca życia procesu (każde nieudane „Test" w setupie).
3. `plans/2026-09-24-faza1-00-przeglad.md:106` + `-04-powloka-aplikacji.md:1190` (D3 krok 2) — nadal zakładają `mic_aec.caf` w każdej sesji, a build nagrywa tylko `system`+`mic_raw` (decyzja S5); kryterium kroku 2 było nie do spełnienia.
4. `SettingsView.swift:25` — `try? model.secrets.get(p.id)` zamienia błąd pęku kluczy w etykietę „No key" (użytkownik może dodać dostawcę ponownie); rozróżnić „brak" od „nie odczytano".

**Zweryfikowane przez orkiestratora (2026-10-13):** BLOKUJĄCE #1 (brak testu „model i język żądań = migawka") — mutacja `TranscriptionRunner.swift:122-123` → `model: "MUTANT-NOT-THE-SNAPSHOT", language: nil` **powtórzona przez orkiestratora**: suita nadal `109/109` (mutacja cofnięta, drzewo czyste). Kod na HEAD jest poprawny — runda to wyłącznie dodanie testu.

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
