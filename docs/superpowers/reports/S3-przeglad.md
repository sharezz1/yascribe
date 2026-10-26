# S3 — przegląd (niezależny)

**Zakres:** `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md` §4, raport `docs/superpowers/reports/S3.md`, diff `901bb4a..3024eb3` (faktycznie jeden commit: `3024eb3`).
**Tryb:** przegląd. Nic nie naprawiano, nie zmieniano gałęzi ani innych plików niż ten raport.

## Wynik testów (wymagany)

`scripts/test.sh` → ostatnia linia:

```
test.sh: 44/44 testów uruchomionych i zaliczonych.
```

Kod wyjścia: `0`. Zgodne z deklaracją w `S3.md`.

## Ustalenia osi 1 i 2 (fakty, bez oceny)

- `Sources/meetnotes-cli/CLI.swift` jest **identyczny bajt w bajt** z blokiem kodu A9 z planu (`2026-09-24-faza1-01-fundament-i-nagrywanie.md`, płotki 2677/2792). Deklaracje z `S3.md` („bez różnic", „bajt w bajt") są prawdziwe.
- Diff pliku planu w `901bb4a..3024eb3` to **wyłącznie** `- [ ]` → `- [x]` dla A9 Krok 1–5 (linie ~2675, 2794, 2796, 2798, 2800); liczba linii bez zmian, więc numery linii w `S3.md` pozostają aktualne.
- Hash `88c0bd4` cytowany w `S3.md` jako przed-amend istnieje; `git diff --stat 88c0bd4 3024eb3` = tylko `docs/superpowers/reports/S3.md | 97 +++`. Wyjaśnienie amend potwierdzone.
- **Mutacja z planu: N/A dla S3.** Jedyne wystąpienie „mutacj" w planie to linia 41 (status sekcji A1 o samym skrypcie testowym). Sekcja A9 nie zawiera kroku mutacji — zadanie A9 nie dokłada żadnego testu (44 → 44).
- Drzewo robocze czyste (`git status --porcelain` pusty) — brak zapisów poza repo/katalogiem sesji.

## Punkty

### 1. Całkowity odczyt pliku do RAM bez limitu

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:97–113` (`readAnyAudio`)
- **Problem:** funkcja wczytuje cały plik do `[Int16]`, potem `AudioFit.mono` tworzy kopię `[Float]`. Dla godzinnego nagrania stereo 48 kHz to ~1,9 GB tylko na Int16 (plus konwersje). Brak jakiegokolwiek ograniczenia lub ostrzeżenia.
- **Propozycja:** ograniczyć analizowany zakres (offset/długość) albo jawnie udokumentować górny limit rozmiaru i przerwać z błędem po jego przekroczeniu.

### 2. Ciche obcięcie danych przy `break`

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:108` oraz `:109`
- **Problem:** `if buf.frameLength == 0 { break }` i `guard let p = buf.int16ChannelData else { break }` kończą odczyt **bez błędu**. `fit` policzy dopasowanie na niepełnych danych i wypisze wynik jako poprawny.
- **Propozycja:** zamienić `break` na `throw` (np. „nie udało się wczytać całego pliku") zamiast cichego sukcesu.

### 3. Niepoprawna wartość liczbowa opcji ignorowana po cichu

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:55` (`--seconds`), `:57` (`--silence`), `:91` (`--max-lag-ms`)
- **Problem:** parsowanie przez `Double(...)`/`Int(...)` z fallbackiem na wartość domyślną; literówka (np. `--seconds abc`) nie daje błędu — opcja działa jak niepodana. Zweryfikowane: `record /tmp/x --seconds abc --no-system --no-aec` wystartowało bez ostrzeżenia.
- **Propozycja:** walidować obecność opcji i parsowalność wartości; przy błędzie wypisać `usage` i `exit(64)`.

### 4. Walidacja argumentów po efekcie ubocznym w `fit`

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:86–87`
- **Problem:** `fit` najpierw otwiera plik referencyjny (`readAnyAudio(positional(0))`), a dopiero potem używa drugiego pozycyjnego (`CAFReader(positional(1))`) — który przy braku wywołuje `exit(64)`. Przy podaniu tylko jednej ścieżki wychodzi więc błąd CoreAudio (`ExtAudioFileOpenURL`) i `exit(1)` zamiast `exit(64)`. Zweryfikowane smoke'em: `fit /nie/ma/ref.aiff` → exit 1.
- **Propozycja:** najpierw pobrać i zwalidować oba argumenty pozycyjne, dopiero potem otwierać pliki.

### 5. `--seconds` powyżej 14400 jest nieskuteczne

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:54–55` w powiązaniu z `Sources/MeetNotesRecording/EndCondition.swift:59–62`
- **Problem:** `conditions = .standard` zawiera już `HardLimitCondition(4*3600)`, a `--seconds` dokłada kolejny `HardLimitCondition` **na końcu** listy. `evaluateLocked` zwraca pierwszy nie-nil, więc wartość > 4 h nigdy nie zadziała (mniejsza działa, bo jest wcześniej). Zachowanie przeniesione wprost z planu.
- **Propozycja:** przy podanym `--seconds` nadpisać/pominąć standardowy `HardLimitCondition`, albo udokumentować ograniczenie 4 h w `usage`.

### 6. Źródło sygnału nigdy nie anulowane

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:60–63`
- **Problem:** `DispatchSource` dla SIGINT nie jest anulowany po zakończeniu nagrywania. W procesie CLI kończącym się po komendzie jest to nieszkodliwe, ale zasób pozostaje niezwolniony i utrudnia użycie `record` z poziomu procesu długożyjącego.
- **Propozycja:** zachować uchwyt i wywołać `cancel()` po `for await`.

### 7. `ticker` nie jest awaitowany

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:64` i `:68`
- **Problem:** po `for await` wywoływane jest tylko `ticker.cancel()`; nie ma `await ticker.value`. Zadanie mogło już wejść w `Task.sleep` i wykonać jeszcze jeden `recorder.tick()` równolegle z `summarize`. Dziś bezpieczne tylko dlatego, że `tick()` sprawdza `finishing` — zachowanie zależne od implementacji, nie od kontraktu.
- **Propozycja:** `await ticker.value` po `cancel()` (lub przenieść `cancel()` przed `summarize` i poczekać na zakończenie).

### 8. Podwójny wydruk „koniec:"

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:66` i `:74`
- **Problem:** `record` wypisuje `koniec: <reason>` w pętli, a następnie `summarize` wypisuje to samo z `session.json`. Użytkownik widzi dwie linie „koniec:".
- **Propozycja:** usunąć jeden z wydruków.

### 9. Brak automatyzacji dla CLI (i brak mutacji w planie)

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift` (całość); plan A9 (2661–2812)
- **Problem:** A9 nie dodaje żadnego testu (liczba 44 bez zmian), a plan nie przewiduje kroku mutacji dla A9 — więc kryterium „mutacja z planu wykonana i czerwona" nie ma tu zastosowania i nie da się go potwierdzić. Pokrycie `record` i `fit` opiera się wyłącznie na smoke (help + `summarize /nie/ma`); sam `fit` nie ma ani testu, ani udokumentowanego przebiegu w `S3.md`.
- **Propozycja:** albo dodać test `fit` na małym fixture (np. `findsDelayedAndAttenuatedCopy` już istnieje w bibliotece — użyć syntetycznych plików), albo świadomie zapisać w raporcie, że `fit`/`record` są weryfikowane dopiero w A10.

## Uwagi formalne

- `S3.md` podaje pełny blok kroków A9 (w tym przebieg `scripts/test.sh` + commit), nie twierdzi „brak kroku mutacji" dla A9 — spójne z treścią planu.
- W `S3.md` nie ma odwołania do nieistniejącego kroku; wszystkie cytowane hashe sprawdzone w `git`.
