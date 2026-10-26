# F15-T13 — część A odbioru: poprawki funkcjonalne (2026-10-15)

Wejście: `reports/F15-T13-uwagi-uzytkownika.md` (`1ab686e`). Zakres na polecenie użytkownika: **tylko część A**; część B (wygląd, `docs/design/`) robi osobna sesja designu — widoków nie stylowałem. 1 commit na uwagę. `scripts/test.sh`: **199/199** (183 + 16 nowych `@Test`). Mutacje wykonywał Haiku (każda pada na asercji, nie na budowaniu; po cofnięciu pełny przebieg zielony).

| # | Uwaga | Commit | Testy | Mutacje |
|---|---|---|---|---|
| D | `ruvector.db`: plik usunięty, `.gitignore` | `24a84e9` | — | — |
| 3 | Korekta „wisi" | `db97258` | +4 (187) | 5/5 |
| 2 | Echo z głośników (Me powtarza Them) | `3081902` | +7 (194) | 5/5 |
| 5 | Krótki tytuł bez przedrostka | `395aa47` | +2 (196) | 4/4 |
| 4 | Cała notatka zaznaczalna | `eabaa2d` | +1 (197) | 3/3 |
| 6a | ModelPicker: układ | `a2341f7` | — (UI) | n/d |
| 7 | Kafelki dostawców + Verified | `641f0f3` | +2 (199) | 4/4 |

## #3 Korekta „wisi" — przyczyna i poprawka
**Przyczyna ustalona z danych sesji `f184`:** `corrected.json` **istnieje**, ale ma godzinę 15:25, ~16 min po transkrypcji (15:09), przy transkrypcie z 7 wypowiedzi (1931 znaków, jedna partia). Korekta nie padła, tylko jedno wywołanie modelu trwało kilkanaście minut: `URLRequest.timeoutInterval` mierzy bezczynność łącza, nie czas całości, więc dostawca trzymający połączenie nigdy go nie przekraczał. Stan nie miał końca ani powodu. **Poprawka:** `withDeadline` (całkowity limit czasu) — 120 s na partię korekty, 60 s autotytuł, 180 s generowanie notatki; po limicie partia zostaje oryginalna i liczy się jako nieudana; gdy nie przeszła żadna partia (`failedCompletely`) → stan **„Correction failed: <powód>"** w wierszu listy (`SessionStatus.correctionFailed`) i w banerze zakładki Transcript z **Retry**; „Improve transcript" także wtedy, gdy korekty nie ma (np. aplikacja zamknięta w trakcie). Stan korekty zawsze się kończy (`runCorrection`).
**Ograniczenie:** `NotesModel`/UI (przejście stanu, Retry) nie mają testu automatycznego (cel aplikacji bez testTargetu — BACKLOG); pinują je testy biblioteczne (`slowBatchIsGivenUpOnAndTheOriginalIsKept`, `correctionFailureIsVisibleInTheStatusUntilRetried`, generator/autotytuł).

## #2 Echo — odsiew tekstowy
`EchoFilter` (biblioteka transkrypcji): wypowiedź „Me" (≥4 różne słowa), której słowa w ≥80% leżą w słowach wypowiedzi „Them" nakładających się czasowo (±5 s), dostaje `Utterance.echoOfThem` (pole opcjonalne — stare pliki się wczytują) i jest poza notatką/korektą. Stosowany w `Merger` i przy wczytaniu starszych transkryptów (idempotentnie, bez zapisu). **Na prawdziwej sesji `f184` wykrywa oba echa z odbioru** (0:00 — identyczne 64 słowa; 0:21 — pierwsza część 60-słowowej wypowiedzi); w pozostałych 12 sesjach z `.devdata` dwa trafienia, oba prawdziwe echa (te same słowa, ten sam czas). `languageFlagCount` liczy teraz tylko flagi języka (echo ma `echoCount`). Ryzyko: użytkownik dosłownie powtarzający słowa rozmówcy w tym samym oknie zostanie oznaczony (widoczna etykieta „Echo of the other side", poza notatką). Filtr akustyczny zostaje; AEC offline — faza 2.

## #5 Tytuł
Wspólna reguła `NoteTitle.rule` w prompcie notatki i autotytułu (do 8 słów, bez etykiet typu „Notatki z rozmowy"/„Meeting notes") + deterministyczne zdejmowanie takiej etykiety z tytułu (`stripLabel`: „Notatki z rozmowy: presja na wygląd" → „Presja na wygląd").

## #4 Zaznaczanie notatki
`MarkdownBlocks.flatten` składa blok-y w jeden `AttributedString` (nagłówki z pustą linią przed, `•` z wcięciem, `n.`), a `MarkdownView` rysuje jeden `Text` z `.textSelection`. Układ potwierdzony migawką; **samo zaznaczanie ponad akapitami potwierdzisz w odbiorze** (migawka go nie pokazuje).

## #6a ModelPicker
Jedna linia ze skracaniem w środku, pełne id w podpowiedzi (`.help`), pole szukania wyrównane do lewej (popover dziedziczył wyrównanie do prawej z formularza), popover 520 pt zamiast 380. Bez migawki (popover) — odbiór.

## #7 Dostawcy
Kafelki **OpenRouter**, **Ollama** (bez klucza, z adnotacją „Corrections and summaries only — Ollama can't transcribe audio."), **Custom**; arkusz z gotowym adresem. Po dodaniu automatyczny test połączenia (`listModels`) → „Verified · N models" albo powód po ludzku (401 zły klucz, 403 uprawnienia/guardrail, 404 zły adres, serwer wyłączony, nie-lista modeli); przycisk **Verify** przy każdym dostawcy. Wynik jest w pamięci (po restarcie „Not verified" do kliknięcia Verify). ElevenLabs bezpośrednio — faza 2 (Scribe v2 przez OpenRouter działa już teraz).

## Odchylenia i uwagi
- `makeClient(for:)` wydzielone z `client(for:)` (bez alertu), żeby weryfikacja pokazywała powód przy dostawcy zamiast okna błędu.
- Plan przeglądu §3: wiersz „po odbiorze T13, część A" (+16 → 199), T13 oczekuje `199/199`.
- Nie ruszałem `docs/design/` ani wyglądu widoków (kolory, krój, odstępy). Zmiany UI to wyłącznie treść i układ potrzebne do działania.

## Do odbioru (część C) — rzeczy, których migawki i testy nie pokrywają
1. #3: nagranie z presetem „Polski"; wolny model → po 2 min „Correction failed" + Retry w wierszu i banerze, Retry działa; po restarcie podczas korekty — przycisk „Improve transcript".
2. #2: ponownie otwórz sesję `f184` — wypowiedzi Me z 0:00 i 0:21 mają etykietę „Echo…", notatka ich nie zawiera (po „Regenerate").
3. #4: zaznacz całą notatkę myszą od pierwszego do ostatniego akapitu i skopiuj.
4. #6a: popover wyboru modelu (jedna linia, szersze okno, szukanie od lewej).
5. #7: kafelki → arkusz z gotowym adresem; zły klucz → „Invalid API key."; Ollama wyłączona → „Can't connect…".
6. Dalej z poprzedniej listy: Review Focus #9 i #10, D2 (nazwa mikrofonu po zmianie wejścia), potwierdzenie zmiany embeddingu, arkusz Add Provider, nieczytelny plik notatek; **T11** czeka na nagranie mieszane i klucz w Twoim terminalu.
