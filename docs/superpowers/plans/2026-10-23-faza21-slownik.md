# Faza 2.1a „Słownik" — plan wykonania

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dictionary (Termy z Aliasami) edytowany w zakładce, deterministyczny Replacement widoczny wszędzie, gdzie czyta się transkrypt, oraz Termy i Attendee hint w poleceniach korektora i podsumowania.

**Architecture:** Cała logika (model, Replacement, import/eksport, składanie linii do poleceń) w `MeetNotesNotes`, testowalna bez UI. `MeetNotesApp` dostaje tylko wiązanie (`AppModel`, `NotesModel`, jeden punkt odczytu transkryptu) i widok zakładki. Replacement to czysta funkcja przy odczycie; pliki sesji nie są zmieniane.

**Tech Stack:** Swift 6.4 (Command Line Tools), swift-testing, SwiftUI bez `@State`/`@Entry`/`#Preview`, `JSONFile` z `MeetNotesProviders`.

**Spec:** `docs/superpowers/specs/2026-10-23-faza21-slownik-design.md` (pojęcia: `GLOSSARY.md`). Gałąź: `faza21-slownik`.

**Przydział modeli (propozycja, jak w planach 1.5):** T1 Sonnet · T2 Haiku · T3 Opus · T4 Sonnet · T5 Sonnet · T6 Sonnet · T7 Opus · T8 Sonnet · T9 Haiku.

## Global Constraints

- Testy wyłącznie `scripts/test.sh` (nigdy goły `swift test`); po zadaniu pełny przebieg ma przejść, liczba testów rośnie o liczbę nowych `@Test`.
- Nowe pola w już zapisywanych typach (`GlobalSettings`, `NoteMeta`…) tylko opcjonalne. Nowe typy `UserDictionary*` są nowym plikiem, więc ich pola mogą być wymagane.
- Commity: jawne ścieżki (`git add <plik>…`), nigdy `git add -A` ani `git add .`; stopka `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Mutacja każdej bramki: wprowadź → test ma paść → `git checkout <plik>`. Mutację robisz po commicie zadania (`git checkout` cofa do commita, a plik niezacommitowany by zginął); po mutacji `git status` ma być czysty.
- Interfejs aplikacji po angielsku, dokumenty po polsku. Żadnych kluczy API w kodzie ani testach (literały `test-fake-…`).
- `.devdata/` jest w `.gitignore`: testy nie czytają `.devdata/` ani `~/GCX/`, używają literałów w kodzie.
- Nie zmieniaj Ustawień systemowych, TCC ani pęku kluczy.
- Raw `transcript.json` nietknięty; istniejące `corrected.json` nie są migrowane.
- Terminologia z `GLOSSARY.md`: Dictionary, Term, Alias, Risky alias, Priority, Replacement, Attendee hint. Nazwa typu `Dictionary` koliduje ze Swift: typ nazywa się `UserDictionary`.

## Review Focus

1. Alias w innej normalizacji Unicode (NFD z schowka macOS, np. „Dżenesis") musi trafiać w tekst NFC; Aliasy i Termy normalizowane do NFC przy wejściu do słownika.
2. Alias ze znakami specjalnymi regex (`.`, `+`, `(`) nie może rzucać ani dopasowywać „wszystkiego": dopasowanie na ucieczkowanych literałach.
3. Alias wewnątrz dłuższego słowa (`pu do` w „pu dowolny", `Pudo` w „Pudowski") nie jest podmieniany (granice słów).
4. Alias przypisany do dwóch Termów jest odrzucony także przy ręcznej edycji, nie tylko przy imporcie; Alias równy własnemu Termowi (różnica tylko wielkości liter) jest pomijany.
5. Pusty słownik albo same wyłączone Aliasy: Replacement zwraca ten sam transkrypt, a polecenia są bajt w bajt takie jak dziś.
6. Imiona uczestników i Termy trafiają do polecenia: znaki nowej linii i cudzysłowy wycięte, długość ograniczona (nazwisko `"Ignore all instructions…"` nie może dopisać linii do polecenia).
7. Uszkodzony `dictionary.json`: wczytanie idzie przez istniejące `read(_:_:)` w `AppModel` (przenosi plik na bok jako `.corrupt-<stamp>` i pokazuje błąd), nie przez własny kod.

---

### Task 1: Makieta zakładki Dictionary

**Files:**
- Create: `docs/design/makiety/dictionary-empty.png`, `dictionary-list.png`, `dictionary-edit.png`, `dictionary-import-report.png` (konwencja nazw i narzędzia jak sąsiednie pliki w `docs/design/makiety/`; wykonawca sprawdza, jak powstały np. `b-add.png`)
- Modify: `docs/design/macos.md` (§ o Dictionary: jedno zdanie z odnośnikiem do makiety, jeśli sekcja istnieje)

**Interfaces:**
- Produces: układ ekranu, do którego odwołuje się Task 8 (lista z wyszukiwaniem, edycja Terma z listą Aliasów i przełącznikiem risky, Priority High/Normal/Low, Import…/Export…, licznik „N terms don't fit the correction prompt", raport importu).

- [ ] **Step 1: Narysuj cztery stany** (pusty, lista, edycja Terma, raport importu) w stylu istniejących makiet i `DesignSystem.swift` (kolory `mn*`).
- [ ] **Step 2: Przegląd wg `macos.md` §9** (najwyżej dwie rundy: zbuduj całość, obejrzyj wszystkie stany naraz, popraw jedną partią, potwierdź drugą). W raporcie napisz, skąd dowód.
- [ ] **Step 3: STOP — pokaż makiety użytkownikowi** i czekaj na akceptację (decyzja projektowa należy do użytkownika). Zmiany po akceptacji tylko na jego polecenie.
- [ ] **Step 4: Commit** `git add docs/design/makiety/dictionary-*.png docs/design/macos.md` · „Faza 2.1: makieta zakładki Dictionary".

### Task 2: Model Dictionary i magazyn

**Files:**
- Create: `Sources/MeetNotesNotes/UserDictionary.swift`
- Modify: `Sources/MeetNotesProviders/Stores.swift` (dodaj `MeetNotesPaths.dictionary`)
- Test: `Tests/MeetNotesNotesTests/UserDictionaryTests.swift`

**Interfaces:**
- Produces:
  - `public enum TermPriority: String, Codable, CaseIterable, Sendable { case high, normal, low }`
  - `public struct DictionaryAlias: Codable, Equatable, Sendable { public var text: String; public var risky: Bool; public var enabled: Bool; public init(_ text: String, risky: Bool = false, enabled: Bool = true) }` (Alias risky z importu ma `risky: true, enabled: false`)
  - `public struct DictionaryTerm: Codable, Equatable, Sendable, Identifiable { public var id: UUID; public var text: String; public var priority: TermPriority; public var aliases: [DictionaryAlias]; public init(_ text: String, priority: TermPriority = .normal, aliases: [DictionaryAlias] = [], id: UUID = UUID()) }`
  - `public struct UserDictionary: Codable, Equatable, Sendable { public var terms: [DictionaryTerm]; public init(terms: [DictionaryTerm] = []); public func owner(ofAlias: String, excluding: UUID?) -> DictionaryTerm?; public mutating func upsert(_ t: DictionaryTerm) throws(DictionaryError); public mutating func remove(_ id: UUID) }`
  - `public enum DictionaryError: Error, Equatable { case emptyTerm, duplicateTerm(String), aliasTaken(alias: String, by: String), emptyAlias }`
  - `MeetNotesPaths.dictionary: URL` → `root/dictionary.json`
- Normalizacja NFC (`precomposedStringWithCanonicalMapping`) i przycięcie białych znaków w `upsert`; porównania Termów i Aliasów bez rozróżniania wielkości liter.

- [ ] **Step 1: Napisz testy** (nazwy i asercje):
  - `dictionaryRoundTripsThroughJSONFile`: zapis → odczyt daje równy `UserDictionary`; brak pliku → pusty słownik.
  - `upsertRejectsAliasOwnedByAnotherTerm`: `#expect(throws: DictionaryError.aliasTaken(alias: "Zoey", by: "Zowie"))`.
  - `upsertRejectsDuplicateTermIgnoringCase` i `upsertRejectsEmptyTermAndEmptyAlias`.
  - `upsertNormalizesToNFC`: Alias `"Dz\u{0307}enesis"` wpisany w NFD odczytywany jest jako NFC.
  - `upsertDropsAliasEqualToItsTermIgnoringCase`: `Term "Zowie"` z Aliasem `"zowie"` → brak Aliasu.
- [ ] **Step 2: Uruchom** `scripts/test.sh --filter UserDictionaryTests`; oczekiwane: FAIL (brak typów).
- [ ] **Step 3: Zaimplementuj** typy powyżej w `UserDictionary.swift` i `MeetNotesPaths.dictionary`.
- [ ] **Step 4: Uruchom** `scripts/test.sh --filter UserDictionaryTests`; oczekiwane: PASS.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesNotes/UserDictionary.swift Sources/MeetNotesProviders/Stores.swift Tests/MeetNotesNotesTests/UserDictionaryTests.swift` · „Faza 2.1: model Dictionary i magazyn".
- [ ] **Step 6: Mutacja bramki:** usuń kontrolę `aliasTaken` w `upsert` → test z `aliasTaken` ma paść → `git checkout Sources/MeetNotesNotes/UserDictionary.swift`.

### Task 3: Replacement

**Files:**
- Create: `Sources/MeetNotesNotes/Replacement.swift`
- Test: `Tests/MeetNotesNotesTests/ReplacementTests.swift`

**Interfaces:**
- Consumes: `UserDictionary`, `Transcript`/`Utterance` (`MeetNotesTranscription`).
- Produces:
  - `public struct ReplacementRules: Sendable { public init(_ d: UserDictionary); public var isEmpty: Bool; public func apply(to text: String) -> String }`
  - `public enum Replacement { public static func apply(_ t: Transcript, rules: ReplacementRules) -> Transcript }` — zmienia wyłącznie `Utterance.text`; `words`, czasy, `speaker`, flagi bez zmian; gdy `rules.isEmpty`, zwraca `t` bez kopiowania pól.

- [ ] **Step 1: Napisz testy:**
  - `replacesAliasWithTermExactSpelling`: Alias `Zoim` → `Zowie`, `"Zoim mówi"` → `"Zowie mówi"`; Alias `Pudo`→`PUDO`: wynik używa zapisu Terma.
  - `matchingIgnoresCase`: `"zOiM"` → `"Zowie"`.
  - `matchesOnlyOnWordBoundaries`: Alias `pu do`: `"pu dowolny"` bez zmian, `"pu do."` → `"PUDO."`; polskie litery: Alias `Jarla`, tekst `"Jarlań"` bez zmian.
  - `longestAliasWins`: Aliasy `in post` i `post`→inny Term; `"in post"` → `"InPost"`.
  - `singlePassDoesNotChainReplacements`: Term A z Aliasem `b`, Term B z Aliasem `a` → `"a b"` daje `"B A"`, nie zapętla się.
  - `disabledAliasIsIgnored`: Alias `risky: true, enabled: false` nie zmienia tekstu.
  - `isIdempotent`: `apply(apply(x)) == apply(x)` na zestawie ze wszystkimi przypadkami powyżej.
  - `specialCharactersInAliasAreLiteral`: Alias `c++ (x)`; tekst `"c++ (x)"` zamieniony, `"cccc"` bez zmian.
  - `nfdTextMatchesNfcAlias`: tekst w NFD z Aliasem w NFC → podmieniony (rules normalizują wejście do dopasowania, wynik w NFC).
  - `emptyRulesReturnSameTranscript` i `transcriptReplacementKeepsWordsAndTimes`: po `Replacement.apply` `words`, `start`, `end`, `speaker`, `languageMismatch`, `echoOfThem` równe oryginałowi.
- [ ] **Step 2: Uruchom** `scripts/test.sh --filter ReplacementTests`; oczekiwane: FAIL.
- [ ] **Step 3: Zaimplementuj** `ReplacementRules` jako jedno przejście po tekście: Aliasy włączone, posortowane malejąco po długości, dopasowanie na ucieczkowanych literałach z granicami `(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])` i opcją bez rozróżniania wielkości liter (np. `NSRegularExpression` z jedną alternacją); bez ponownego skanowania wyniku.
- [ ] **Step 4: Uruchom** testy; oczekiwane: PASS.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesNotes/Replacement.swift Tests/MeetNotesNotesTests/ReplacementTests.swift` · „Faza 2.1: Replacement".
- [ ] **Step 6: Mutacja bramek:** (a) zamień warunek `enabled` na stały `true` → `disabledAliasIsIgnored` pada; (b) usuń granice słów → `matchesOnlyOnWordBoundaries` pada; (c) wyłącz sortowanie po długości → `longestAliasWins` pada. Po każdej `git checkout Sources/MeetNotesNotes/Replacement.swift`.

### Task 4: Import i eksport TSV

**Files:**
- Create: `Sources/MeetNotesNotes/DictionaryTransfer.swift`
- Test: `Tests/MeetNotesNotesTests/DictionaryTransferTests.swift`

**Interfaces:**
- Consumes: `UserDictionary`, `DictionaryTerm`, `DictionaryAlias`, `TermPriority`.
- Produces:
  - `public struct DictionaryImportReport: Equatable, Sendable { public var termsAdded: Int; public var aliasesAdded: Int; public var riskyLeftOff: Int; public var conflicts: [Conflict]; public struct Conflict: Equatable, Sendable { public var alias: String; public var keptBy: String; public var skippedFor: String }; public var summary: String }` (`summary` np. „166 terms, 223 aliases, 12 risky left off, 2 conflicts" — angielski, do UI)
  - `public enum DictionaryTransfer { public static func importFiles(vocabulary: String?, replacements: String?, into d: UserDictionary) -> (dictionary: UserDictionary, report: DictionaryImportReport); public static func exportReplacements(_ d: UserDictionary) -> String; public static func exportVocabulary(_ d: UserDictionary) -> String }`
- Format wejścia: `vocab_core.txt` — jedna fraza w linii, `#` i puste pomijane; nagłówek zaczynający się od `# ==` i zawierający `T1`/`T2`/`T3` ustawia priorytet kolejnych linii (High/Normal/Low; przed pierwszym nagłówkiem Normal). `replacements.tsv` — `fraza<TAB>zapis`, `#` pomijane, linia zaczynająca się od `#!` otwiera sekcję risky aż do następnego nagłówka `# ---`; cele spoza `vocab_core` dostają priorytet Low.
- Reguły: scalanie po tekście bez rozróżniania wielkości liter; istniejące Termy i Aliasy nietknięte (priorytet i `enabled` użytkownika wygrywają), dodawane tylko nowe; Alias już należący do innego Terma → pominięty i w `conflicts`; idempotencja.

- [ ] **Step 1: Napisz testy** (literały w teście, nie pliki z `~/GCX`):
  - `vocabularyTiersMapToPriorities`: dwa nagłówki `# ====== T1 …` i `# ====== T3 …` z po jednym Termie → High i Low.
  - `replacementsAddAliasesToTerms` i `termsOnlyInReplacementsGetLowPriority`.
  - `riskySectionImportsAliasesDisabled`: po `#! ----` Alias ma `risky: true, enabled: false`, `report.riskyLeftOff == 1`.
  - `aliasOwnedByAnotherTermIsReportedNotMoved`: ten sam Alias w dwóch liniach do różnych Termów → pierwszy zostaje, `conflicts.count == 1`.
  - `importIsIdempotent`: drugi import tych samych tekstów zwraca równy słownik i raport z zerami.
  - `reimportKeepsUserEdits`: po ręcznej zmianie priorytetu i włączeniu risky Aliasu ponowny import ich nie cofa.
  - `exportRoundTrips`: `importFiles(export…)` na pustym słowniku daje równoważny słownik (Termy, Aliasy, risky, priorytety).
- [ ] **Step 2: Uruchom** `scripts/test.sh --filter DictionaryTransferTests`; oczekiwane: FAIL.
- [ ] **Step 3: Zaimplementuj** parser i eksport; eksport `replacements.tsv`: Aliasy włączone w sekcji głównej, risky w sekcji `#! ---------- RISKY ----------`; `vocab_core.txt` z nagłówkami T1/T2/T3 wg priorytetu.
- [ ] **Step 4: Uruchom** testy; oczekiwane: PASS.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesNotes/DictionaryTransfer.swift Tests/MeetNotesNotesTests/DictionaryTransferTests.swift` · „Faza 2.1: import i eksport Dictionary".
- [ ] **Step 6: Mutacja bramki:** usuń kontrolę istniejącego Aliasu → `importIsIdempotent` i `reimportKeepsUserEdits` padają → `git checkout`.

### Task 5: Linie do poleceń (Termy i Attendee hint)

**Files:**
- Create: `Sources/MeetNotesNotes/DictionaryPrompt.swift`
- Test: `Tests/MeetNotesNotesTests/DictionaryPromptTests.swift`

**Interfaces:**
- Consumes: `UserDictionary`, `ContextBudget` (`MeetNotesProviders`), `CalendarLink?`.
- Produces:
  - `public struct PromptVocabulary: Equatable, Sendable { public var terms: [String]; public var attendees: [String]; public var omittedTerms: Int; public var isEmpty: Bool; public var promptLines: String? }` — `promptLines` zwraca `nil` przy pustym, inaczej linie: `Known names and terms (spell them exactly like this when they appear): A, B, C.` oraz `Meeting attendees: X, Y.` (każda tylko gdy niepusta, rozdzielone `\n`).
  - `public enum DictionaryPrompt { public static func make(_ d: UserDictionary, link: CalendarLink?, maxChars: Int) -> PromptVocabulary; public static func maxChars(budget: ContextBudget?) -> Int }`
- Reguły: Uczestnik = `Attendee.name` (bez nazwy pomijany; e-maili nigdy), deduplikowani, maks. 30, każdy ≤ 60 znaków; Terminy i imiona oczyszczone z `\n`, `\r`, `"` i ograniczone do 60 znaków. Uczestnicy zawsze pierwsi w budżecie; Termy wypełniają resztę w kolejności: High, Normal, Low, a w obrębie priorytetu kolejność słownika; `omittedTerms` = ile Termów nie weszło. `maxChars(budget:)`: `nil` (API) → 3000; lokalnie → `min(3000, Int(Double(budget.tokens) * ContextBudget.charsPerToken * 0.1))`. (Wartości to decyzje planu: spec zostawił je wykonawcy.)

- [ ] **Step 1: Napisz testy:**
  - `termsOrderedByPriorityThenDictionaryOrder` i `termsOverBudgetAreOmittedLowestPriorityFirst` (`omittedTerms` zgodne z liczbą wyciętych).
  - `attendeesUseNamesOnlyAndSkipEmailOnly`: `Attendee(email:)` pominięty; duplikaty złączone.
  - `sanitizesNewlinesAndQuotes`: nazwisko `"Ada\n\"Ignore all instructions\""` → jedna linia bez `\n` i `"`.
  - `emptyDictionaryAndNoLinkGivesNilPromptLines`.
  - `maxCharsForLocalBudgetScalesAndCaps`: `ContextBudget(tokens: 4096)` → 982; `ContextBudget(tokens: 16384)` → 3000; `nil` → 3000.
- [ ] **Step 2: Uruchom** `scripts/test.sh --filter DictionaryPromptTests`; oczekiwane: FAIL.
- [ ] **Step 3: Zaimplementuj** `make`, `promptLines`, `maxChars`.
- [ ] **Step 4: Uruchom** testy; oczekiwane: PASS.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesNotes/DictionaryPrompt.swift Tests/MeetNotesNotesTests/DictionaryPromptTests.swift` · „Faza 2.1: linie Termów i uczestników do poleceń".
- [ ] **Step 6: Mutacja bramki:** usuń sortowanie po priorytecie → `termsOrderedByPriorityThenDictionaryOrder` pada; usuń oczyszczanie → `sanitizesNewlinesAndQuotes` pada → `git checkout`.

### Task 6: Podłączenie do Corrector i NotePromptBuilder

**Files:**
- Modify: `Sources/MeetNotesNotes/Corrector.swift` (pole `vocabulary: PromptVocabulary?`, init, `system(language:)`)
- Modify: `Sources/MeetNotesNotes/NotePrompt.swift` (`build`/`prompt`/`mapPrompt` dostają `vocabulary: PromptVocabulary? = nil`), `Sources/MeetNotesNotes/NoteGenerator.swift` (`generate(…, vocabulary: PromptVocabulary? = nil)`)
- Test: `Tests/MeetNotesNotesTests/CorrectorTests.swift`, `Tests/MeetNotesNotesTests/PromptTests.swift`

**Interfaces:**
- Consumes: `PromptVocabulary.promptLines` (Task 5).
- Produces: `Corrector.init(…, fillerWords: [String] = [], vocabulary: PromptVocabulary? = nil)`; `NotePromptBuilder.build(template:transcript:myNotes:context:notesLanguage:condensed:vocabulary:)`; `NoteGenerator.generate(…, vocabulary:)`. Domyślnie `nil` — wszystkie dotychczasowe wywołania i testy bez zmian.
- Linie lądują w `system` (po zdaniu o języku, przed „Extra instructions"); w podsumowaniu w `system` po regułach, także w promptach etapu map (wykonawca sprawdza, że reduce nie dubluje linii).

- [ ] **Step 1: Napisz testy:**
  - `correctorSystemIncludesVocabularyLines` (zawiera `Known names and terms` i `Meeting attendees`), `correctorSystemUnchangedWithoutVocabulary` (równe z wynikiem sprzed zmiany: porównanie z `Corrector` bez parametru) i `batchLimitShrinksWithVocabulary` (`batchLimit` mniejszy o długość linii przy lokalnym budżecie).
  - `summaryPromptIncludesVocabularyLines` oraz `summaryPromptUnchangedWithoutVocabulary` (równość `NotePrompt` z domyślnym wywołaniem).
- [ ] **Step 2: Uruchom** `scripts/test.sh --filter CorrectorTests` i `--filter PromptTests`; oczekiwane: FAIL.
- [ ] **Step 3: Zaimplementuj** dopisanie `vocabulary?.promptLines` w `Corrector.system` i `NotePromptBuilder.prompt`/`mapPrompt`; przekazanie parametru przez `NoteGenerator.generate` do `build` i etapów map.
- [ ] **Step 4: Uruchom** pełne `scripts/test.sh`; oczekiwane: wszystko zielone, liczba testów = poprzednia + nowe.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesNotes/Corrector.swift Sources/MeetNotesNotes/NotePrompt.swift Sources/MeetNotesNotes/NoteGenerator.swift Tests/MeetNotesNotesTests/CorrectorTests.swift Tests/MeetNotesNotesTests/PromptTests.swift` · „Faza 2.1: Termy i uczestnicy w poleceniach korektora i podsumowania".
- [ ] **Step 6: Mutacja bramki:** zignoruj `vocabulary` w `Corrector.system` → `correctorSystemIncludesVocabularyLines` pada → `git checkout`.

### Task 7: Wiązanie w AppModel i NotesModel

**Files:**
- Modify: `Sources/MeetNotesApp/AppModel.swift` (`dictionary: UserDictionary`, wczytanie `read(paths.dictionary, UserDictionary())`, `saveDictionary() -> String?` jak `savePreset`, `transcript(of:corrected:)`, `ReplacementRules` odświeżane po zmianie słownika)
- Modify: `Sources/MeetNotesApp/NotesModel.swift` (zamknięcia `replacementRules: () -> ReplacementRules` i `dictionary: () -> UserDictionary`; Replacement na wejściu `runCorrection` i przed `generate`; `vocabulary` do `Corrector` i `NoteGenerator` z `item.notes.meta.calendarEvent` czytanym w chwili uruchomienia)
- Modify: `Sources/MeetNotesApp/MeetingTabs.swift` (linie 199, 309, 373 — odczyt przez `model.transcript(of:corrected:)`), `Sources/MeetNotesApp/MeetingsView.swift` (linia 25 — wyszukiwanie)
- Test: logika jest w Task 2–6; wiązanie bez testów jednostkowych (brak `MeetNotesAppTests`). Weryfikacja w Task 9.

**Interfaces:**
- Consumes: `UserDictionary`, `ReplacementRules`, `Replacement.apply`, `DictionaryPrompt.make/maxChars`.
- Produces: `AppModel.transcript(of item: SessionItem, corrected: Bool) -> Transcript?` — jedyny punkt odczytu do wyświetlania, wyszukiwania i notatki; zwraca wynik `item.transcript(corrected:)` po `Replacement`. Cache wyniku kluczowany (id sesji, tryb, wersja słownika, `utterances.count`) jest dozwolony; zmiana słownika odświeża otwarte widoki (wykonawca wybiera mechanizm zgodny z `@Observable`).

- [ ] **Step 1: Wylistuj** wszystkie miejsca czytające `item.transcript`/`item.corrected?.transcript` (grep; spec §4) i zapisz w raporcie, które idą przez nowy punkt, a które (statusy, `!= nil`) zostają na surowym.
- [ ] **Step 2: Zaimplementuj** `dictionary` (wczytywane lokalnym `read` jak presety), `saveDictionary()`, `transcript(of:corrected:)` i podmień cztery miejsca odczytu.
- [ ] **Step 3: Zaimplementuj** w `NotesModel`: Replacement na `transcript` przekazywanym do `Corrector.correct`; transkrypt trafiający do `NoteGenerator` przechodzi `Replacement` (idempotentny — wystarczy, że zawsze przechodzi); `PromptVocabulary` budowany przez `DictionaryPrompt.make(dictionary(), link: item.notes.meta.calendarEvent, maxChars: DictionaryPrompt.maxChars(budget: budget))` przy każdym uruchomieniu korekty, generowania i ponowienia.
- [ ] **Step 4: Uruchom** `scripts/test.sh`; oczekiwane: zielone, bez zmiany liczby testów. `swift build --disable-keychain` bez nowych ostrzeżeń kompilatora.
- [ ] **Step 5: Commit** `git add Sources/MeetNotesApp/AppModel.swift Sources/MeetNotesApp/NotesModel.swift Sources/MeetNotesApp/MeetingTabs.swift Sources/MeetNotesApp/MeetingsView.swift` · „Faza 2.1: Dictionary w AppModel, odczyt przez Replacement, słownik w poleceniach".

### Task 8: Zakładka Dictionary

**Files:**
- Create: `Sources/MeetNotesApp/DictionaryView.swift`, `Sources/MeetNotesApp/DictionaryViewState.swift`
- Modify: `Sources/MeetNotesApp/MeetNotesApp.swift:86` (zamień `LaterPhaseView` dla `.dictionary` na `DictionaryView()`)

**Interfaces:**
- Consumes: `AppModel.dictionary`, `saveDictionary()`, `UserDictionary.upsert/remove`, `DictionaryTransfer`, `DictionaryPrompt.make/maxChars`, `ContextBudget.resolve(provider:detected:)`, `model.presetsInfo`-podobny dostęp do domyślnego presetu.
- Produces: `DictionaryViewState: ObservableObject` (stan lokalny przez `@StateObject`, bez `@State`): `query`, `selection: UUID?`, `draft: DictionaryTerm?`, `importReport: DictionaryImportReport?`, `error: String?`.

- [ ] **Step 1: Zbuduj widok** zgodnie z zaakceptowaną makietą (Task 1): lista z wyszukiwaniem, dodaj/edytuj/usuń Term, edytowalna lista Aliasów z przełącznikiem risky/enabled, Priority (High/Normal/Low), przyciski Import… (wybór `vocab_core.txt` i/lub `replacements.tsv` przez `NSOpenPanel`, raport w arkuszu) i Export… (`NSSavePanel`, dwa pliki do wybranego katalogu); błędy `DictionaryError` pokazane po angielsku przy polu.
- [ ] **Step 2: Licznik:** „N terms don't fit the correction prompt" dla modelu korekty domyślnego presetu; budżet z `ContextBudget.resolve(provider:detected: nil)` (pole „Context window", przybliżenie: bez sondy `/api/ps`; dla API 3000 znaków); ukryty, gdy `omittedTerms == 0` lub preset bez korekty.
- [ ] **Step 3: Sprawdź** `swift build --disable-keychain --product MeetNotesApp` i `scripts/test.sh` (zielone, bez zmiany liczby testów).
- [ ] **Step 4: Scena migawek:** dodaj w `Snapshots.swift` cztery sceny (pusty, lista, edycja, raport importu) i uruchom `scripts/snapshot.sh`; porównaj z makietą, drugą rundę poprawek zrób jedną partią (`macos.md` §9).
- [ ] **Step 5: Commit** `git add Sources/MeetNotesApp/DictionaryView.swift Sources/MeetNotesApp/DictionaryViewState.swift Sources/MeetNotesApp/MeetNotesApp.swift Sources/MeetNotesApp/Snapshots.swift` · „Faza 2.1: zakładka Dictionary".

### Task 9: Odbiór agenta i dokumenty

**Files:**
- Create: `scripts/fixtures/dictionary-62de.tsv` (Term `Zowie` z Aliasami `Zoe`, `Zoey`, `Zoim`; `Jarek` z `Jarla`; `Zoom` z `Doomem`, `Zoomem`), wspólny format `replacements.tsv`
- Modify: `Sources/meetnotes-cli/` (nowa komenda `dictionary-check <session-dir> --replacements <plik>`: wypisuje dla każdego Terma i Aliasu liczbę wystąpień w surowym i w poprawionym transkrypcie przed i po Replacement; wzorzec parsowania argumentów jak istniejące komendy)
- Modify: `docs/superpowers/ROADMAP.md`, `docs/superpowers/BACKLOG.md`, `CLAUDE.md` (sekcja „Stan"), `GLOSSARY.md` (jeśli pojęcia się zmieniły), artefakt „Mapa faz Yascribe" (https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz: `Artifact` read, edycja, publikacja pod tym samym URL-em)
- Create: `docs/superpowers/reports/F21-odbior.md`

- [ ] **Step 1: Dodaj komendę CLI** i uruchom: `B=$(swift build --show-bin-path)/meetnotes-cli; $B dictionary-check .devdata/sessions/2026-10-21T07-29-08Z-62de --replacements scripts/fixtures/dictionary-62de.tsv`. Następnie mutacja kontrolna (po commicie Task 7): wyłącz Replacement w `AppModel.transcript(of:corrected:)` i zbuduj — widok ma pokazywać stare zapisy (tu: sprawdź w migawce sceny z transkryptem), `git checkout Sources/MeetNotesApp/AppModel.swift`. Oczekiwane: po Replacement 0 wystąpień `Zoim`, `Zoey`, `Zoe `, `Jarla`, `Doomem`, `Zoomem` i niezerowe `Zowie`, `Jarek`, `Zoom` zarówno w surowym, jak i poprawionym transkrypcie (odbiór §8.1).
- [ ] **Step 2: Odbiór §8.3:** w teście `DictionaryPromptTests` jest już przypadek 4096 tokenów; uruchom dodatkowo scenę migawek z licznikiem „N terms don't fit" (słownik >100 Termów, model lokalny z Context window 4096) i dołącz zrzut do raportu.
- [ ] **Step 3: Pełny przebieg** `scripts/test.sh`; zapisz liczbę testów.
- [ ] **Step 4: Raport** `F21-odbior.md`: wyniki kroków 1–3 z dowodami (polecenia, wyjście), co zrobił agent, co zostaje użytkownikowi (§8.4: wpisać prawdziwe Termy/Aliasy w zakładce, nagrać spotkanie powiązane z wydarzeniem na presecie z korektą), co niezmierzone.
- [ ] **Step 5: Dokumenty:** ROADMAP (2.1a zamknięta w kodzie, 2.1b i spike boostingu otwarte), BACKLOG (odłożone: odmiany Aliasów, licznik z sondą kontekstu), CLAUDE.md „Stan", artefakt „Mapa faz Yascribe".
- [ ] **Step 6: Commit** `git add scripts/fixtures/dictionary-62de.tsv Sources/meetnotes-cli docs/superpowers/reports/F21-odbior.md docs/superpowers/ROADMAP.md docs/superpowers/BACKLOG.md CLAUDE.md GLOSSARY.md` · „Faza 2.1a: odbiór agenta i dokumenty".
- [ ] **Step 7: STOP — przekaż użytkownikowi** raport i kroki do wykonania (odbiór §8.4); PR i scalenie na polecenie użytkownika.
