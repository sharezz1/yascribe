# Przegląd S11 — runda 2 (po poprawkach E6)

**Zakres:** `git diff e111fe9..HEAD` (E6 = `d66c088`), raport `S11.md` sekcja „E6 — poprawki po przeglądzie i checku S11", plan 05 §E6 (kroki 1–5), plan 00 §4.
**Domknięcie:** `S11-przeglad.md` uwagi 1–5 (uwaga 6 świadomie odłożona do D — poza zakresem rundy), `checks/S11-check.md` #3.

**Testy:** `scripts/test.sh` → ostatnia linia: `test.sh: 109/109 testów uruchomionych i zaliczonych.` (kod 0). Liczba deklaracji `@Test` = 109 — zgadza się z raportem.

**Zgodność kod ↔ plan E6:** kroki 1–5 weszły zgodnie z literałami planu (porównane linia po linii): `CrosstalkFilter: Codable, Equatable, Sendable`; pole `crosstalk` w `RunInput` po `maxChunkSeconds`; `crosstalk: crosstalk` w `run(progress:)`; drugi przypadek w `resumingWithADifferentPresetIsRefused` z `correlationThreshold = 0.5`; własna mowa 7–9 s (500 Hz zamiast echa 300 Hz) w `crosstalkFromSpeakersIsDroppedBeforeASR`; `-mmin +60` przed `-exec`, `trap` pod `mktemp`, komentarz nad `find` dosłownie z planu; komentarz `tracks(in:)` z regułą awarii. Diff planu 05 to wyłącznie `- [ ]` → `- [x]`. Twierdzenia raportu E6 (linie mutacji, 109 bez nowych `@Test`, „42 przed i 42 po") potwierdzone.

**Mutacje — odtworzone niezależnie w tej rundzie (każda cofnięta `git checkout` zaraz po sprawdzeniu; drzewo po wszystkich czyste):**

| # | Mutacja | Test | Wynik |
|---|---|---|---|
| 1 | `RunInput(…, crosstalk: CrosstalkFilter(), …)` zamiast `crosstalk: crosstalk` | `resumingWithADifferentPresetIsRefused` | ✘ RunnerTests.swift:166:11 — „an error was expected but none was thrown" |
| 2 | `return best < correlationThreshold && false` w `CrosstalkFilter.keep` | `crosstalkFromSpeakersIsDroppedBeforeASR` | ✘ RunnerTests.swift:143 (`!me.isEmpty`, `me → []`) |
| 3 (regresja) | `correlationThreshold = 0.8 → 1.1` (dawna mutacja E3 krok 8) | `crosstalkFromSpeakersIsDroppedBeforeASR` | ✘ RunnerTests.swift:144 (`me.allSatisfy { $0.start > 6.5 }`) |

Obie mutacje E6 dają czerwień tam, gdzie mówi raport. Przerobiony test nadal łapie też dawną mutację progu (kolumna `allSatisfy { .them }` zastąpiona asercją na start `.me` — przechwytuje to samo). Przy mutacji 2 pierwsza asercja (`.them`) przechodzi, a `me` jest puste — czyli test odróżnia „odfiltrowano" od „nie ma nic", o co pytał check #3.

**Sprzątanie (`scripts/test.sh`):** `ls "$TMPDIR"/tmp.* | wc -l` = 42 przed pełnym przebiegiem i 42 po (także po trzech przebiegach z `--filter`) — `trap` domyka wyciek na wszystkich ścieżkach wyjścia. Nowa linia `find` sprawdzona na katalogach próbnych: katalog sprzed 2 h (`mn-AABBCCDD-…`) usunięty, świeży (`mn-tr-FFEEDDCC-…`) nietknięty — `-mmin +60` chroni równoległy przebieg. Katalogi testowe rosną do ~190 w `$TMPDIR`, ale to wzorzec sprzątania „na początku następnego przebiegu" z E5, nie nowy wyciek.

**Zapisy:** wszystkie w `sesja/runs/<runID>/` (input.json, chunks/, transcript.json, run.json); walidacja `runID` przed każdym zapisem. Poza sesją: wyłącznie `OUT` z `mktemp` (sprzątany przez `trap`). Brak nowych wyścigów ani połkniętych błędów w diffie.

## Domknięcie uwag z rundy 1

| Uwaga | Stan | Uzasadnienie |
|---|---|---|
| 1. `crosstalk` poza `RunInput` | **domknięta** | Pole dodane, `CrosstalkFilter` jest `Codable, Equatable`; test porównuje `RunInput` przy różnych progach; mutacja 1 czerwona na :166 (udowadnia, że to pole — a nie inna różnica — daje `inputMismatch`; `snapshot()` ma stałe UUID, więc trzeci przypadek izoluje sam `crosstalk`) |
| 2. sprzątanie kasuje katalogi żywego przebiegu | **domknięta** | `-mmin +60` przed `-exec`; empirycznie stary katalog znika, świeży przeżywa |
| 3. wyciek `OUT` z `mktemp` | **domknięta** | `trap 'rm -f "$OUT"' EXIT` pod `mktemp`; 42 → 42 plików `tmp.*` po pełnym przebiegu i po `--filter` (wcześniej przy każdym `--filter`/padzie przybywał jeden). Kosmetyka: linia 45 `rm -f "$OUT"` jest teraz redundantna (nieszkodliwa). Pozostałość po wcześniejszych sesjach: 42 pliki `tmp.*` sprzed poprawki nikt nie sprząta — do jednorazowego ręcznego usunięcia |
| 4. komentarz wzorca sprzątania nieprecyzyjny | **domknięta** | Nowy komentarz dokładnie opisuje zbiór dopasowań (`mn-[prefiks-]<UUID wielkimi literami>`, sufiksy bez UUID przeżywają); planowy `/tmp/mn-corpus-<n>` (plan 03:1172) nie ma UUID, więc jest bezpieczny. Ryzyko szczątkowe: `mn-corpus-<UUID>` (gdyby kiedyś powstał) nadal wpada w regex — komentarz już temu nie przeczy |
| 5. komentarz `tracks(in:)` bez reguły awarii | **domknięta dla kodu**, patrz uwaga 1 poniżej dla dokumentów | Komentarz mówi o `mic_aec` z awarią → `mic_raw`, zgodnie z propozycją |
| check #3 (test nie odróżnia odsiewu od wyłączenia mikrofonu) | **domknięte** | Własna mowa w ciszy systemu + asercje `.them`/`!me.isEmpty`/`.me` po 6,5 s; mutacja `&& false` czerwona na :143 (dawniej zielona) |

## Nowe uwagi

### 1. Plan 03 nadal powtarza regułę mówców bez wariantu awarii — resztka uwagi 5 niedomknięta
- **Plik:** `docs/superpowers/plans/2026-09-24-faza1-03-potok-transkrypcji.md`
- **Miejsce:** linia 18 („Mówcy z kanałów: `system` → „Them", `mic_aec` → „Me", a gdy go brak — `mic_raw`.")
- **Problem:** uwaga 5 pytała wprost o „opis w spec §3, jeśli go powtarza"; E6 krok 4 (literal planu) objął tylko komentarz w kodzie. Linia 18 to kopia tej samej reguły w wersji dwuprzypadkowej — po E3 obowiązuje trzeci przypadek (`mic_aec` z zapisaną awarią → `mic_raw`). To ten sam „komentarz w tyle za zachowaniem", tylko w dokumencie; plan 03 jest wskazówką dla wykonawcy C4/C5, więc fałszywa reguła może wrócić do nowego kodu.
- **Propozycja:** dopisać wariant awarii: „…`mic_aec` → „Me", a gdy go brak albo gdy jego ścieżka zanotowała awarię — `mic_raw`".

### 2. E6 samo łamie format `input.json`, a uwaga 6 (wersja formatu) jest odłożona do D — raport E6 nie odnotowuje skutku
- **Plik:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift` + `Sources/MeetNotesProviders/Stores.swift`
- **Miejsce:** nowe obowiązkowe pole `RunInput.crosstalk` (linia 16), `guard saved == input` (linia 84–85), `JSONFile.load` (Stores:38–41 — rzuca przy błędzie dekodowania, `default` tylko przy braku pliku)
- **Problem:** odłożenie uwagi 6 do powłoki (D) było udokumentowane i świadome, ale zakładało, że format `input.json` pozostanie stabilny do D. E6 właśnie ten format zmienia: każdy `input.json` zapisany przed E6 (runs w `.devdata`/sesjach użytkownika) przy wznawianiu skończy surowym `DecodingError: keyNotFound(crosstalk)` zamiast czytelnym `inputMismatch` — dokładnie mechanizm z uwagi 6, wywołany przez samą poprawkę. Dziś nie ma w drzewie czytnika poza `run()` i testy zakładają świeże sesje, więc skutku bieżącego brak; ale decyzja „bez wersji formatu" zaczyna się zużywać przy każdym nowym polu (E3: `preset`, E6: `crosstalk`).
- **Propozycja:** minimalnie — zanotować w raporcie/planie 05: „E6 zmienia format `input.json` — runs sprzed E6 przelicz od nowa" (uczciwe wobec odłożonej uwagi 6); taniej niż migracja byłoby dodać już teraz samo `formatVersion: Int` do `RunInput`/`RunMetadata`, żeby kolejne pole nie powtarzało tego samego problemu.

### 3. Komentarz `RunError.inputMismatch` nie wylicza nowego powodu odrzucenia
- **Plik:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift`
- **Miejsce:** linia 7 („Ten sam runID, inne wejście (preset, bramka, limit okna, ramki ścieżek) — ChatGPT #4.") vs linia 16 (`crosstalk` w `RunInput`)
- **Problem:** to sam typ zaległości co uwaga 5: komentarz dokumentujący kontrakt `inputMismatch` wymienia przyczyny odrzucenia i nie ma wśród nich progów przesłuchu, choć E6 dodał je do równania (i test je egzekwuje). Czytelnik błędu w CLI/S12 nie dowie się, że filtr też unieważnia wznawianie.
- **Propozycja:** „…(preset, bramka, limit okna, progi przesłuchu, ramki ścieżek)".

### 4. Test E6 ma sztywne indeksy ramek sprzężone z fixture — zmiana układu sygnału zamieni czerwień asercji na crash
- **Plik:** `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`
- **Miejsce:** linia 138 (`mic.replaceSubrange(112_000..<144_000, with: tone(seconds: 2, rate: 16_000, hz: 500))`)
- **Problem:** zakres 112 000..<144 000 (= 7–9 s przy 16 kHz) jest wpisany liczbami i zależy od długości `sys` (2 s + 5×0,7 s + 5 s = 10,5 s = 168 000 ramek). Dziś mieści się z zapasem 24 000 ramek do końca bufora i trafia w ciszę systemu (5,2–10,5 s) — działa. Ale każde skrócenie ogona ciszy w fixture (albo zmiana `rate`) da `replaceSubrange` poza zakresem — trap w runtime zamiast czytelnej czerwieni asercji, a test łapie mutacje tylko przy oryginalnym układzie. To nie jest błąd dzisiaj; to pułapka na następną edycję tego testu.
- **Propozycja:** liczyć zakres z sekund (`Int(7 * 16_000)..<Int(9 * 16_000)`) i/lub dodać `#expect(mic.count >= 144_000)` przed wstawką; alternatywnie dokleić ton do `mic` zamiast podmieniać zakres.

## Zgodność deklaracji raportu E6 (skrót)

| Deklaracja S11 (E6) | Stan |
|---|---|
| Krok 1–4 zgodne z planem | potwierdzone (literał po literale) |
| Mutacja 1 → ✘ RunnerTests:166 | potwierdzona niezależnie (ten sam komunikat) |
| Mutacja 2 → ✘ RunnerTests:143 (`!me.isEmpty`) | potwierdzona niezależnie |
| „Bez nowych `@Test` (109)" | potwierdzone (109 deklaracji, 109/109) |
| „Sprzątanie: 42 przed i 42 po (nie rośnie)" | potwierdzone (42 → 42 po pełnym przebiegu i po `--filter`; `trap` działa) |
| Odchylenie 1 (odtworzenie zmian po `git checkout`) | brak skutku w drzewie końcowym: diff `e111fe9..HEAD` kompletny, drzewo po moich mutacjach czyste |
