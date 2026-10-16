# F15-T13 część B — wdrożenie języka wizualnego B (2026-10-15)

Gałąź `faza15-design-b` (z `faza15` @ `9952595`; `faza15` bez nowych commitów w chwili raportu, gałąź NIE scalona — scalenie to decyzja użytkownika, w uzgodnieniu z sesją poprawek T13). Orkiestrator: Opus. Widoki: 5 agentów Sonnet, każdy we
własnym worktree, scalone tutaj. Pomiar kontrastu: Haiku. Źródło prawdy: `docs/design/macos.md` §11 i
makiety `docs/design/makiety/b-*.png`.

**Wynik:** `scripts/test.sh` → `200/200` (199 z części A + 1 nowy), `check-bundle: OK`.

## Commity

| Commit | Co |
|---|---|
| `1f131d6` | Docs: spec §5.4, uwaga 7, plan T4 — dodawanie dostawcy w miejscu zamiast arkusza i kafelków |
| `bf2ac49` | `DesignSystem.swift`: tokeny §11.1 (`NSColor(name:dynamicProvider:)`, wariant Increase Contrast dla `text2`/`line`), `PageTitle`, `.documentTitle()`, `SectionHeader`, `Card`, `RowDivider`, `FormRow`, `PillButtonStyle` (primary/secondary/small; hover, wciśnięty, nieaktywny, fokus), `StateLabel`, `MetaLine`; `ModelPicker` wygląda jak `ModelField`; `.tint(.mnAccent)`; galeria komponentów w migawkach |
| `26d78f3` | Strona główna (Sonnet) |
| `63ad9a3` | Pigułka nagrywania, Liquid Glass za `#available(macOS 26)` z materiałem jako fallback (Sonnet) |
| `3453cf3` | Widok spotkania (Sonnet) |
| `41ee8eb` | Settings: dodawanie w miejscu, `ProviderPreset.isAdded(in:)` + test, `AppModel.replaceKey` (Sonnet) |
| `01be8ba` | Presets i Templates (Sonnet) |
| `0d0f555` | Po scaleniu: `WarnLabel` jako komponent wspólny (był zdublowany w dwóch gałęziach), embedding w Settings bez podwójnej karty |

## Weryfikacja

- **Migawki T0 (macos.md §9):** „przed” w `.design/przed/` (34 PNG, stan `9952595`), „po” w `.design/review/`
  (42 PNG, w tym `components-*`, `settings-add-*`). Obejrzane przez orkiestratora: `meetings-full`, `meeting-summary`,
  `presets-editing`, `settings-add-failed`, `components` (oba motywy dla galerii). Agenci obejrzeli resztę swoich ekranów.
  Zgodne z makietami co do palety, typografii, kart, pigułek i stanów. **Dowód: migawka offscreen, nie zrzut na żywo.**
- **Czego migawka nie pokaże:** sidebara macOS 27 (`NavigationSplitView` renderuje się offscreen jako pusta plansza, T3),
  szkła pigułki, pigułki w stanie nagrywania (stanu nie da się wymusić), koloru `Toggle`/akcentu (okno migawki jest
  nieaktywne, kontrolki są szare), fokusu z klawiatury. Wszystko to → odbiór na żywo.
- **Kontrast (WCAG, policzony skryptem, nie na oko):** wszystkie pary tekstu ≥ 4,5:1 w obu motywach, także
  `text2`/`sunk` (4,62 / 4,66), formularz dodawania w ciemnym (`text2` 4,76, `rec` 4,97) i warianty Increase Contrast
  (`text2` 7,5–9,5). Kropka nagrywania ≥ 3:1 (najmniej 3,28 na jasnym tle). **Jedna para poniżej progu:**
  `text2` na `selection` w jasnym = **4,26:1** (metadane zaznaczonego presetu oraz wiersza listy spotkań pod kursorem, bo podświetlenie najechania używa tego samego `selection`). → decyzja użytkownika (D1).
  `text3` (2,3–3,1) tylko dla nieaktywnych, zgodnie z §11.1.
- **Increase Contrast:** warianty `text2`/`line` są w kodzie, ale offscreen nie da się ich zobaczyć:
  `NSAppearance(named: .accessibilityHighContrastAqua)` zwraca zwykłe Aqua (sprawdzone małym programem). Wariant HC
  włącza tylko ustawienie systemowe, którego nie zmieniamy → **otwarte, do odbioru na żywo** (użytkownik włącza
  Increase Contrast).
- **Interlinia notatki (§11.2 ⚠️):** w `meeting-summary-*` odstęp między liniami akapitu ≈ 22 pt — `lineSpacing(5)` na SF 14 wystarcza.
- **Test + mutacja:** `presetCountsAsAddedByAddressNotName`. Mutacja „bez `lowercased()` hosta” → test pada
  (`ProviderSetupTests.swift:16`), przywrócone `git checkout`. Mutacja `guard self != .custom` → `guard true` jest
  **równoważna** (Custom ma pusty adres, `URL(string: "")` = nil), więc test jej nie łapie; guard zostaje jako jawny zamiar.
- **Klawiatura:** fokus pigułek to własny pierścień w `keyboardFocusIndicatorColor` (galeria: niewidoczny bez fokusu).
  Tab przez przyciski na macOS wymaga włączonego „Keyboard navigation” w Ustawieniach systemowych. Tego nie ruszamy,
  więc **niezweryfikowane**. Do odbioru: Tab przez pigułki, zakładki spotkania, wiersze listy, „⋯”, czy nie ma
  podwójnego pierścienia (systemowy + własny).

- **Świeży przegląd (agent Sonnet, read-only, wszystkie 42 migawki po vs `b-*.png`):** 13 uwag. Poprawione jedną partią:
  model w pasku generowania nie jest już ucinany (`layoutPriority`), placeholder My notes i tekst pola instrukcji w tokenach
  (`text2`/`text`), migawka `preset-form` na tle `background`. Reszta → odstępstwa i decyzje niżej (m.in. D8) albo drobne:
  pole nazwy presetu w semibold (makieta: regular), pusty stan „Choose a preset” z dużą ikoną (§11.6), „silent” pogrubione
  w pigułce, fixture migawek („No key” przy „Verified”), środkowe ucinanie długich id w `ModelField` w Presets.

## Odstępstwa od makiet (świadome)

1. Górny margines treści 24 pt zamiast 54: okno ma pasek tytułu, makieta go nie ma.
2. Wyszukiwarka to `TextField` w kapsule obok tytułu, a nie `.searchable` (ten trafia do paska okna). Brak ⌘F.
3. Widok spotkania bez kapsuły „wstecz” i „⋯”: obecny widok nie ma nawigacji wstecz ani menu akcji, a nowych akcji nie dodawaliśmy.
4. Notatka: punktory bez wcięcia 18 pt i akapity oddzielone pustą linią, bo `MarkdownBlocks.flatten` daje jeden zaznaczalny tekst (uwaga T13 #4). Nie ma też `text2` dla „— uzasadnień”.
5. Settings: po udanym „Save & verify” formularz zostaje otwarty z „✓ Verified · N models available” i przyciskiem Done.
   Po błędzie ponowne „Save & verify” podmienia klucz (`replaceKey`) zamiast dodawać drugiego dostawcę. Cancel tylko zwija formularz.
6. Settings: „Save & verify” to pigułka primary 28 pt (makieta ma 24 pt) i stoi obok Save w pasku. Na ekranie są więc dwa przyciski primary, tak jak na zatwierdzonej makiecie `b-add.png`, wbrew regule §11.4.
7. Presets: wiersz „Provider” pokazuje się tylko przy więcej niż jednym dostawcy albo przy roli bez dostawcy. Linia sondy („Not tested” + Test) jest przy każdej roli, a makieta ma ją tylko przy ASR.
8. Pigułka: brak paska tytułu i przycisku zamknięcia (makieta). Kropka jest stała zamiast pulsującej. Linia presetu nie zawiera modelu, bo `RecordingController` go nie zna.
9. Sidebar: makiety mają Presets / Templates / Settings na dole bez nagłówka, a `ContentView` nadal ma sekcję „Setup” (`MeetNotesApp.swift`). Migawki sidebara nie renderują, więc tylko lektura kodu. Nie zmienione → D7.
10. Ollama: `note` zmienione na „correction and summary only, no transcription” (jak w makiecie), test zaktualizowany.

## Decyzje dla użytkownika

- **D1** `text2`/`selection` jasny 4,26:1. Do wyboru: słabsze `selection` (np. 6%) albo `text` zamiast `text2` w zaznaczonym wierszu.
- **D2** `StateLabel(.live)`: słowo „Recording” jest czerwone (§11.4), a na makiecie pigułki ciemne. Co wybieramy?
- **D3** Pigułka bez przycisku zamknięcia: zostawić?
- **D4** Dwa przyciski primary w Settings podczas dodawania (pkt 6): zostawić czy „Save & verify” jako small primary?
- **D5** Wstecz / „⋯” w widoku spotkania (pkt 3): dodać, a jeśli tak, to co w menu?
- **D6** Wcięcia punktorów w notatce (pkt 4): zmiana `flatten` albo `NSTextView`?
- **D7** Sidebar: przenieść Presets / Templates / Settings na dół bez nagłówka „Setup”, jak na makiecie?
- **D8** Popupy (preset na karcie Record i w pigułce, Language, Notes language, Provider) są systemowe, zgodnie z zasadą
  §11 „Picker/Menu zostają systemowe”. Makiety rysują je jak pole `mnField` z małym ⌄ (tak wygląda już `ModelField`
  i menu szablonu), a w ciemnym motywie systemowy popup to jasnoszary blok obok wystylowanego pola. Wystylować je
  wspólnym stylem pola (wzór: `templateMenu` w `MeetingTabs.swift`) czy zostawić systemowe?

## Znane braki (do odbioru na żywo / dalej)

- **Pigułka ma okno o stałym rozmiarze (336×60, rozwinięta 224).** Agent ostrzega, że przezroczysty margines (do ~100 pt)
  może przechwytywać kliknięcia nad aplikacją spotkania. **Niezweryfikowane:** okno jest nieprzezroczyste=false z czystym tłem,
  więc WindowServer może przepuszczać kliknięcia przez w pełni przezroczyste piksele. Do sprawdzenia na żywo; jeśli łapie —
  okno dopasowane do treści (komentarz `ponytail:` w `RecordingController.swift`).
- Format czasu „1 h 05 min” i stany Recording / Correcting / Transcribing % / Correction failed na liście są sprawdzone tylko lekturą kodu i galerią, bo seed migawek ich nie ma.
- Data w `MetaLine` jest w locale systemu („15 paź 2026”), nie „Oct 15” jak w interfejsie po angielsku.

## Wykonanie decyzji D1–D8 (2026-10-15, wieczór)

Decyzje użytkownika zapisane w `docs/design/macos.md` §11 (commit `6dbca58` na `faza15`, scalony tutaj).
Opus: D1/D4/D7/D8 i scalanie; D5 i D2+D3 — Sonnet; D6 — Opus; każdy agent we własnym worktree.

| D | Wykonanie | Commit |
|---|---|---|
| D1 | `text2` jasny `#666259` (kontrast z §11.1: na zaznaczeniu 4,88, tło 5,62, karta 6,08, sunk 5,28) | `6efcbb3` |
| D2 | Pigułka rozwinięta: czerwona kropka + „Recording” w `text` Semibold; lista spotkań dalej `StateLabel(.live)` na czerwono | `bb997b4` |
| D3 | Bez przycisku zamknięcia; menu Window → „Hide Recording Window” (aktywne tylko przed startem, przy widocznej pigułce); okno pigułki dopasowane do treści (`fittingSize`, górna krawędź stoi), bez stałego 336×60 i marginesu | `bb997b4` |
| D4 | `.pillSmallPrimary` (24 pt) dla „Save & verify” i Done; Cancel jako `.pillSmall` | `6efcbb3` |
| D5 | Kapsuła wstecz (‹ Meetings) i „⋯” (Copy notes, Show in Finder, Delete meeting…); menu aplikacji „Meeting”: Back to Meetings ⌘[, Copy Notes ⌘⇧C, Show in Finder, Delete Meeting…. Usuwanie z potwierdzeniem („Move to Trash”), do Kosza (`trashItem`), nieaktywne dla sesji nagrywanej lub transkrybowanej. Delete bez skrótu ⌘⌫ — kolidowałby z edycją w My notes | `148e6eb`, `263a387` |
| D6 | Notatka = jeden `NSTextView` tylko do odczytu; `MarkdownBlocks.attributed(_:style:)` w `MeetNotesNotes` (interlinia 22, akapit 16, punkt 18 / zagnieżdżony 36, odstęp punktów 3, nagłówek 15 semibold 20/6, „— uzasadnienie” w `text2`); `flatten` usunięte (jedyny użytkownik). Pomiar migawki: interlinia 22, punkt→punkt 25, wcięcie 18/36, odstępy wokół nagłówków ±1 pt od makiety | `f682735` |
| D7 | Sidebar: Meetings na górze, Presets / Templates / Settings na dole bez nagłówka (druga lista w `safeAreaInset` z tym samym wyborem); nowa migawka `sidebar-*` | `6efcbb3` |
| D8 | `FieldMenu` (DesignSystem): pole `field`, obwódka, promień 7, ⌄; pod spodem standardowe `Menu`, wybór przez `Picker(.inline)`. Użyte dla presetu (karta Record i pigułka), Language, Notes language, Provider, szablonu | `6efcbb3` |

**Testy:** `scripts/test.sh` → `200/200` (test `flatten` zastąpiony testem `noteIsOneAttributedTextWithParagraphStyles`).
Mutacja D6: wcięcie punktu `headIndent = 0` → test pada (`MarkdownTests.swift:55–56`), przywrócone `git checkout`.
D5 bez nowej logiki w bibliotece (jednolinijkowe `canDelete` w `AppModel`), więc bez testu.

**Do odbioru na żywo (migawka tego nie pokaże):** pasek z wstecz i „⋯” (okno migawki nie ma paska narzędzi), menu
Meeting i Window, dialog usuwania, zaznaczanie notatki przeciąganiem przez akapity i Cmd-A/Cmd-C (uwaga T13 #4),
przewijanie kółkiem nad notatką, pigułka zwinięta↔rozwinięta i klik obok kapsuły, sidebar w prawdziwym oknie.

## Odbiór na żywo 2026-10-16: uwagi 1–8

Decyzje zapisane w `docs/design/macos.md` §11.5 (commity na `faza15`, scalone tutaj). Opus: uwaga 1, spinanie,
mutacje; agenci: Templates, Settings, pigułka (Sonnet), widok spotkania, ElevenLabs, Recordings (Opus).

| # | Wykonanie | Commit |
|---|---|---|
| 1 | Pasek narzędzi bez tła i tytułu (`toolbar(removing: .title)`, `toolbarBackground(.hidden)`); `navigationTitle` zostaje dla menu Window/VoiceOver | `59b0f5a` |
| 2 | Szablon = lista sekcji (`sections?`, `about?` opcjonalne; stary prompt → jedna sekcja), prompt z sekcji po kolei; wbudowane edytowalne (override, „Built-in · edited”, Reset to default), własne: Duplicate / Delete… z potwierdzeniem; pola rosną z treścią (`TextField(axis: .vertical)`) | `a0714de` |
| 3 | Pigułka: przezroczyste okno, cień po `invalidateShadow`, stały rozmiar (licznik o stałej szerokości, resize tylko przy zwinięta↔rozwinięta, kotwica lewy dolny róg), przesuwanie za tło (`WindowDragGesture` + `makeKey` w `mouseDown`), pozycja w UserDefaults, domyślnie środek dołu ekranu | `205a2ee` |
| 4 | Pigułka tylko podczas nagrywania; stan „przed startem” i „Hide Recording Window” usunięte; „Show Recording Window” (⌘⌥R) aktywne tylko w trakcie — ratunek, gdy pigułka zniknie z ekranu | `205a2ee` |
| 5 | Settings: lista OpenRouter / ElevenLabs / Ollama / Custom endpoint z oficjalnymi logo (SVG w kodzie, bez resource bundle), stan po prawej, „⋯” (Edit key…, Test again, Refresh Models, Remove…), konfiguracja w arkuszu z „Test connection” kluczem z pola (bez zapisu do pęku) i „Get an API key”. **ElevenLabs bezpośrednio:** `xi-api-key`, multipart, `scribe_v2`, `language_code` przy języku jawnym, granica `TranscriptionClient`, wybór klienta po `Provider.kind` (opcjonalne, E6) | `4c7b44b`, `714783a`, `6c639c1`, `e5803bf`, `ab43f8d` |
| 6 | Archive search: „Provider” (tylko skonfigurowani OpenAI-compatible; ukryty przy jednym) + „Embedding model”; zmiana dostawcy czyści model | `4c7b44b` |
| 7 | Widok spotkania = jedna przewijana strona (bez wewnętrznych ScrollView/List/TextEditor; `GrowingTextView` dla My notes i kontekstu, `LazyVStack` transkryptu); Summary bez karty, ten sam pasek przed/po; notatka na szerokość kolumny (kontener tekstu wraca do szerokości ramki po pomiarze); Transcript w jednej linii; „▶II” = odtwarzanie nagrania → przeniesione do menu Meeting („Play/Pause Recording”, bez skrótu Spacja). „Generate notes” na ⌘↩ zamiast Return (Return w polu kontekstu nie uruchamia płatnego generowania) | `402c899`, `7ca7d78` |
| 8 | Recordings: lokalizacja (kopia → weryfikacja listy i rozmiarów → przełączenie → usunięcie starych; błąd = nic nie kasujemy) i „Keep audio” 7/14/30/90/Forever (domyślnie 30; kasuje tylko `*.caf`, tylko po ukończonej transkrypcji; znacznik `audio-deleted.json`); widok spotkania: „Audio deleted after N days”, bez odtwarzania i ponownej transkrypcji | `fe273a1`, `c94ffc2`, `997e6b4` |

**Testy:** `scripts/test.sh` → `224/224`. Mutacje (każda wprowadzona po `git add`, test padł, `git checkout`):
Templates 5/5 (override w `all()`, reset, blokada usuwania wbudowanego, migracja, kolejność sekcji), Settings 4/4
(kolejność wierszy, filtr dostawców embeddingu, zachowanie wyboru, dopasowanie ElevenLabs), ElevenLabs 8/8 (agent),
Recordings: agent a–d, orkiestrator powtórzył niezależnie 3/3 (retencja bez warunku transkryptu, kasowanie nie tylko
`*.caf`, wyłączona weryfikacja przenoszenia).

**Przegląd migawek (Sonnet, read-only, 50 PNG):** nic zepsutego. Poprawione: pusty edytor Presets/Templates jako
tekst na tokenach zamiast `ContentUnavailableView`, nazwa presetu/szablonu zwykłym 15 pt (`f93f742`). Zostaje:
brak „N GB on disk” w migawce (rozmiar liczony asynchronicznie), brak migawki z „Improve transcript”, model nie
mieści się w linii presetu w rozwiniętej pigułce.

**⚠️ Dane:** pierwsze uruchomienie tej wersji (`scripts/run.sh` w tym worktree) **trwale skasuje `*.caf`** każdego
spotkania z ukończoną transkrypcją starszego niż 30 dni w aktywnym katalogu danych — tu kopii `.devdata`.
Transkrypty, notatki i My notes zostają.

### Decyzje dla użytkownika (z tej rundy)

- **R1** Skrócenie „Keep audio” kasuje od razu, bez potwierdzenia (np. 30 → 7 dni usuwa audio spotkań w wieku 7–30 dni). Dodać potwierdzenie?
- **R2** Po nieudanym przenoszeniu częściowa kopia zostaje w nowym folderze, więc ponowna próba do tego samego folderu jest odrzucana jako niepusty. Sprzątać własną częściową kopię?
- **R3** W trakcie przenoszenia nie są blokowane zapisy notatek (autozapis My notes, tytuł) z widoku spotkania — zapis po usunięciu starego miejsca odtworzyłby osierocony katalog. Użytkownik jest wtedy w Settings, więc ryzyko jest małe; zablokować całkiem?
- **R4** Podpis pod „Keep audio”: „Only audio is deleted. Transcripts, notes and My notes stay. Audio is kept until its transcription has finished.” (makieta ma inny tekst).
- **R5** Kotwica pigułki przy rozwijaniu: lewy dolny róg (teraz) czy środek dolnej krawędzi (rozwinięta przesuwa się wtedy o 82 pt)?
- **R6** „Show Recording Window” (⌘⌥R) zostawić jako ratunek czy usunąć?
- **R7** Prompt z sekcji: „Write these sections in this order, each titled section under a "## <title>" heading:” + lista „N. Tytuł: instrukcja”; zapis wbudowanego z treścią równą domyślnej nie zostawia „edited”; pusty szablon odrzucany przy Save.
- **R8** ElevenLabs: test klucza przez `GET /v1/models` — klucz ograniczony tylko do STT może dostać 403 („Not allowed…”) mimo działającej transkrypcji ⚠️.

### Gotowe do drugiego odbioru (na żywo, `scripts/run.sh` — najpierw zamknij działającą instancję)

1. Pasek okna: ciepłe tło do góry, bez tytułu i linii; w spotkaniu tylko wstecz i „⋯”.
2. Templates: edycja sekcji, przeciąganie ⋮⋮, Move up/down z menu kontekstowego, Return w polach, „Built-in · edited” + Reset, Delete template….
3–4. Pigułka: pojawia się przy Record z karty, znika po Stop; rogi i cień rozwiniętej na pierwszym planie; stały rozmiar przy tykającym liczniku; przeciąganie przy aktywnym Teams (bez odbierania fokusu); pozycja po restarcie.
5. Settings: logo w obu motywach, arkusz z „Test connection” (OpenRouter z kluczem; **ElevenLabs z Twoim kluczem** — verify, krótka polska sesja, preset Auto), Edit key…, Remove….
6. Archive search: Provider/Embedding model.
7. Widok spotkania: cała strona przewija się jednym paskiem przy krawędzi okna; My notes i kontekst rosną przy pisaniu (wklej długi tekst); notatka na 640 pt; zaznaczanie całej notatki; Transcript w jednej linii; Meeting → Play/Pause Recording; ⌘↩ w Summary.
8. Recordings: rozmiar na dysku w nagłówku, Change… do pustego folderu (postęp, przeniesione spotkania), Show in Finder, Keep audio, „Audio deleted after N days” na starym spotkaniu.

## Wykonanie decyzji R1–R8 (2026-10-16)

Użytkownik przyjął zalecenia R1–R8 („Accept the recommendations for R1–R8…”). Agenci: R1–R3 Opus, R5+R8 Sonnet.

| R | Wykonanie | Commit |
|---|---|---|
| R1 | Skrócenie „Keep audio”: `AudioRetention.plan` (ta sama reguła co kasowanie, bez kasowania) → dialog „Delete X of audio from N meetings older than D days?” / Delete Audio / Cancel (Cancel nie zmienia ustawienia); gdy nic by nie zniknęło lub Forever — bez pytania; `apply` idzie po `plan` (reguła w jednym miejscu) | `22677e0` |
| R2 | Po nieudanym przenoszeniu sprzątana jest tylko własna kopia (wpisy zapisane jako „nasze” przed kopiowaniem i tylko gdy ich nie było); folder docelowy usuwany tylko, jeśli go utworzyliśmy i jest pusty; ponowna próba do tego samego folderu działa | `22677e0` |
| R3 | Na czas przenoszenia widok spotkania tylko do odczytu („Moving recordings…” pod MetaLine); blokady w modelu (`canDelete`, `generate`, `retryCorrection`, `setManualTitle`, `saveMyNotes`); oczekujący autozapis My notes zapisywany przed startem przenoszenia | `22677e0` |
| R4 | Podpis pod „Keep audio” bez zmian | — |
| R5 | Pigułka: kotwica w środku dolnej krawędzi; `PillPlacement.frame` (czysta funkcja w `MeetNotesRecording`, clamp do `visibleFrame`); pozycja `recordingPillBottomCenter`, stara pozycja przeliczana | `5f6ffab` |
| R6 | „Show Recording Window” (⌘⌥R) zostaje jako ratunek | — |
| R7 | Bez zmian | — |
| R8 | ElevenLabs 403 z `/v1/models` → `ProviderCheck.limited("Key works for transcription only")`: trójkąt + słowa w `warn`, bez ✗ i Retry, w wierszu i w arkuszu; OpenAI-compatible 403 dalej błąd; migawki `settings-limited-*`, `settings-sheet-limited-*` | `5f6ffab`, `09e30bd` |

**Testy:** `scripts/test.sh` → `229/229`. Mutacje: agent R1 4/4, R2 3/3, R5+R8 3/3; orkiestrator powtórzył
niezależnie 3/3 (brak sprzątania, obce wpisy uznane za nasze, 403 ElevenLabs jako błąd). R3 bez testu — blokady
to `recordingsMove != nil` w celu aplikacji, który nie ma testów (sprawdzenie na żywo).

**Uwagi:** w trakcie przenoszenia My notes i rozwinięty kontekst są pokazane jako zaznaczalny tekst (NSTextView nie
reaguje na `.disabled`); Retry korekty na liście spotkań zostaje aktywny w UI, ale blokuje go strażnik w modelu
(komunikat „Meetings are being moved to a new folder. Try again when that finishes.”). Teksty dialogu R1 dobrał agent.

### Gotowe do drugiego odbioru — dodatki do listy wyżej

- R1: Keep audio 30 → 7 dni na kopii `.devdata` ze starymi spotkaniami → dialog z liczbą i rozmiarem; Cancel zostawia 30.
- R2: Change… na folder, który nie da się zapisać (np. bez uprawnień) → komunikat, stare miejsce aktywne, w celu nic po nas; ponowna próba działa.
- R3: w trakcie przenoszenia otwarte spotkanie tylko do odczytu z „Moving recordings…”.
- R5: zwinięta↔rozwinięta pigułka ze wspólnym środkiem dołu; przeciągnięcie przy krawędzi ekranu.
- R8: ElevenLabs z kluczem tylko STT → trójkąt „Key works for transcription only”.

## Drugi odbiór 2026-10-16: poprawki 1–6

Zapis w `docs/design/macos.md` §11.5 (`9cbe688`, `2bd91aa`, `dcefcdd` na `faza15`, scalone). Agenci Opus: pigułka (1–3), widok spotkania (4–6).

| # | Przyczyna → poprawka | Commit |
|---|---|---|
| 1 | „Sto / p”: idealna szerokość pigułki zaokrąglona w dół (okno 245 przy treści 253) → `lineLimit(1)` + `fixedSize` na Stop, liczniku, „Recording”, „Open note” i wierszu; migawka `pill-collapsed` w rozmiarze okna z najszerszym licznikiem 09:59:59 | `a401139` |
| 2 | **Przyczyna rogów (zmierzona):** warstwa Liquid Glass maluje poświatę 2–5 % alfa na całym prostokącie warstwy, także w rogach poza kształtem; okno = rozmiar treści, więc maska alfa okna była prostokątem i system liczył cień z prostokąta. Cień okna klucza ma ostrą krawędź (35–40 % alfa), stąd widoczne tylko na pierwszym planie. Właściwości okna (`.borderless` + `.nonactivatingPanel`, przezroczyste) były już poprawne; sam `invalidateShadow` nic nie zmieniał. → `.clipShape(shape)` po `glassEffect`: rogi 0 alfa, cień z zaokrąglonego kształtu w obu stanach (sonda `CGWindowListCreateImage` własnego okna) | `a401139` |
| 3 | „Open note” wołało tylko `openSession` (już ustawione) → `NSApp.activate()`, przywrócenie/wysunięcie okna głównego, `openWindow(id: "main")` gdy zamknięte; cel z `OpenNoteDestination.forRecording` (Meetings → sesja → My notes), test + mutacja | `a401139` |
| 4 | **Przyczyna:** widok spotkania otwiera się przy starcie nagrania; `onAppear` raz kopiował tytuł do `titleDraft` (wtedy pusty), a `@StateObject` z `.id(item.id)` przeżywa przeładowania — autotytuł nigdy nie trafiał do pola. → `titleEdit: String?` (`nil` = pole pokazuje `NoteTitle.fieldText`: ręczny > auto > z notatki, w kolorze `text`); zapis ręcznego tylko gdy `NoteTitle.isEdit` (realna zmiana); testy + mutacje | `1f36b90`, `3a2c432` |
| 5 | Stałe paski przewijania zwężały treść → `ScrollPage(width)` w DesignSystem: mierzy szerokość zewnętrzną i treści (`onGeometryChange`), przesuwa kolumnę o szerokość paska — kolumna wyśrodkowana względem okna; użyte w widoku spotkania, Presets, Settings, Templates. Dowód: migawki z `-AppleShowScrollBars Always` (argument procesu), krawędź 130/130 vs 130/123 po mutacji | `1f36b90` |
| 6 | `allZeros60s`: dziennik nie odróżnia ciszy na początku od braku uprawnień (liczba klatek rośnie w obu), więc sygnałem jest transkrypt — wypowiedź mówcy tego toru (system → Them, mikrofon → Me) = dźwięk przyszedł później = informacja („System audio was silent for the first minute; recording continued.”), bez ⚠ na liście; brak takich wypowiedzi albo transkryptu = ostrzeżenie. W widoku: chip „ⓘ/⚠ System audio” w linii metadanych z popoverem i linia nad transkryptem. Stare dzienniki nieprzepisywane. Sesja `af52`: 1 wypowiedź Them → informacja | `1f36b90` |

**Testy:** `scripts/test.sh` → `236/236`. Mutacje: agenci (tytuł 3, klasyfikacja 2, setter 1, Open note 2, ScrollPage i pigułka na migawkach/sondzie); orkiestrator powtórzył niezależnie 4/4 (autotytuł pominięty, cisza zawsze ostrzeżeniem, zły mówca, Open note bez sesji).

**Do decyzji:** (a) „Untitled meeting” zostaje szarym placeholderem przy pustym tytule (zmiana na kolor `text` to jedna linia); (b) do czasu transkrypcji cisza na początku pokazuje się jako ostrzeżenie — trwałe rozróżnienie wymaga zdarzenia w dzienniku przy pierwszych niezerowych próbkach po `allZeros` (zmiana w `SessionRecorder`, poza tą rundą); (c) gdy pigułka staje się oknem klucza, wokół Stop pojawia się niebieski pierścień fokusu; (d) `WindowGroup(id: "main")` może raz zresetować zapamiętany rozmiar i pozycję okna.

### Do trzeciego odbioru (na żywo)

1. Pigułka zwinięta: „Stop” w jednej linii, także po 1:00:00.
2. Rogi zwiniętej i rozwiniętej — po kliknięciu (pierwszy plan) i w tle, jasny i ciemny.
3. „Open note” z Teams/przeglądarką na pierwszym planie (ścieżka nieprzetestowana), z oknem zminimalizowanym, zamkniętym i po ⌘H.
4. Spotkanie w trakcie nagrania: autotytuł pojawia się w polu (czarny) i w wierszu listy; Enter bez zmiany nie zapisuje `manualTitle`; dopisanie słowa zapisuje ręczny.
5. „Show scroll bars: Always”: Transcript ↔ My notes — kolumna stoi.
6. Sesja `af52`: brak ⚠ na liście, chip „ⓘ System audio”, popover, linia nad transkryptem.
