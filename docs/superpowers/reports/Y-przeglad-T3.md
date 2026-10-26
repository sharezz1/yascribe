# Y-T3: przegląd migracji danych i kluczy

Data: 2026-10-26. Zakres: commit `ab90750` i poprawka po przeglądzie; pliki `DataMigration.swift`, `KeyMigration.swift`, `LegacyMigration.swift`, `Stores.swift` (`isOverridden`), `YascribeApp.swift`, 15 nowych testów (759/759). Przegląd read-only wykonał advisor (silniejszy model) na pełnym zapisie sesji; agent wprowadził poprawki.

## Odpowiedzi na pytania planu

| Pytanie | Odpowiedź |
|---|---|
| Czy któraś ścieżka może skasować lub przepisać dane użytkownika? | Znaleziona: usuwanie „pustego" nowego katalogu było rekurencyjne (`removeItem`) i sprawdzało tylko istnienie. Przy dwóch równoległych instancjach druga mogła skasować katalog z danymi przeniesionymi przez pierwszą. **Poprawione:** `rmdir` (nierekurencyjne; odmawia przy niepustym) po usunięciu samego `.DS_Store`. Poza tym kasowane są wyłącznie `.DS_Store` i pusty katalog. Stare klucze nie są nigdzie usuwane (mutacja d). |
| Czy `moveItem` na tym samym woluminie jest atomowy? | Tak, w obrębie jednego katalogu nadrzędnego to `rename(2)`; gdy cel istnieje, kończy się błędem, nie nadpisaniem. `Application Support/MeetNotes` i `…/Yascribe` leżą w tym samym katalogu. |
| Czy `AppModel()` jest wywoływany przed migracją? | Nie. Jedyne miejsce utworzenia: `YascribeApp.init` po `LegacyMigration.moveDataIfNeeded()`; pole to `let model: AppModel` przypisywane w `init`. |

## Mutacje bramek (wszystkie padają, potem `git checkout`)

(a) zawsze przenoś → `bothDirectoriesWithDataAreReportedNotMerged`; (b) bez sprawdzenia działającej aplikacji → `runningOldAppBlocksTheMove`; (c) błąd starego klucza jako `.noOldKey` → `unreadableOldKeyIsReportedNotTreatedAsMissing`; (d) `old.delete` po kopii → `neverDeletesTheOldKey`; (e) `unreadable` do rozstrzygniętych → `unresolvedKeysAreRetriedOnNextRun`.

## Odstępstwa od planu (świadome)

1. `.DS_Store` nie liczy się do niepustego katalogu (Finder dokłada go po samym otwarciu folderu); sprawdzone w `emptyNewDirectoryIsTreatedAsMissing`, bez nowego `@Test`.
2. Migracja katalogu **i kluczy** jest pomijana przy `YASCRIBE_DATA_DIR`, w trybie migawek (`YASCRIBE_SNAPSHOT_DIR`) i przy sondach (`YASCRIBE_PROBE`). Plan bramkował tylko katalog; klucze dev-owe dzielą jednak usługę pęku ze starą aplikacją, więc każdy `run.sh` kopiowałby prawdziwe klucze i wywoływał okna dostępu. Konsekwencja: uruchomienie z `.devdata` w nowej aplikacji nie ma kluczy (wpisuje je użytkownik). Interpretacja spec poprawki 2 („`.devdata` nieimportowane"); do odwrócenia jednym warunkiem.
3. Kod podłączenia w `LegacyMigration.swift` (nie wprost w `YascribeApp.swift`); alerty aktywują aplikację przed `runModal`.
4. Wykrycie działającej starej aplikacji także po nazwie pliku wykonywalnego `MeetNotesApp` (spec mówi o procesie), nie tylko po bundle ID.

## Sprawdzone ręcznie (read-only)

- Brak ścieżek bezwzględnych do `…/Application Support/MeetNotes` w plikach JSON starego katalogu (`grep -rl`, 0 trafień). `settings.recordingsPath` ma domyślnie `nil` (`AppModel` zapisuje `nil`, gdy wybrano domyślny folder), więc po przeniesieniu nie dynda. Użytkownik z własnym folderem nagrań nie jest dotknięty, bo ten folder leży poza katalogiem danych.
- `~/Library/Application Support/Yascribe` nie istnieje (więc prawdziwa migracja nie trafi w `.bothHaveData` z tego powodu). Stary katalog zawiera dziś tylko `providers.json` i jedną kopię `providers.json.corrupt-…`.
- `UserDefaults` zmienia domenę razem z bundle ID. Resetują się: `systemAudioVerified` (arkusz Setup pokaże się raz; uprawnienia TCC i tak resetują się przy nowym bundle ID), zapamiętana pozycja pigułki nagrywania. Nic krytycznego.

## Ryzyka do T9 (kroki użytkownika) i decyzje

- Jeśli stara MeetNotes uruchomi się po migracji (Launch at login albo z przyzwyczajenia), odtworzy `MeetNotes/providers.json` (zapis rekordu modelu lokalnego przy wczytaniu), a Yascribe od tej chwili przy każdym starcie pokaże „Two data folders found". **Krok T9:** przed pierwszym startem Yascribe wyłączyć w starej MeetNotes „Launch at login" i potem jej nie otwierać.
- Wybór „Use Yascribe data" nie jest zapamiętywany, więc alert wraca przy każdym starcie, dopóki jeden z katalogów nie zniknie. Czy zapamiętywać — decyzja użytkownika; na razie nie.
- Kod odmowy w oknie pęku („Deny") nie był zmierzony w T0; testy używają kodu umownego `-25293`. Aplikacja nie rozgałęzia po kodzie. T9 krok 4 sprawdza komunikat na żywo.
- Alerty (`NSAlert` w `App.init`) bez testu jednostkowego: pilnuje ich odbiór T9. Ryzyko: alert w `init` przed pierwszym oknem; zmniejszone przez `NSApplication.shared.activate()` przed `runModal`, do potwierdzenia na żywo.
- Pierwsze uruchomienie z kluczami: macOS zapyta o dostęp do starej pozycji osobno dla każdego dostawcy z kluczem (zmierzone w T0). `unreadable` wraca przy następnym starcie.
