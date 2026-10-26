# Recenzja planu fazy 1.5 MeetNotes — Hermes (space-bunny)

> Recenzja bez wykonania i bez zmian w planie ani kodzie. Stan: gałąź `faza15`, commit `2e9df0d`.
> Sprawdzone: `Spec §3` (decyzje 1–25), `§8` (bramki 1–18), plany `00`–`04`, `scripts/test.sh`,
> `Package.swift`, `Sources/` (Providers, Transcription, Recording, SessionFormat, App), `Tests/`.
> Weryfikacje wykonane: odpalony `swift build --build-tests` (Build complete), policzone `@Test`
> w repo (111), uruchomiony stub `AttributedString(markdown:options:)` na przykładzie testowym
> z planu, uruchomiony `urlcheck` (hipoteza „Recovered"), policzone `maskedKey`/`fourCC`.
> **Niesprawdzone:** kompilacja nowego targetu `MeetNotesNotes` (kod nie istnieje — ocena
> statyczna), zachowanie `NSPanel` poza ekranem (T0 spike), wyniki modeli (T11).

## Werdykt

**Do drobnych poprawek, ale jeden błąd blokujący w T4.** Plan jest wyjątkowo spójny: pokrycie
25 decyzji speca i 18 bramek jest kompletne, licznik 111 → 177 arytmetycznie się zgadza
(sprawdzone: 111 + 7 + 4 + 3 + 3 + 12 + 9 + 12 + 6 + 5 + 1 + 2 + 0 + 2 = 177), przydział modeli
jest czysty, kolejność zależności poprawna. Jeden konkretny błąd w teście T4 nie da się policzyć
za prawdziwy wynik — musi zostać poprawiony przed startem.

## Co jest dobre (nie ruszać)

1. **Pokrycie decyzji 1–25 jest kompletne i numerowane.** Sprawdziłem każdą decyzję §3 speca
   wobec planów: 8/13/23 → T1, 12 → T2, 17 → T0, 7 → T3/T4, 2/3/9/10/11/16/21/22 → T5A/T5B,
   5/18/19/20 → T6, 24 → T7, 6/14 → T8/T9, 4/15 → T10, 25 → §0.4. Decyzja 1 (transkrypt na żywo,
   Resume) świadomie poza zakresem i tak opisana w specu §2.
2. **Reguła liczby testów faktycznie działa.** Zweryfikowałem, że `scripts/test.sh` liczy
   deklaracje `grep -rhE '^[[:space:]]*@Test' Tests` i że **błąd kompilacji w kodzie aplikacji
   (`MeetNotesApp`, cel `executableTarget`) jest łapany** — wstrzyknąłem błąd do `AppModel.swift`
   na kopii repo i `test.sh` zakończył się `error: Build failed`, nie „zielonym" przebiegiem.
   To znaczy, że bramka „kod w planie się kompiluje" faktycznie ma zęby, a nie jest pozorem.
3. **Mutacja „maksimum zamiast ostatniej porcji" (T10) jest dobrze wymyślona** — pilnuje
   semantyki („wskaźnik ma opadać z ciszą"), a nie tylko istnienia pola. Ten sam wzorzec
   w T2 (`return all` zamiast filtra) i T6 (usunięcie pasma długości).
4. **Sprawdzone na żywo fakty techniczne.** `MarkdownBlocks.group` daje dokładnie to, czego
   wymaga test: zagnieżdżona pozycja ma `presentationIntent` `[…, listItem(1), unorderedList,
   listItem(1), unorderedList]` (głębokość 1), numerowane listy mają `listItem(1)/listItem(2)` +
   `orderedList`. `fourCC(2003334207) == "wht?"` — potwierdzone bajt po bajcie. Plan nie zmyśla
   zachowania platformy.
5. **Hipoteza „Recovered" jest prawdziwa.** Uruchomiłem `urlcheck` z T8 kroku 2: `equal: false`,
   `listed` ma ukośnik na końcu, `built` nie ma. Plan słusznie kazał to sprawdzić przed naprawą
   i przewidział STOP, gdyby było inaczej.
6. **Lekcja E6 jest zapisana jako reguła, nie jako hasło** (przegląd, „Wspólne ograniczenia"):
   „nowe pola tylko opcjonalne + nie normalizujemy presetów przy wczytywaniu", z konkretnym
   powodem (`RunInput` porównuje pełny preset → każda zmiana daje `inputMismatch`). Test
   `phaseOnePresetJSONStillDecodes` dodatkowo robi round-trip `encode → decode` i porównuje
   równość — to pilnuje dokładnie tego, czego E6 wymaga.
7. **STOP-y są tam, gdzie trzeba, i mają właściciela** (przegląd §0, tabela). Wyjątek przez
   słusznie opisany: T1–T12 mają ⚠️ (kod nieskompilowany), więc wykonawca ma pozwolenie na
   minimalną naprawę kompilacji, ale nie na cichą zmianę zachowania.

## Uwagi

### 1. T4 krok 1 — test `keychainFailureIsNotShownAsNoKey` nie może przejść · **BLOKUJĄCE**

**Miejsce:** plan `02-presety-i-ustawienia.md`, T4 krok 1, `SettingsLogicTests.swift`.

**Problem.** Test asertywnie porównuje z oczekiwaną wartością, która nigdy nie powstanie:

```swift
#expect(KeyStatus.of { "«redacted:sk-…»" } == .set("••••1234"))
```

`maskedKey` w `Sources/MeetNotesProviders/SecretStore.swift:67-69` to
`key.count <= 4 ? "••••" : "••••" + key.suffix(4)`. Dla wejścia `"«redacted:sk-…»"`
(15 znaków) zwraca **`••••k-…»`**, nie `••••1234`. Policzyłem to dwiema niezależnymi drogami
(skopiowana funkcja + `python3` na tym samym napisie): `MATCH? false`.

Skutek: T4 krok 4 (`[haiku]` zielone, `128/128`) nigdy nie osiągnie `128/128`, a protokół
mówi wprost „każda inna rozbieżność = STOP". Wykonawca stanie na kroku 4 i zgłosi fałszywy
STOP, albo — co gorsza — „naprawi" test pod oczekiwanie, ucząc się, że liczby testów się sypią.

**Poprawka.** Test ma sprawdzać **kontrakt maskowania**, nie konkretne cztery znaki. Zamień
jedną linię na wersję odporną na zmianę treści przykładowego klucza:

```swift
@Test func keychainFailureIsNotShownAsNoKey() {
    struct Boom: Error {}
    guard case .set(let masked) = KeyStatus.of({ "«redacted:sk-…»" }) else {
        Issue.record("oczekiwano .set, nie .missing/.unreadable"); return
    }
    #expect(masked.hasPrefix("••••"))
    #expect(masked != "••••1234")           // test nie zależy od konkretnych 4 znaków
    #expect(KeyStatus.of { nil } == .missing)
    if case .unreadable = KeyStatus.of({ throw Boom() }) {} else { Issue.record("oczekiwano .unreadable") }
}
```

Zachowaj intencję pozytywną: **błąd pęku kluczy ≠ „brak klucza"** — to jest właśnie S18 §2.4.
Alternatywnie (mniej zmian): podmień dane wejściowe na `sk-1234567890`, wtedy `.set("••••7890")`.

### 2. T1 krok 10(a) — mutacja nie skompiluje się, więc nie „spadnie test" · **BLOKUJĄCE**

**Miejsce:** plan `01-fundament.md`, T1 krok 10(a).

**Problem.** Mutacja brzmi:

> W `Merger.swift` zamień `if let language {` na `if let language = language ?? .polish {`

`language` jest już opcjonalne (`LanguageCode?`), więc `language ?? .polish` to `LanguageCode`,
a `if let x = <nieopcjonalne>` jest w Swift błędem kompilacji. Sprawdziłem:

```
error: initializer for conditional binding must have Optional type, not 'String'
```

Ten sam błąd dotyczy `corrector(stub)`… nie, dotyczy wyłącznie tej linii. Efekt: zamiast testu
`autoLanguageSkipsTheLanguageGuard`, który ma **paść** i dowieść, że pilnuje strażnika,
dostaniemy `error: Build failed`. Zgodnie z §0.2 wykonawca traktuje to jako nieznaną
rozbieżność, czyli STOP po pięciu minutach pracy zamiast zielonej mutacji.

**Poprawka.** Użyj wariantu, który się kompiluje i daje dokładnie zamierzony efekt
(Auto dostaje strażnika PL/EN, jawne języki zachowują zachowanie):

```swift
if let language = language ?? LanguageCode.polish {
```

…co dalej nie zadziała (ta sama przyczyna). Poprawna, kompilująca się forma to odwrócenie
warunku w kodzie produkcyjnym — zamień w `Merger.swift` blok

```swift
if let language {
    utterances[i].languageMismatch = LanguageGuard.mismatch(text, expected: language)
} else {
    utterances[i].languageMismatch = LanguageGuard.nonLatinScript(text)
}
```

na

```swift
let forced: LanguageCode? = language ?? .polish
if let forced {
    utterances[i].languageMismatch = LanguageGuard.mismatch(text, expected: forced)
} else {
    utterances[i].languageMismatch = LanguageGuard.nonLatinScript(text)
}
```

i w tym miejscu zmutuj `forced` na `nil` (wtedy Auto wpadnie w `nonLatinScript` i test
`autoLanguageSkipsTheLanguageGuard` padnie na angielskiej wypowiedzi, bo `mismatch` nigdy
nie zobaczy „pl"). **Sprawdź mutację naprawdę:** `test.sh --filter` ma zwracać test *padający*,
nie build nieudany.

### 3. T5A krok 8 — licznik `140/140` nie zgadza się z planowanymi testami T5B/T6 · **WAŻNE**

**Miejsce:** przegląd §3 tabela oraz plany `03-notatki.md` T5A krok 8 i T5B krok 17.

**Problem.** Tabela §3 mówi: T5A `+12 → 140`, T5B `+9 → 149`. Przeliczyłem testy z treści
planów (nie z opisu): T5A to **6 promptu + 4 tytułu + 2 szablonów = 12** ✓. T5B to **3 store +
3 markdown + 1 search + 2 notes-dir = 9** ✓. Tu jest spójnie.

Problem jest w **kroku 18 T5B (mutacje) i T6 kroku 9**, a konkretnie w `SearchAndLayoutTests.swift`:
plik `Tests/MeetNotesNotesTests/SearchAndLayoutTests.swift` w planie zawiera **3** testy
(`searchMatchesTitleNotesSummaryAndTranscript`, `sessionSummaryIgnoresTheNotesDirectory`,
`latestRunIgnoresTheNotesDirectory`), ale opis kroku 17 mówi „9: 3 store, 3 markdown, 1 search,
2 notes-dir". „1 search" jest zaniżone — plik ma 3 testy, z czego 2 to notes-dir i 1 to search.
Suma zgadza się (9), więc **nie unieważnia to wyniku**, ale opis kroku jest mylący dla
wykonawcy, który ma policzyć `różnica = liczba nowych @Test` (reguła §0.4 / decyzja 25).
Przy pierwszej rozbieżności opisu i tabeli wykonawca ma podstawę zgłosić STOP.

**Poprawka.** Popraw opis kroku 17 na „9: 3 store, 3 markdown, 3 search/notes-dir", albo
wymień testy po imieniu (jak robi to T1 krok 8 — najlepszy wzorzec, są go 3 wystąpienia).
Dla spójności warto przejść tym wzorcem wszędzie: **lista nazw testów przy każdej bramce**,
tak jak w T1/T2. Wtedy reguła decyzji 25 jest sprawdzalna bez zgadywania.

### 4. T12 krok 6 — `MEETNOTES_APP` nie istnieje w `bundle.sh`, a dwie wersje tego samego kroku · **WAŻNE**

**Miejsce:** plan `04-powloka.md`, T12 krok 6.

**Problem.** Krok dwa razy podaje zawartość `scripts/check-bundle.sh`: najpierw wersję z
`APP="$(MEETNOTES_SIGN_IDENTITY=- scripts/bundle.sh …)"`, potem „W `scripts/check-bundle.sh`
zmień wiersz z `APP=` na: `APP="$(MEETNOTES_APP=.build/check/MeetNotes.app …)"`". Sam krok
jest wewnętrznie sprzeczny (polecenie „utwórz plik z wersją A" + „zmień go na wersję B"),
a `scripts/bundle.sh:15` ma dziś `APP=".build/MeetNotes.app"` — potwierdziłem, że zmienna
`MEETNOTES_APP` **nie występuje** w `bundle.sh` w ogóle.

Sens zmiany jest jednak bardzo dobry i ważny: `check-bundle.sh` nie może nadpisywać paczki
podpisanej „MeetNotes Dev" (ad-hoc zmienia cdhash → TCC resetuje uprawnienia do mikrofonu).
Tylko że przy obecnym stanie `bundle.sh` ustawienie `MEETNOTES_APP=…` jest **po cichu bezskuteczne**
— skrypt i tak zapisze do `.build/MeetNotes.app`, czyli dokładnie w to miejsce, przed którym
krok ma chronić. Wykonawca dostanie „OK" i uzna, że zabezpieczenie działa.

**Poprawka.** Podaj tylko wersję finalną i popraw kolejność w instrukcji:

1. `bundle.sh`: `APP=".build/MeetNotes.app"` → `APP="${MEETNOTES_APP:-.build/MeetNotes.app}"`
   (kontrakt `run.sh` bez zmian — domyślna ścieżka ta sama).
2. `check-bundle.sh` tworzy **jedną** wersję, tę z `MEETNOTES_APP=.build/check/MeetNotes.app`.
3. Dodaj do kroku jedno zdanie dowodowe: „po przebiegu porównaj `codesign -dvv .build/MeetNotes.app`
   przed i po — ta sama linia `Authority`". Plan to ma w kroku 7, ale jako weryfikację, nie
   jako kryterium kroku 6; przenieś to do kroku 6, bo to jest moment, w którym paczka jest
   nadpisywana.

### 5. T7 krok 6(f) — `run(...)` jest `private`, a plan zakłada modyfikację z zewnątrz · **DROBNE**

**Miejsce:** plan `03-notatki.md`, T7 krok 6(f).

**Problem.** `AppModel.run(sessionURL:runID:snapshot:client:)` jest `private`
(`Sources/MeetNotesApp/AppModel.swift:277`) — to się zgadza z planem (plan pokazuje zamianę
wnątrz metody, nie dodanie nowej), więc **to nie jest błąd**. Zgłaszam jako ryzyko wykonawcze:
plan w kroku 6(f) wstawia do środka `Task { … }` wywołanie
`await self.notes.afterTranscription(sessionURL:runID:snapshot:transcript:)`, co wymaga, żeby
`NotesModel` był `let` zainicjowany **przed** `init()` i żeby `notes.clientFor` było podłączone
w `init()`. Plan to robi w 6(c) — kolejność jest poprawna.

**Poprawka.** Nic nie zmieniaj w planie; dodaj do kroku 6(c) jedno zdanie: „`let notes =
NotesModel()` musi być zadeklarowane **przed** `init()`, inaczej `init` nie może podłączyć
zależności". To jest dokładnie ten rodzaj cichego założenia, o który wcześniej potykał się plan.

### 6. T8 krok 2 — hipoteza potwierdzona, ale plan mówi „test zostaje" z niejasnym uzasadnieniem · **DROBNE**

**Miejsce:** plan `04-powloka.md`, T8 krok 2 i test `directoryListingURLMatchesTheRecordingURL`.

**Problem.** Uruchomiłem hipotezę sam: **`equal: false`** — `listed` ma `/` na końcu, `built` nie ma.
Plan więc idzie dalej (`equal: false` → hipoteza potwierdzona), co jest poprawne. Ale sam test
`directoryListingURLMatchesTheRecordingURL` nie ma mutacji i niczego nie pilnuje poza tym, że
`lastPathComponent` działa. Nie jest to błąd, bo jest test pokrywający, tylko uwaga: po
potwierdzeniu hipotezy test warto oznaczyć jako „dokumentujący, nie mutacyjny", żeby ktoś za
rok nie szukał do niego mutacji, której nie da się napisać.

**Poprawka.** Jedno zdanie w kroku 2: „potwierdzone 2026-10-14 (`equal: false`); test
zostaje jako dokumentacja porównania po nazwie — dla niego mutacja nie istnieje, bo
`lastPathComponent` jest tautologią."

### 7. T11 krok 3 — skrypt analityczny nie mierzy tego, co obiecuje nagłówek · **WAŻNE**

**Miejsce:** plan `04-powloka.md`, T11 krok 3 (skrypt `stats.py`).

**Problem.** Składnia Pythona jest tu inna niż w bloku Swift, którego używa reszta planu
(`from`/`import`/`f-string` z `{x["text"]}` wewnątrz `f"..."` — to jest poprawne dla Pythona,
sprawdziłem wizualnie). Zadziała. Problem jest merytoryczny i dotyczy **metryki**, nie składni:

`non_latin_share` liczy `ord(c) > 0x24F`, czyli **wszystko poza łaciną podstawową i rozszerzeniami
do U+024F**. Dla polskiego tekstu z diakrytykami to OK, ale raport ma odpowiedzieć na pytanie
(b) „czy samo *mostly_non_latin > 0* wykrywa bełkot". Próg w skrypcie to `> 0.3`, a guard w T1
to `foreign * 2 > letters` (czyli **> 0.5**). **Skrypt mierzy inną granicę niż kod, który ocenia.**
Raport porównywałby dwie różne reguły i wniosek „fałszywe alarmy" byłby nieinterpretowalny.

**Poprawka.** Dodaj do skryptu **oba progi** i policz je osobno, żeby raport porównywał kod z kodem:

```python
def share(s):
    letters = [c for c in s if c.isalpha()]
    return sum(1 for c in letters if ord(c) > 0x24F) / max(1, len(letters)), len(letters)
# granica kodu z T1: foreign * 2 > letters, czyli share > 0.5  (i >= 4 litery)
"guard_t1": sum(1 for x in u if (sh := share(x["text"]))[0] > 0.5 and sh[1] >= 4),
# granica z kroku 3: share > 0.3
"gt_0_3":    sum(1 for x in u if share(x["text"])[0] > 0.3),
```

Bez tego T11 (jedyny pomiar decyzji 8 i 23) nie odpowiada na pytanie, które mu zadano.

### 8. T7/T8 — `SessionItem` musi zyskać pola, ale plan nie mówi, że `summary` zostaje · **DROBNE**

**Miejsce:** plan `03-notatki.md` T7 krok 6(b) i plan `04-powloka.md` T8 (`SessionRow` używa
`item.summary?.tracks`).

**Problem.** T7 krok 6(b) dodaje do `SessionItem` pola `corrected` i `notes` oraz metodę
`title`. Nie mówi nic o tym, że `summary: SessionSummary?` (używane przez `SessionRow` w T8
przez `item.summary?.crashed` i `item.summary?.tracks`) **zostaje**. Czytając krok dosłownie,
`summary` tam jest — ale wykonawca czytający „dodaj pola” przy „zastąp zawartość” może wyciąć
to przez pomyłkę, a `SessionRow` w T8 tego wymaga.

**Poprawka.** Dopisz do kroku 6(b): „`summary` zostaje — T8 czyta z niego `crashed` i `tracks`
(status wiersza i komunikat o problemie z torem)".

### 9. T0 — `Snapshots.seed` używa API, którego sygnatury nie sprawdziłem, a `init` aplikacji jest ryzykowny · **DROBNE**

**Miejsce:** plan `01-fundament.md`, T0 krok 2.

**Problem.** Dwie rzeczy, których **nie dało się rozstrzygnąć bez uruchomienia**, bo zależą od
tego, jak `App` inicjuje `AppModel` w tym projekcie: (a) `Snapshots.seed` robi
`try presets.upsert(Preset(...))` i `model.load()` — `PresetsFile.upsert` istnieje
(`Stores.swift:54`), `Provider(name:baseURL:)` i `JSONFile.save` też, więc to się spinie;
(b) proponowany `init()` w `MeetNotesApp` z `DispatchQueue.main.async { MainActor.assumeIsolated
{ … } }` **nie był skompilowany** — plan sam oznacza T0 jako ⚠️ spike i przypisuje je Opusowi
do decyzji, co jest tu właściwe.

Jedna konkretna uwaga: `Snapshots.render` używa `directory!` w dwóch miejscach
(`try FileManager.default.createDirectory(at: directory!, …)`), a `directory` jest
`static var … -> URL?`. Force unwrap jest tu bezpieczny tylko dlatego, że `runAll` wywołuje
render wyłącznie po sprawdzeniu `Snapshots.directory != nil` w `init()`. Warto to zapisać
w komentarzu, bo refaktor przy okazji zrobi z tego crash.

**Poprawka.** W T0 krok 2 dopisz: „`directory!` jest bezpieczne: `runAll` wchodzi tylko
przez `init()`, który sprawdza `directory != nil`; przy wywołaniu `render` z testu/komendy
guard należy dodać w `runAll`". Reszta T0 to i tak spike pod Opusem.

### 10. Licznik testów: brak weryfikacji, że plan nie koliduje z `test.sh --filter` przy T12 · **DROBNE**

**Miejsce:** plan `04-powloka.md` T12 krok 6 (dopis `check-bundle.sh` do `test.sh`) i krok 7.

**Problem.** Krok 6 dopisuje `scripts/check-bundle.sh || { …; exit 5; }` **na samym końcu**
`test.sh`, po `echo "test.sh: $RAN/$EXPECTED …"`. `test.sh` kończy się tym `echo` (ostatnia
linia, `exit` nie ma — kod wyjścia to kod `echo`, czyli 0). Dopisek po `echo` **wykona się**,
ale wtedy bramka zgłasza sukces (`echo` już wydrukowało `177/177`) zanim bundle w ogóle
zostanie sprawdzony. Przy awarii bundle czytelnik widzi `177/177` i potem `exit 5` — niespójne.
Plan słusznie zauważa, że `--filter` kończy się wcześniej (linie 40–42 `test.sh`).

**Poprawka.** Przenieś bramkę bundle **przed** komunikat końcowy, np. dopisz przed linię
`echo "test.sh: $RAN/$EXPECTED …"`, albo jawnie zaznacz w planie, że kolejność jest celowa
i czytelnik ma patrzeć na kod wyjścia, nie na `echo`. Druga opcja jest gorsza — pierwsza jest
jednolinijkowa.

## Odpowiedzi na pytania z §5 przeglądu

Plan `00-przeglad.md` §5 zawiera **6 pozycji, wszystkie zamknięte** i wprowadzone do planu
i speca — żadna nie jest otwarta. Dla porządku, co faktycznie zrobiłem z każdą:

1. **Auto a alfabet** → T1 (`nonLatinScript` + testy `nonLatinScriptIsDetectedByMajority`,
   `autoLanguageFlagsGibberishInAnotherScript`, mutacja „każdy cudzy znak"). Pokryte.
2. **Reguła liczby testów** → §0.4, tabela §3, kroki bramkowe. Pokryte — z zastrzeżeniem
   z uwagi 3 (opisy kroków powinny wymieniać nazwy testów).
3. **T5A + T5B w jednym zadaniu** → tak, jeden przegląd Opusa po 5B (T5 krok 20). Pokryte.
4. **Autotytuł: trzy próbki po ~2000** → T6, `AutoTitle.sample`, test
   `autoTitleSamplesTheStartMiddleAndEndOfALongTranscript`. Pokryte.
5. **Zamrożony preset bez `summary`** → T7, `SummaryModel.resolve`, 3 testy + mutacja
   „usunięcie pętli zastępstwa". Pokryte.
6. **Poza planem** (historia wersji, map-reduce, wybór mikrofonu) → zgodne ze specem §2 i §10.
   Pokryte.

**Jedno pytanie otwarte, którego §5 nie zawiera, a które warto rozstrzygnąć przed T4:**
w T4 krok 7 `SettingsView.commit()` robi `model.settings.embedding = draft.embedding; model.save()`.
`AppModel.save()` zapisuje **wszystkie cztery** pliki (`AppModel.swift:104-113`), więc Cancel
w sekcji Archive nie cofnie zmian w innych sekcjach — ale jedyne pola `GlobalSettings` to
`embedding` i `defaultPresetID`, a ten drugi edytor nie zmienia. **Sprawdzone: to jest bezpieczne.**
Reguła z planu („Save/Cancel obejmuje tylko sekcję Archive") jest więc wykonalna bez dodatkowej
pracy — nie mam tu zastrzeżeń.

## Rekomendacja

Popraw **uwagi 1 i 2** (obie blokujące, obie kosztują kilka minut), potem **uwagi 3, 4 i 7**
(spójność opisów, skrypt bundle, metryka pomiaru T11 — ta ostatnia jest jedyną, która realnie
psuje wniosek z jedynego pomiaru w fazie). Uwagi 5, 6, 8–10 są kosmetyczne i mogą zostać
wprowadzone przy okazji.

Nie wykonuję żadnego zadania. Decyzje należą do użytkownika.

recenzja: 10 uwag
