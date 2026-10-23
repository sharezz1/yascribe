# F21 T9 — odbiór agenta fazy 2.1a „Słownik”

> 2026-10-23. Wykonał agent (Sonnet 5.5) na gałęzi `faza21-slownik` (nie scalonej do `master`), po `04ea8d3`. Kod CLI i fixture: `76c921f`;
> sceny migawek: `4bfb2fa`. Spec: [faza21-slownik-design](../specs/2026-10-23-faza21-slownik-design.md) (§8), plan: [faza21-slownik](../plans/2026-10-23-faza21-slownik.md).
> **Prywatność:** sesja `62de` jest prawdziwym nagraniem użytkownika (`.devdata/`, poza repo); w raporcie są tylko zliczenia słów ze słownika, nie treść.
> **Czego nie robiłem:** nie wpisywałem prawdziwych Termów ani Aliasów, nie klikałem w prawdziwej aplikacji (`.app`), nie nagrywałem, nie wołałem API,
> nie ruszałem pęku kluczy, TCC ani Ustawień systemowych. Zrzuty migawek są w `.design/review/` (poza git), obejrzane przez agenta.

## 0. Wynik w skrócie

| Krok (spec §8) | Wynik |
|---|---|
| 8.1 Sesja `62de` pod słownikiem testowym (CLI, surowy i poprawiony) | **zaliczone** — po Replacement 0 wystąpień wszystkich Aliasów, niezerowe `Zowie`, `Jarek`, `Zoom` w obu wariantach |
| 8.1 w UI (migawki: widok surowy, poprawiony, preset bez korekty) | **zaliczone** na wymyślonym krótkim transkrypcie; **mutacja kontrolna** (Replacement wyłączony w `AppModel.transcript(of:corrected:)`) przywraca stare zapisy we wszystkich trzech scenach |
| 8.2 Testy jednostkowe (risky, idempotencja, granice słów PL, najdłuższy Alias, import idempotentny) | **zaliczone** — `ReplacementTests`, `UserDictionaryTests`, `DictionaryTransferTests` w pełnym przebiegu |
| 8.3 Przycinanie do kontekstu 4096 i licznik „N terms don't fit” | **zaliczone** — test `capturedCorrectorRequestListsExactlyThePrunedTerms` (Task 6) + scena `dictionary-list` (60 Termów wypełniacza przy kontekście 2048; Task 8) |
| Pełny przebieg `scripts/test.sh` | **704/704** (te zmiany nie dodały testów: CLI i sceny migawek nie mają własnych `@Test`) |
| 8.4, 8.5 (nagranie, Termy w zakładce, „Transcribe again…”, panele systemowe) | **czeka na użytkownika** — §4 |

## 1. §8.1 — sesja `62de` i słownik testowy (CLI)

Nowe polecenie `meetnotes-cli dictionary-check` (`Sources/meetnotes-cli/CLI.swift`, nowa zależność `MeetNotesNotes` w `Package.swift`): czyta
`replacements.tsv` (opcjonalnie `vocab_core.txt`) przez `DictionaryTransfer.importFiles`, wybiera przebieg sesji przez `RunSelection.of(session:)`
(jak aplikacja), stosuje `Replacement.apply(_:rules:)` do transkryptu surowego i do `corrected.json` i liczy całe słowa (bez względu na wielkość liter)
w tekstach wypowiedzi. Kod wyjścia 1, gdy po Replacement został Alias albo zniknął Term. Żadnej logiki podmiany ani importu nie duplikuje.
Fixture: `scripts/fixtures/dictionary-62de.tsv` (`Zoe`/`Zoey`/`Zoim` → `Zowie`; `Jarla` → `Jarek`; `Doomem`/`Zoomem` → `Zoom`; format `fraza<TAB>zapis`).

```
B=$(swift build --disable-keychain --show-bin-path)/meetnotes-cli
$B dictionary-check .devdata/sessions/2026-10-21T07-29-08Z-62de --replacements scripts/fixtures/dictionary-62de.tsv
przebieg: 2026-10-21T07-46-31Z-c848, import: 3 terms, 6 aliases, 0 risky left off, 0 conflicts, 0 rejected
Term  Zowie    raw 0 -> 6  |  corrected 0 -> 6
Alias Zoe      raw 3 -> 0  |  corrected 3 -> 0
Alias Zoey     raw 1 -> 0  |  corrected 1 -> 0
Alias Zoim     raw 2 -> 0  |  corrected 2 -> 0
Term  Jarek    raw 2 -> 3  |  corrected 2 -> 3
Alias Jarla    raw 1 -> 0  |  corrected 1 -> 0
Term  Zoom     raw 0 -> 2  |  corrected 0 -> 2
Alias Doomem   raw 1 -> 0  |  corrected 1 -> 0
Alias Zoomem   raw 1 -> 0  |  corrected 1 -> 0
OK: po Replacement 0 wystąpień Aliasów i niezerowe Termy        (kod wyjścia 0)
```

Obserwacje: (a) korekta modelem (`deepseek/deepseek-v4.1-flash`) zostawiła wszystkie złe zapisy — liczby w `corrected.json` są takie same jak w surowym,
więc to Replacement, a nie korekta, daje poprawne `Zowie`/`Jarek`/`Zoom`; (b) `Zowie` i `Zoom` nie występowały w sesji w ogóle (0 przed) — wszystkie
wystąpienia po Replacement pochodzą z podmiany; (c) plików sesji CLI nie zmienia (tylko czyta).

## 2. §8.1 w UI — migawki i mutacja kontrolna

W `Snapshots.swift` (po scenach słownika) trzy nowe sceny na wymyślonym transkrypcie („Zoim will send the invoice, and Jarla checks it…”,
„We can talk on Doomem tomorrow, Zoim has the link”) pod słownikiem `Zowie ← Zoim`, `Jarek ← Jarla`, `Zoom ← Doomem`; `scripts/snapshot.sh`, pliki
`.design/review/dictionary-transcript-{raw,corrected,no-correction}-{light,dark}.png`:

| Scena | Zawartość | Wynik (Read) |
|---|---|---|
| `dictionary-transcript-raw` | wersja „Original” przy dostępnej korekcie | „Zowie will send the invoice, and Jarek checks it…”, „…talk on Zoom tomorrow, Zowie has the link” |
| `dictionary-transcript-corrected` | wersja „Corrected” | te same zapisy (korekta zmieniła tylko interpunkcję) |
| `dictionary-transcript-no-correction` | aktywny preset „Polish” bez roli korekty (bez przełącznika wersji i chipa korekty) | te same zapisy — Replacement nie zależy od korekty (spec §8.1) |

Uwaga: widok „Original” też jest po Replacement — zgodnie z D8 (podmiana przy odczycie, surowy `transcript.json` nietknięty), nie błąd.

**Mutacja kontrolna** (po commicie): w `AppModel.transcript(of:corrected:)` `let result = Replacement.apply(source, rules: rules)` zastąpione przez
`let result = source`; `scripts/snapshot.sh`; trzy sceny pokazały z powrotem „Zoim … Jarla”, „Doomem … Zoim”, „Jarla” (`raw-light` i `no-correction-light`
obejrzane przez Read). `git checkout Sources/MeetNotesApp/AppModel.swift`, `git status` czysty. Ta mutacja dowodzi, że sceny rzeczywiście kontrolują
punkt odczytu, a nie fixture z gotowymi poprawnymi zapisami.

## 3. §8.2, §8.3 i pełny przebieg

- `scripts/test.sh` (pełny, na HEAD z `4bfb2fa`): `test.sh: 704/704 testów uruchomionych i zaliczonych.`, `check-bundle: OK`.
- §8.3: przycinanie polecenia korektora do budżetu dowodzi `capturedCorrectorRequestListsExactlyThePrunedTerms` (`Tests/MeetNotesNotesTests/CorrectorTests.swift`);
  licznik „N terms don’t fit” w zakładce — scena `dictionary-list` z Task 8 (słownik > 100 Termów, lokalny dostawca z Context window 2048; spec mówił 4096,
  scena używa 2048, żeby licznik był widoczny przy 60 wypełniaczach). Tu nie dubluję zrzutów.
- Zrobione i zmierzone w trakcie zadań (ledger SDD): Replacement ok. 0,19 ms na wypowiedź po filtrze wstępnym (debug, 215 Termów / 212 Aliasów, 56 sesji),
  zimne wyszukiwanie po 56 sesjach 363 ms; **pomiar tylko w debugu**, w release niezmierzony.

## 4. Co zostaje użytkownikowi (§8.4, §8.5 i nowe elementy UI)

1. **Prawdziwy słownik:** w zakładce Dictionary wpisać prawdziwe Termy i Aliasy (np. `Zowie` z `Zoey`, `Zoim`), potem **Import…** z plików GCX (`vocab_core.txt`,
   `replacements.tsv`; wielokrotny wybór w `NSOpenPanel` — klasyfikacja po rozszerzeniu `.tsv`). Sprawdzić raport importu (konflikty, odrzucone, risky wyłączone).
2. **Nagranie z wydarzeniem i korektą:** nagrać spotkanie powiązane z wydarzeniem kalendarza na presecie **z modelem korekty**; w `runs/<przebieg>/vocabulary.txt`
   sprawdzić imiona uczestników i Termy; w transkrypcie i notatce poprawne zapisy (bez korekty Attendee hint niczego nie poprawia).
3. **„Transcribe again…”** na nagraniu z 2026-10-21 z innym modelem ASR: powstaje drugi przebieg w `runs/`, bieżący transkrypt zmienia się dopiero, gdy nowy
   przebieg jest ukończony i bez luk (R23); sprawdzić też przypadek nieudanego/przerwanego przebiegu (baner „didn’t finish — showing the transcript from …”)
   i „Resume Transcription with …”.
4. **Wygląd i panele systemowe, których migawki nie weryfikują:** odcień przełącznika „On” (Task 8), `NSOpenPanel` przy Import/Export, potwierdzenie
   nadpisania przy Export…, stany banera przebiegu na prawdziwym oknie, popover „Transcribe again…” w oknie (migawka rysuje go inline), Dictionary jako czwarty
   wiersz dolnej grupy paska bocznego.
5. **Decyzje:** PR i scalenie `faza21-slownik` → `master` na polecenie użytkownika; czy 2.1b (klik na słowo → Alias) i spike word boostingu zostają w 2.1, czy idą dalej.

## 5. Niezmierzone i znane ograniczenia

- Brak odbioru na żywo wszystkiego z §4; `NSOpenPanel`, potwierdzenie nadpisania, odcień przełącznika, zachowanie banera w prawdziwym oknie — tylko migawki i testy.
- Wydajność Replacement i wyszukiwania zmierzona w debugu (best-of-3); release niezmierzony. Pierwsze otwarcie dużego spotkania liczy Replacement na głównym wątku.
- Jakość na prawdziwych danych: tylko słownik testowy (6 Aliasów) na jednej sesji; prawdziwy słownik (166 Termów, 223 pary) nie był stosowany do `62de`
  (GCX nie zawiera Zowie/Jarek/Zoom — spec §8.1).
- Odłożone drobiazgi i zaparkowane uwagi recenzentów: BACKLOG „Z fazy 2.1”. Zaparkowane z uzasadnieniem w ledgerze SDD: R12 (egzotyczna para Greek
  dialytika+tonos po NFC), R19 (filtr wstępny zwraca tekst bez NFC, gdy nic się nie zmienia — kanonicznie równy), I3 (`try?` przy kompilacji wyrażenia, wzorzec z ucieczkowanych literałów).
- Znalezisko poza zakresem: pliki `ruvector.db` w `Sources/MeetNotesSessionFormat` i `Sources/MeetNotesRecording` (nieśledzone, ignorowane; pochodzą z hooka wtyczki) — do usunięcia przez użytkownika.
