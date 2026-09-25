# Konsultacja — pytania z `S3-S4-poprawki.md`

**Konsultant:** Claude (K), Opus 5.5, 2026-09-25. **Stan:** `faza1` @ `93b68cc`, `scripts/test.sh` 52/52 (wg raportu).
Tylko opinia, nic nie wdrożone.

## Kolejność wykonania

Najpierw pkt 3+4 (jedna zmiana w `CLI.swift`, **bez nowych `@Test`**), potem pkt 1 (liczby). Jeśli 3/4 dołożą test,
przesunięcie w pkt 1 nie będzie już +5 — liczby zmieniać na końcu, od faktycznego wyniku `scripts/test.sh`.

## 1. Liczby testów (+5) — zgoda, wariant (a)

**Wariant (a): jednorazowo przesunąć liczby w planach i runbooku.** Nie (b): reguła „+5” to rachunek w pamięci
w każdej sesji F, także przy krokach mutacji („Przywróć; `58/58`”), a następna runda poprawek dołoży kolejne „+N”.
(a) to jednorazowa, mechaniczna zmiana, którą sprawdza jeden `grep`.

Zmienić (numery linii z `93b68cc`):

| Plik | Miejsca | Zmiana |
|---|---|---|
| `2026-09-25-faza1-runbook.md` §2 | kolumna „Testy po sesji”: S6, S7, S8, S10, S11, S12, S14, S15, S16, S18 | 65→70, 70→75, 92→97, 99→104 |
| `…-02-dostawcy-i-presety.md` | l. 542, 768, 770, 1014, 1016, 1080 | 51→56, 58→63, 65→70, 70→75 |
| `…-03-potok-transkrypcji.md` | l. 438, 440, 538, 1051 (też „84 z poprzednich” → 89), 1055, 1140 | 80→85, 84→89, 92→97, 99→104 |
| `…-04-powloka-aplikacji.md` | l. 1148 | 99→104 |
| `…-05-poprawki-po-recenzjach.md` | tabela l. 23–25; l. 410, 701, 703, 1045 | 70→75, 99→104 |

**Nie zmieniać** (historia, nie oczekiwania): odhaczone kroki planu 01 i E1 (`47/47`, l. 243/245), wiersze S1–S4 runbooka,
statusy „przebieg kontrolny … 99/99” (plan 05 l. 15, 39, 258, 423, 716; plan 00 l. 73, 82; runbook l. 141). Pod tabelą
§2 runbooka dopisać jedno zdanie: „Liczby od S6 przesunięte o +5 po poprawkach S3+S4 (decyzja użytkownika z 2026-09-25)”.
Wiersz S4 (47) zostaje — tak było w chwili zakończenia sesji.

Sprawdzenie po zmianie: `grep -nE '\b(51|58|65|80|84|92|99)/\1\b'` na planach 02–05 nie zwraca nic poza wierszami
historycznymi z listy wyżej. Nazwy 5 nowych testów nie występują w żadnym planie (sprawdzone), więc +5 jest stałe dla
wszystkich dalszych kroków.

**§0:** spełnione. Zasada brzmi „plan zmienia się tylko przez użytkownika” — chodzi o decyzję, nie o to, kto pisze.
Użytkownik zatwierdził, orkiestrator jedynie wykonuje. Warunek: zgoda ma być zapisana (ten plik + commit, który go
przywołuje, np. „Plany: liczby testów +5 po S3/S4 (decyzja użytkownika)”), a zmiana ograniczona do liczb z tabeli.
Samodzielna zmiana czegokolwiek innego w planie dalej łamałaby §0.

## 2. P11 (dziennik poza blokadą) — nie teraz; do backlogu, z wyzwalaczem

Nie do E2 (dostawcy) ani E4 (UI) — żadne z nich nie dotyka `SessionRecorder`, a dopisanie zmian do sesji literalnego
przepisywania łamie §0 pkt 2. Wpis do backlogu (po D3 / faza 2).

**Wyzwalacz, który robi z tego zadanie wcześniej:** A10 (S5) pokaże w T6 lub T8 luki albo nieregularne kotwice
`track.clock` bez przyczyny sprzętowej. `handle()` wykonuje fsync pod blokadą rejestratora przy każdej luce i kotwicy
(co ~10 s na tor), a woła go kolejka IOProc HAL (`HALCapture`, `.userInteractive`) i wątek `installTap` — zablokowany
fsync opóźnia wtedy pozostałe tory. To nie jest wątek czasu rzeczywistego, więc na dziś to ryzyko, a nie błąd.

**Minimalny zakres, jeśli wejdzie:** w `handle()` i `tick()` pod blokadą tylko zbierać zdarzenia do lokalnej tablicy,
a `append` robić po `unlock()`. `finish()` pod blokadą ustawia `finishing`; append po `finishing` odrzucić (żadnego
`track.failed` za `session.ended`, żadnego zapisu do zamkniętego uchwytu). Jeden test: zdarzenie z `tick()` wywołanego
po `finish()` nie trafia do dziennika.

## 3. Bug `positional` — zgoda na poprawkę, ale teraz, nie w B4/C4

Nie wrzucać tego do B4/C4: to sesje, w których K przepisuje kod dosłownie (B4 bez przeglądu), a nieplanowana zmiana
w środku zaciera, co przegląd S12 ma sprawdzić. Lepiej osobny mały commit w `CLI.swift` jeszcze w tej rundzie
poprawek, przed S6.

**Jak:** jeden zbiór opcji z wartością, **od razu z opcjami z B4/C4**:
`static let valued: Set = ["--seconds", "--silence", "--max-lag-ms", "--language", "--shape", "--run"]`.
`positional` pomija element stojący zaraz po opcji z tego zbioru. Sygnatura bez zmian → kod B4/C4 (`positional(args, n)`,
`option(...)`) wchodzi dosłownie i działa bez żadnej zmiany w planach. Przy okazji `-3` z `--max-lag-ms -3` przestaje się
liczyć jako argument pozycyjny.

**Ryzyko dla B/C:** niskie. Wszystkie wywołania w planach (A10, B4, B5, C4, C5) mają opcje na końcu, więc wynik się nie
zmienia. Jedyna pułapka: opcja z wartością spoza zbioru dodana w przyszłym planie wróci do dzisiejszego zachowania, gdy
ktoś postawi ją przed ścieżką. Dymny test w raporcie (bez sprzętu):
`fit --max-lag-ms 100 /nie/ma/a /nie/ma/b` → błąd o `/nie/ma/a`, nie o `100`.

## 4. Nieznane opcje — zgoda, jeden globalny zbiór, nie listy per polecenie

Listy per polecenie wymagałyby, żeby B4/C4 rejestrowały swoje opcje, a ich kodu z planu tego nie robią → albo
zmiana planów, albo nowe polecenia bez walidacji. Prościej: w `main` każde `--x` spoza
`valued ∪ ["--no-aec", "--no-system"]` → komunikat, `usage`, `exit(64)`. Ten sam zbiór co w pkt 3, jedna linia
sprawdzenia; obejmuje od razu `models`/`probe`/`transcribe`/`session-from-file`.

Nie łapie „dobrej opcji przy złym poleceniu” (`summarize x --seconds 5`) — nieszkodliwe, per polecenie niewarte kodu.

**Ryzyko dla B/C:** B4 używa tylko `--language`, C4 `--language`, `--shape`, `--run` — wszystkie w zbiorze. Gdyby
przyszły plan dodał nową opcję, dostanie głośne `64` i STOP, a nie cichy błąd — to akceptowalne. Dymny test:
`record /tmp/mn-x --second 5` → 64, katalog nie powstaje.

## Ryzyka

- **Kolejność:** jeśli pkt 3/4 dostaną `@Test` (np. parser przeniesiony do biblioteki), przesunięcie w pkt 1 będzie inne
  niż +5. Liczyć od faktycznego wyniku po pkt 3/4.
- **Nadgorliwy `sed`** w pkt 1 może trafić w historyczne „99/99” (statusy przebiegu kontrolnego). Zmieniać tylko miejsca
  z tabeli, potem sprawdzić `git diff --stat` (5 plików) i `grep`.
- **P11 w backlogu** zależy od tego, czy A10 przejdzie T6/T8 czysto. Orkiestrator powinien przy S5 jawnie sprawdzić luki
  i kotwice pod tym kątem i przy wątpliwości wrócić do tego punktu.
- **Brak testu jednostkowego parsera CLI** (cel wykonywalny nie ma testów w `scripts/test.sh`) — pkt 3/4 sprawdzają tylko
  dymne wywołania w raporcie. Świadomy kompromis; parser warto przenieść do biblioteki dopiero wtedy, gdy urośnie.
