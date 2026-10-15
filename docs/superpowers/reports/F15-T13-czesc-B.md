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
