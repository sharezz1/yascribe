# Presets i Templates: lista i okno jak w Dictionary (projekt)

Status: do zatwierdzenia. Poprzedni projekt (ta sama linia prac): `docs/superpowers/specs/2026-10-24-transcript-summary-minimalizm-design.md`.
Zakres: sekcje **Presets** i **Templates** w głównym oknie. Wzorzec: **Dictionary** (`DictionaryView.swift`, `DictionaryTermSheet`).

## Po co

Dictionary jest jedynym z trzech modułów wyglądającym tak, jak chce użytkownik: pełnoszeroka lista, klik w wiersz otwiera okno edycji.
Presets i Templates mają inny układ (lista 196 pt + formularz obok + przyklejony pasek Save/Cancel + blokada przełączania). Trzy moduły, trzy układy.

## Cele

- **Lista:** `ScrollPage(640)`, tytuł strony z przyciskiem „New preset" / „New template" po prawej (jak „New term"), pod nim `Card` z wierszami oddzielonymi `RowDivider`. Wiersz: nazwa (13 Medium) i druga linia 11 pt `mnText2` (te same metadane co dziś: presety — język · model ASR · „default"; szablony — „Built-in" / „Built-in · edited" / „Custom"); „Fully local" jako plakietka po prawej w wierszu presetu.
- **Edycja:** klik w wiersz otwiera okno (`.sheet`) o szerokości 560 pt, wysokości do ok. 80% okna, z przewijaną treścią i stałym paskiem na dole okna: po lewej akcje destrukcyjne (Delete template…, Reset to default, Duplicate — jak dziś w menu `⋯` szablonu), po prawej Cancel (Esc) i Save (⌘S / Return). Okno ma `.tint(.mnAccent)` i tło `mnCard` jak `DictionaryTermSheet`.
- **Stan pusty** listy: jak w Dictionary (karta z krótkim opisem i „New …"); dla presetów w praktyce nie wystąpi (zawsze jest przynajmniej jeden), dla szablonów też (wbudowane).
- **Odchudzenie formularza presetu (decyzja użytkownika):** w każdej roli rząd sondy (plakietki wyniku i „Test") oraz „Extra instructions" (korekta) trafiają do zwiniętej sekcji „Advanced". Dostawca, model, język, „Notes language", przełącznik korekty, notki „On this Mac" / lokalny serwer zostają widoczne.
- Znika blokada „Save or cancel your changes to switch…" (okno jest modalne) i wskaźnik „Unsaved changes" z przyklejonego paska; Save jest nieaktywny, dopóki nic się nie zmieniło (`isDirty`), Cancel zamyka bez zapisu.

## Poza zakresem

- Zmiany treści formularza szablonu (sekcje, przeciąganie, „About this meeting type") — przechodzi do okna bez zmian.
- Nowe funkcje presetów (usuwanie, ustawianie domyślnego) — dziś ich w UI nie ma.
- Settings, Dictionary, Transcript, Summary.
- Wyszukiwarka na liście (Dictionary ma, bo termów są setki; presetów i szablonów jest garstka).

## Antycele

- Utrata danych przy zamknięciu okna: Cancel i Esc przy niezapisanych zmianach nie mogą ich po cichu zapisać; zamknięcie z zmianami to Cancel (tak jak dziś Cancel wraca do `original`).
- Schowanie czegoś, bez czego preset nie zadziała: zwinięta sekcja „Advanced" nie może ukrywać problemu. Jeśli sonda ma negatywny wynik albo „Extra instructions" nie są puste, „Advanced" tej roli jest rozwinięta domyślnie. Błąd zapisu (`state.error`, np. „This model returns no word timings…") jest widoczny w oknie nad paskiem, nie w zwiniętej części.
- Nowe pola w zapisywanych typach inne niż opcjonalne.

## Podejścia

(A) Okno jak w Dictionary — wybrane po rozmowie. (B) Zostawić podział lista + formularz i tylko ujednolicić styl — nie spełnia „po kliknięciu pojawia się nowe okno". (C) Panel wysuwany z boku — nowy wzorzec, którego nie ma w aplikacji.

## Ustalenia

- Stan edytora zostaje w `PresetEditorState` i `TemplateEditorState` (`draft`, `original`, `isDirty`, `isNew`, `error`, `confirmingDelete`); dochodzi sterowanie oknem: okno jest otwarte, gdy `draft != nil` (jak `DictionaryViewState.draft`), `select`/`startNew` je otwierają, `cancel` zamyka i zeruje `draft`; zapis zamyka okno po sukcesie.
- Zapis przy błędzie (`error`) zostawia okno otwarte z komunikatem.
- Okno edycji używa istniejących elementów (`EditorNameField`, `EditorPromptField`, `RoleSection`, `SectionHeader`, `Card`, `FormRow`, `FieldMenu`); `EditorFooter` w obecnej postaci (przyklejony pasek strony) jest zastąpiony paskiem w oknie.
- Wiersz listy: osobny widok wzorowany na `DictionaryRow` (wspólny dla presetów i szablonów, `PresetRow` dziś służy obu — przerobić go na wiersz karty z `RowDivider`, zachowując nazwę i podpis).

## Zostawione wykonawcy

- Dokładne wymiary okna, przewijanie w oknie przy wysokim formularzu, komponent „Advanced" (zwykłe `DisclosureGroup` w stylu aplikacji albo własny wiersz-nagłówek z chevronem; wzorzec: czy aplikacja ma już zwijaną sekcję — jeśli tak, użyć jej).
- Migawki (`Snapshots.swift`): okno edycji presetu (Advanced zwinięte i rozwinięte), okno szablonu, lista presetów, lista szablonów.
- Testy jednostkowe nie obejmują widoków; logika „Advanced rozwinięta, gdy sonda negatywna lub prompt niepusty" ma być czystą funkcją z testem (np. `RoleAdvanced.startsExpanded(probe:prompt:) -> Bool`).

## Do potwierdzenia przy odbiorze

Wysokość i szerokość okna presetu; czy „Advanced" nie chowa tego, czego używasz często (sonda „Test"); wygląd listy w ciemnym motywie.
