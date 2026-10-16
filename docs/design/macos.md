# macOS: referencja platformy dla designu

> Status: **wymaganie wstępne**, 2026-09-24, uzgadniane w specach. Do czytania przed każdą
> pracą nad interfejsem meetnotes.
> Wzorowane na `reference/ios.md` z [impeccable](https://github.com/pbakaus/impeccable)
> (Apache-2.0), który nie obsługuje macOS: nasza aplikacja trafiłaby tam do kategorii `ios`
> i dostałaby reguły dotyku, paska zakładek i symulatora iPhone'a.
>
> Ten plik opisuje **platformę**. Reguły **produktu** (brak auto-języka, brak jednej liczby
> dokładności, wariant modelu widoczny przed startem) są w `docs/wymagania.md` §2 i §6 oraz
> w `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md` §9.
>
> ✏️ **Uzgodnienie z decyzjami z 2026-09-24** (spec fazy 1, §1.2–§1.4):
> - **Interfejs aplikacji jest po angielsku.** Przykłady tekstów interfejsu w tym pliku są
>   po angielsku; opisy i uzasadnienia zostają po polsku, jak reszta repo.
> - **Ustawienia są zakładką w oknie głównym**, a nie osobnym oknem. To świadome odstępstwo
>   od HIG, zapisane w §10 jako odstępstwo 3.
> - **Słownik (Dictionary) jest osobną zakładką**, a nie sekcją ustawień.
>
> ✏️ **Uzgodnienie z 2026-10-15 (język wizualny):** obszar treści dostaje własny system
> wizualny, opisany w §11 (kierunek B, „ciepły”, wzorowany na Granoli). Łamie on trzy reguły
> z §5 i §6.1, a odstępstwa 4–7 w §10 je uzasadniają. Ramka okna, sidebar, menu i kontrolki
> systemowe zostają bez zmian.

**Oznaczenia:** ✅ potwierdzone w Apple HIG (pobrane 2026-09-24, strona podana w nawiasie) ·
⚠️ z pamięci albo z dokumentacji API, niesprawdzone w tej sesji · 📐 wymaga pomiaru albo
spike'a · 🔀 świadome odstępstwo od HIG, z uzasadnieniem.

---

## 1. Test „przeniesione z innej platformy”

Czy użytkownik Maca zaufa tej aplikacji od pierwszego spojrzenia, czy zatrzyma się na
kontrolce, która zachowuje się „nie tak”? Są dwa typowe objawy:

- **Wygląda jak strona internetowa.** Własne przyciski w stylu webowym, własna ramka okna,
  akcje widoczne dopiero po najechaniu kursorem, brak menu. Tak wyglądają aplikacje
  na Electronie, które zmierzyliśmy (OpenWhispr).
- **Wygląda jak aplikacja z iPhone'a.** Pasek zakładek na dole, wielkie przyciski pod palec,
  wszystko w arkuszach modalnych, brak skrótów klawiszowych, brak menu kontekstowego.

Domyślnie bierz komponenty systemowe. Odchodź od nich tylko z powodem, za który
użytkownik by podziękował, i zapisz ten powód w §10.

---

## 2. Okna

- **Okno główne + okna pomocnicze.** Okno główne niesie nawigację i treść. Pomocnicze
  służy jednemu zadaniu, nie pozwala przejść gdzie indziej i zwykle ma przycisk zamknięcia (✅ windows).
- **Nie otwieraj nowych okien domyślnie.** Zaoferuj „Open in New Window” w menu
  kontekstowym albo w menu File (✅ windows).
- **Żadnej własnej ramki okna ani własnych przycisków okna.** Imitacja wyglądu systemu,
  która nie trafia idealnie, sprawia wrażenie zepsutej aplikacji (✅ windows).
- **Okna mają stany: główne, kluczowe, nieaktywne.** Komponenty systemowe przełączają
  wygląd same, a własne komponenty muszą robić to ręcznie (✅ windows). Nieaktywne okna nie
  używają materiałów (✅ windows), więc zrzut nieaktywnego okna wygląda inaczej niż aktywnego.
- **Nic krytycznego u dołu okna ani u dołu sidebara.** Ludzie przesuwają okna tak, że dolna
  krawędź ląduje poza ekranem (✅ layout, windows, sidebars). Dolny pasek statusu tylko na
  drobną informację o treści okna, jak w Finderze.
- **Treść nie wchodzi pod wycięcie kamery** na górnej krawędzi (✅ layout).
- **Okno ma rozmiar minimalny**, przy którym układ się nie rozpada. Sidebar może chować się
  sam przy zwężaniu okna, jak w Mailu (✅ sidebars).
- **Słowo „window” w tekstach interfejsu.** Nigdy „scene”, „view” ani „panel” (✅ windows, panels).

### 2.1 Panele

- Panel daje szybki dostęp do kontrolek albo informacji o tym, nad czym człowiek pracuje.
  Typowy przykład to inspektor, który podąża za zaznaczeniem (✅ panels).
- Panel ma pasek tytułu z krótkim rzeczownikiem („Recording”, „Inspector”). W menu:
  „Show Inspector”, bez słowa „panel” (✅ panels).
- W panelu lepiej sprawdzają się proste kontrolki (suwak, stepper) niż pola tekstowe (✅ panels).
- Panel nie trafia na listę dokumentów w menu Window i zwykle nie ma przycisku minimalizacji (✅ panels).
- **Panel standardowy zamiast HUD.** Ciemny, przezroczysty HUD jest przewidziany dla
  aplikacji medialnych, może nie pasować do bieżącego wyglądu, a większość kontrolek
  systemowych w nim źle wygląda (✅ panels).
- Domyślnie panele chowają się, gdy aplikacja traci aktywność (✅ panels). **Nasze pływające
  okno nagrywania łamie tę regułę:** patrz §10, odstępstwo 1.

---

## 3. Menu, klawiatura, ustawienia

- **Standardowe menu w standardowej kolejności.** System daje wiele pozycji za darmo, np.
  Copy i Paste w polach tekstowych (✅ the-menu-bar).
- **Stały zestaw pozycji menu.** Pozycję, której nie da się teraz użyć, wyszarz zamiast ją
  ukrywać, bo menu uczy, co aplikacja potrafi (✅ the-menu-bar).
- **Każda akcja z paska narzędzi jest też w menu**, bo pasek można ukryć albo
  przestawić (✅ toolbars).
- **Tytuły menu jednowyrazowe** (✅ the-menu-bar).
- **Nie polegaj na ikonie w pasku menu (menu bar extra)** jako jedynym wskaźniku ani jedynym
  sterowaniu. System ukrywa te ikony, a ich położenie jest nieprzewidywalne (✅ the-menu-bar).
- **Szanuj standardowe skróty.** Własne skróty tylko dla najczęstszych akcji tej aplikacji.
  Nie dokładaj modyfikatora do istniejącego skrótu dla niezwiązanej akcji: Shift-Cmd-Z to
  zawsze Redo (✅ keyboards).
- **Full Keyboard Access.** Całość musi dać się obsłużyć samą klawiaturą (✅ keyboards).
- **Wielokropek w tytule przycisku**, który otwiera kolejne okno albo wymaga dalszych
  danych: „Add Word…” (✅ buttons).
- **Menu kontekstowe (prawy klik)** na słowie, segmencie, mówcy i spotkaniu. Akcje z menu
  kontekstowego muszą mieć też inną drogę dojścia ⚠️ (praktyka platformy, strony
  context-menus nie sprawdzałem).

### 3.1 Ustawienia

- Pozycja **Settings…** w menu aplikacji, skrót **Cmd-,**. **Żadnego** przycisku ustawień na
  pasku narzędzi (✅ settings).
- Okno ustawień ma niekonfigurowalny pasek z przyciskami paneli. Tytuł okna = nazwa aktywnego
  panelu. Okno otwiera się na ostatnio używanym panelu. Minimalizacja i powiększanie są
  wyszarzone (✅ settings).
- 🔀 **U nas ustawienia są zakładką w oknie głównym, nie osobnym oknem** (odstępstwo 3 w §10).
  Z reguł HIG zostaje to, co da się zachować: pozycja **Settings…** w menu aplikacji
  i **Cmd-,** prowadzą do tej zakładki, a zakładka otwiera się na ostatnio używanej sekcji.
  Sekcje, np. **Providers, Models, Audio, Calendar**, wynikają ze speca fazy 1, §1.2.
  **Dictionary nie jest sekcją ustawień**, tylko osobną zakładką.
- **Nie dubluj ustawień systemowych** (dostępność, wygląd), a o tym, co da się wykryć, nie
  pytaj, np. o tryb ciemny (✅ settings).
- SwiftUI: scena `Settings { … }` ⚠️ API. U nas jej nie używamy, bo daje osobne okno.
  Cmd-, trzeba podpiąć do nawigacji ręcznie, np. `CommandGroup(replacing: .appSettings)`
  ⚠️ API z pamięci.

---

## 4. Kursor, najechanie, cele kliknięcia

- **Obszar kliknięcia przycisku: co najmniej 44×44 pt**, niezależnie od sposobu wskazania,
  także kursorem (✅ buttons). Standardowe kontrolki macOS pilnują tego same, a reguła
  dotyczy przede wszystkim **własnych** przycisków.
- **Przycisk-obrazek: ok. 10 px marginesu** między obrazkiem a krawędzią przycisku. Klik
  obok ikony też ma zadziałać (✅ buttons).
- **Słowa w transkrypcie nie są przyciskami**, tylko tekstem, i działają jak tekst:
  podświetlenie pod kursorem, zaznaczenie, menu kontekstowe, dojście z klawiatury. Nie da
  się ich wyrównać do 44 pt i nie należy tego próbować. 📐 Sposób implementacji: patrz §9.
- **Ikona bez podpisu dostaje podpowiedź (tooltip).** macOS pokazuje ją po chwili
  najechania (✅ buttons). SwiftUI: `.help("…")` ⚠️ API.
- **Akcja nigdy nie jest dostępna wyłącznie po najechaniu kursorem.** Musi być też w menu
  kontekstowym albo w menu głównym.
- **Nie rób własnego przycisku z białym tłem i czarnym tekstem.** Ten styl system
  rezerwuje dla stanu „włączony” (✅ buttons).

---

## 5. Typografia

- **SF Pro to font systemu.** Ciało tekstu ma **13 pt**, minimum **10 pt** (✅ typography).
  Liczby z iOS (17 i 11 pt) tu nie obowiązują.
- **macOS nie obsługuje Dynamic Type** (✅ typography). Reguła iOS „wszystko w Dynamic Type”
  nie ma tu zastosowania. Mimo to używaj **stylów semantycznych** (`.body`, `.headline`),
  a nie sztywnych rozmiarów, żeby tekst zgadzał się z kontrolkami systemu.
- **Wbudowane style macOS** (✅ typography):

  | Styl | Rozmiar / interlinia (pt) | Waga | Waga wyróżniona |
  |---|---|---|---|
  | Large Title | 26 / 32 | Regular | Bold |
  | Title 1 | 22 / 26 | Regular | Bold |
  | Title 2 | 17 / 22 | Regular | Bold |
  | Title 3 | 15 / 20 | Regular | Semibold |
  | Headline | 13 / 16 | Bold | Heavy |
  | Body | 13 / 16 | Regular | Semibold |
  | Callout | 12 / 15 | Regular | Semibold |
  | Subheadline | 11 / 14 | Regular | Semibold |
  | Footnote | 10 / 13 | Regular | Semibold |
  | Caption 1 | 10 / 13 | Regular | Medium |
  | Caption 2 | 10 / 13 | Medium | Semibold |

- **Jedna rodzina kroju pisma.** Aplikacja-narzędzie nie potrzebuje pary krój nagłówkowy +
  krój treści (impeccable, tryb Operate). 🔀 Wyjątek: New York w dwóch rolach tytułowych
  (§11.2, odstępstwo 6).
- **Znaczniki czasu cyframi o stałej szerokości** (`.monospacedDigit()` ⚠️ API), żeby
  kolumna czasu się nie przesuwała. To nie jest „monospace dla ozdoby”, tylko pomiar.
- **Transkrypt to tekst do czytania, nie etykieta.** Długość wiersza warto ograniczyć do
  ~65–75 znaków (impeccable). 📐 Czy dać osobny rozmiar tekstu transkryptu w Ustawieniach,
  jak robią czytniki. To decyzja specyfikacji UI.

---

## 6. Kolor i materiały

### 6.1 Kolor

- **Dynamiczne kolory systemowe**, nigdy surowy hex dla tła, tekstu i separatorów, np.
  `controlBackgroundColor`, `controlTextColor`, `alternatingContentBackgroundColors` dla list
  i tabel (✅ color). Mają warianty dla trybu ciemnego i zwiększonego kontrastu (✅ accessibility).
  🔀 Obszar treści ma własną paletę z §11.1 (odstępstwo 4). Sidebar, ramka okna i kontrolki
  systemowe dalej korzystają z kolorów dynamicznych.
- **Kolor akcentu aplikacji działa tylko wtedy**, gdy użytkownik ma w ustawieniach akcent
  „wielokolorowy”. W każdym innym przypadku system podmienia go na kolor użytkownika (✅ color).
  **Wniosek: akcent nigdy nie niesie znaczenia.** Nie może oznaczać np. stanu nagrywania ani
  kanału „Me”. 🔀 W treści używamy stałego akcentu z §11.1 (odstępstwo 5). Zasada zostaje:
  kolor zawsze idzie w parze z ikoną i słowem.
- **Stały kolor ikony w sidebarze** nie jest nadpisywany przez akcent użytkownika, więc
  nadaje się do ikon, których kolor coś znaczy (✅ color, sidebars).
- **Kontrast co najmniej 4,5:1**, sprawdzany w trybie jasnym **i** ciemnym (✅ accessibility).
- **Informacja nie tylko kolorem.** Dodaj kształt, ikonę albo podpis (✅ accessibility).
  Dla nas oznacza to, że **kolor mówcy zawsze idzie w parze z nazwą albo inicjałami**.
  📐 Paleta mówców (do ~10 osób, rozróżnialnych w obu trybach i przy daltonizmie) to
  prawdziwa decyzja projektowa, do zmierzenia, a nie do zgadywania.
- **Tryb ciemny to pełnoprawny wygląd.** Przy akcencie grafitowym tła okien przejmują kolor
  tapety (tzw. desktop tinting). Własne tła warto robić częściowo przezroczyste, żeby to
  działało (✅ dark-mode).
- **Jasny czy ciemny wybiera użytkownik w systemie.** Aplikacja nie ma własnego przełącznika
  trybu (✅ settings: nie dubluj ustawień systemowych).

### 6.2 Materiały i Liquid Glass

- **Liquid Glass tylko w warstwie funkcjonalnej**, czyli w paskach narzędzi, sidebarach
  i kontrolkach unoszących się nad treścią. **Nigdy w warstwie treści** (✅ materials).
- **Komponenty systemowe dostają Liquid Glass automatycznie.** Na własnych kontrolkach
  stosuj je oszczędnie, tylko dla najważniejszych elementów funkcjonalnych (✅ materials).
  Kandydat w naszej aplikacji to pływające okno nagrywania, i tylko ono.
- Wariant **regular** dla komponentów z tekstem, a **clear** tylko nad bogatym tłem, np.
  wideo (✅ materials). U nas więc zawsze regular.
- W warstwie treści używaj **materiałów standardowych**, dobranych według znaczenia, a nie
  według koloru, jaki dają. Na materiale kładź kolory „vibrant” (✅ materials).
- Żadnego ręcznie robionego szkła ani rozmycia dla ozdoby.
- SwiftUI: `.glassEffect()` ⚠️ API z pamięci (macOS 26+).

---

## 7. Ikony i ruch

- **SF Symbols** we wszystkich ikonach interfejsu, bez domieszki webowych zestawów ikon.
  Zakaz używania symboli (i podobnych do nich obrazków) w ikonie aplikacji i logo (✅ sf-symbols).
  Do dyspozycji są cztery tryby renderowania: monochrome, hierarchical, palette i multicolor (✅ sf-symbols).
- **Ruch sygnalizuje zmianę stanu, nie zdobi.** Przejścia 150–250 ms. Żadnej choreografii
  przy ładowaniu (impeccable, tryb Operate).
- **Reduce Motion:** ogranicz ruch, gdy ustawienie jest włączone. Ostrożnie z miganiem
  (✅ accessibility). Uwaga na **wskaźnik nagrywania**: pulsowanie przy włączonym Reduce
  Motion zastąp stałym stanem.
- **Reduce Transparency / Increase Contrast** zmieniają wygląd Liquid Glass i materiałów
  (✅ materials). Sprawdzaj z nimi pływające okno.

---

## 8. Dostępność

- **VoiceOver:** każda ikona bez podpisu ma etykietę dostępności. Elementy osi czasu
  i słowa transkryptu też muszą dać się odczytać ⚠️ (API `.accessibilityLabel` z pamięci).
- **Full Keyboard Access:** patrz §3.
- ⚠️ **Accessibility Inspector jest częścią Xcode**, a my Xcode nie mamy (specyfikacja
  rdzenia, §2). Kontrolę dostępności trzeba robić inaczej, 📐 np. testem, który przechodzi
  drzewo dostępności okna przez API AX.

---

## 9. Weryfikacja bez Xcode

Nie mamy Xcode, więc **nie ma SwiftUI Previews** ⚠️ (to funkcja Xcode). Pozostają dwie drogi:

1. **Migawki z danymi testowymi (podstawowa).** Osobny cel debugowy renderuje każdy ekran
   w każdym stanie (pusty, ładowanie, błąd, pełny, 85 minut transkryptu) i w obu trybach
   (jasny i ciemny) do plików PNG w `.design/review/`. Claude czyta te PNG przez narzędzie
   Read.
   - 📐 **Spike:** `ImageRenderer` nie renderuje widoków opartych na AppKit (listy, pola
     tekstowe) ⚠️. Alternatywa to `NSHostingView` w oknie poza ekranem +
     `cacheDisplay(in:to:)`. Materiały i vibrancy mogą poza ekranem wyglądać inaczej niż na
     żywo, więc to trzeba zmierzyć, a nie zakładać.
   - Tryb ciemny ustawiaj per widok albo per aplikację (`NSApp.appearance`), **nigdy
     przełączając tryb całego systemu**.
2. **Zrzut działającej aplikacji (uzupełniająca).** `screencapture -x -o -l <id okna>`.
   📐 Wymaga uprawnienia Nagrywanie ekranu dla terminala. Identyfikator okna trzeba wyciągnąć
   przez `CGWindowListCopyWindowInfo`.

Zasady przeglądu (za impeccable):

- **Najwyżej dwie rundy:** zbuduj całość, obejrzyj wszystkie stany naraz, popraw wszystko
  jedną partią, potwierdź drugą rundą i na tym koniec. Resztę robi świeży przegląd (krytyka
  w osobnym agencie).
- **W raporcie napisz, skąd pochodzi dowód:** migawka, zrzut na żywo czy tylko lektura kodu.

**Pytanie do specyfikacji UI (📐):** edytor transkryptu. 85 minut rozmowy to rząd 10 tys.
słów, a każde z nich ma być klikalne (poprawka → alias). Trzeba zmierzyć, czy wytrzyma to
czysty SwiftUI (`Text` / `LazyVStack`), czy potrzebny jest `NSTextView` z atrybutami na
słowach. Od tego zależy wygląd podświetlenia, zaznaczania i menu kontekstowego.

---

## 10. Świadome odstępstwa od HIG

| # | Reguła HIG | Co robimy | Dlaczego |
|---|---|---|---|
| 1 | 🔀 Panele chowają się, gdy aplikacja traci aktywność (✅ panels) | **Pływające okno nagrywania zostaje na ekranie**, gdy aktywny jest Teams czy przeglądarka | Nagrywamy spotkanie, które odbywa się w innej aplikacji. Wskaźnik „Recording / Not recording” i przycisk stop muszą być widoczne właśnie wtedy. Zmierzona awaria bez tego: 70 minut przypadkowego dźwięku (W§1) |
| 2 | 🔀 Klik w panel zwykle go aktywuje | **Klik w okno nagrywania nie odbiera fokusu** aplikacji ze spotkaniem ⚠️ (AppKit: `NSPanel` z `.nonactivatingPanel`; sam SwiftUI `.windowLevel(.floating)` tego nie daje, do sprawdzenia) | Użytkownik w trakcie rozmowy nie może przez przypadek przełączyć okna Teams |
| 3 | 🔀 Ustawienia w osobnym oknie, otwieranym z menu aplikacji i skrótem Cmd-, (✅ settings) | **Ustawienia są zakładką w oknie głównym.** Pozycja **Settings…** w menu i **Cmd-,** prowadzą do tej zakładki | Decyzja użytkownika z 2026-09-24 (spec fazy 1, §1.2). Na zrzutach z tego dnia pięciu konkurentów (Narada, Wispr Flow, FluidVoice, MacParakeet, Granola) trzyma Ustawienia w nawigacji bocznej. Zachowujemy to, czego HIG pilnuje ze względu na odkrywalność: pozycję w menu i standardowy skrót |

| 4 | 🔀 Dynamiczne kolory systemowe, bez surowego hex (§6.1, ✅ color) | **Własna ciepła paleta w obszarze treści** (§11.1), jasna i ciemna, zdefiniowana w kodzie jako kolory dynamiczne | Odbiór F15-T13 (2026-10-15): domyślne szare `Form`/`GroupBox` wyglądały „jak Windows 98 z zaokrąglonymi rogami”. Użytkownik wybrał kierunek B. Zostają warianty jasny i ciemny oraz kontrast ≥ 4,5:1, zmierzony dla każdej pary w §11.1. Sidebar i kontrolki systemowe nie są przemalowywane |
| 5 | 🔀 Akcent aplikacji ustępuje akcentowi użytkownika (✅ color) | **Stały akcent: stonowana zieleń** (`tint` w treści) | Akcent użytkownika (np. niebieski) gryzie się z ciepłym tłem. Kolor nadal niczego nie znaczy sam: każdy stan to ikona i słowo (§11.4) |
| 6 | 🔀 Jedna rodzina kroju (§5, impeccable) | **New York w dwóch rolach**: tytuł strony i tytuł spotkania (§11.2). Wszystkie etykiety, nagłówki sekcji, przyciski i dane zostają w SF | Wzór: Granola i Wispr Flow. Szeryf w etykietach UI odpadł w teście „product slop” (impeccable, `operate.md`), dlatego jest ograniczony do tytułów. New York jest krojem systemowym (`design: .serif`), więc nie trzeba niczego dołączać |
| 7 | 🔀 Standardowe style przycisków; bez własnego przycisku o białym tle i czarnym tekście (§4, ✅ buttons) | **Przyciski-pigułki** (`Capsule`, własny `ButtonStyle`). Przycisk drugorzędny w trybie jasnym jest biały z ciemnym tekstem | Część kierunku B. HIG rezerwuje ten wygląd dla stanu „włączony”, dlatego **pigułka nigdy nie jest przełącznikiem**. Przełączniki to systemowy `Toggle(.switch)`, a wybory to `Picker`/`Menu`. Wymiary, fokus z klawiatury i pozycje menu bez zmian |

Każde nowe odstępstwo dopisuj tutaj, z uzasadnieniem opartym na pomiarze albo wymaganiu.

---

## 11. Język wizualny (kierunek B, ciepły)

> Status: **zatwierdzone przez użytkownika 2026-10-15** (sesja designu po odbiorze F15-T13).
> Kierunek B został wybrany spośród trzech (A Native+, B Ciepły, C Redakcyjny), a potem
> przeszedł test „product slop” z impeccable (`skill/reference/operate.md`,
> `craft-floor.md`). Makiety jasne i ciemne: `docs/design/makiety/ekrany-b.html`
> (`?s=home|meeting|presets|settings|add|pill`), wyrenderowane do `b-*.png` w skali 2×,
> gdzie 1 px = 1 pt. Kierunki odrzucone: `kierunek-a.png`, `kierunek-c.png`.
> Makiety B pokazują okno z **macOS 27 „Golden Gate”** (sidebar przy krawędzi okna,
> bardziej kwadratowe rogi). Makiety kierunków mają jeszcze pływający sidebar z macOS 26.

**Zasada:** system wizualny daje aplikacji paletę, typografię, gęstość i jeden charakterystyczny
ruch: ciepłe tło z białymi kartami i tytuły w New York. Nie zmienia nawigacji ani kontrolek.
Ramka okna, `NavigationSplitView` z systemowym sidebarem, menu, `Toggle`, `Picker`, pola
tekstowe i popovery zostają systemowe. Przemalowujemy wyłącznie obszar treści.

### 11.1 Kolory

Każdy token to jeden kolor dynamiczny w kodzie:
`NSColor(name:dynamicProvider:)` → `Color(nsColor:)` ⚠️ API z pamięci. Katalog zasobów
(`Assets.xcassets`) odpada, bo kompiluje go `actool` z Xcode, którego nie mamy. Wariant
wybiera `appearance.bestMatch(from: [.aqua, .darkAqua])`.

| Token | Rola | Jasny | Ciemny |
|---|---|---|---|
| `background` | tło obszaru treści | `#F7F6F2` | `#1C1C1B` |
| `card` | karta, pole tekstowe, przycisk drugorzędny | `#FFFFFF` | `#262624` (pole: `#2E2E2C`) |
| `sunk` | wnęka: pasek generowania, wiersz dodawania | `#F1EFE9` | `#2E2E2C` |
| `selection` | zaznaczony wiersz listy presetów | `#3C3214` 8% | `#FFFFFF` 8% |
| `line` | obwódka karty i pola (0,5 pt) | `#3C3214` 14% | `#FFFFFF` 11% |
| `line2` | separator wierszy | `#3C3214` 8% | `#FFFFFF` 6% |
| `text` | tekst główny | `#22211E` | `#ECEBE6` |
| `text2` | etykiety, metadane, stany neutralne | `#666259` (D1; było `#6F6B62`) | `#9A978F` |
| `text3` | tylko kontrolki nieaktywne (zwolnione z wymogu kontrastu WCAG) | `#A8A49A` | `#6B6963` |
| `primary` / `onPrimary` | jedyny główny przycisk na ekranie | `#22211E` / `#FFFFFF` | `#ECEBE6` / `#1C1C1B` |
| `accent` | stan „gotowe/zweryfikowane”, `Toggle`, `tint` | `#2F6B4F` | `#7CC39C` |
| `rec` | nagrywanie, błąd | `#C4271C` | `#FF6B5E` |
| `warn` | ostrzeżenie (np. język Auto) | `#8A5A00` | `#E0B050` |
| kropka nagrywania | stała, poza paletą | `#FF3B30` (systemRed) | `#FF3B30` |

Zmierzony kontrast (WCAG): `text`/`background` 14,9 i 14,3; `text2`/`background` 5,62
i 5,85; `text2`/`card` 6,08 i 5,20; `text2`/`selection` 4,88 (jasny; przy `#6F6B62` było 4,26 — D1); `accent` 5,36 (na `#E6EFE8`) i 7,32 (na `card`); `rec` 4,90 (na
`#FBE9E6`) i 5,43; `warn` 5,28 i 7,58; `text2`/`sunk` 5,28 i 4,66. Tło `rec`/`accent` nie
występuje w UI, ale pomiar na nim jest najgorszym przypadkiem. Każdą nową parę mierz przed użyciem.

**Placeholdery** (pole szukania, „Paste your key”) mają systemowy kolor podpowiedzi, który
dają natywne `TextField` i `.searchable`, a nie `text3`. `text3` ma tylko 2,3–3,1:1, więc nadaje się wyłącznie
dla stanu nieaktywnego. Na makietach placeholdery są w `text3` tylko poglądowo.

- Sidebar **nie dostaje** koloru `background`, tylko systemowy materiał. W macOS 27 sidebar
  sięga krawędzi okna, ma tło ciemniejsze niż treść i kolorowe ikony. Na makiecie
  (`#EBE8E0` / `#151514`, ikony w `accent`) to przybliżenie: ⚠️ odcień i kolor ikon wybiera
  system (`tint` aplikacji albo akcent użytkownika), sprawdzić w migawkach T0.
- 📐 **Increase Contrast**: provider powinien zwracać ciemniejsze `text2` i `line` przy
  `.accessibilityHighContrastAqua`. Do sprawdzenia w migawkach T0.
- Czerwień nagrywania i błędu różni się od akcentu (zieleń), więc nie ma kolizji znaczeń.

### 11.2 Typografia

| Rola | Krój | Rozmiar / interlinia | Waga | SwiftUI |
|---|---|---|---|---|
| Tytuł strony (Meetings, Presets, Settings) | New York | 30 / 36, tracking −0,3 | Regular | `.system(size: 30, design: .serif)` |
| Tytuł spotkania (edytowalny) | New York | 28 / 34, tracking −0,3 | Regular | `.system(size: 28, design: .serif)` |
| Nagłówek sekcji / karty | SF | 13 / 16 | Semibold | `.headline` ⚠️ (13 pt Bold na macOS, zamiennie `.system(size: 13, weight: .semibold)`) |
| Tekst UI, etykiety pól | SF | 13 / 16 | Regular | `.body` |
| Metadane w linii, stany | SF | 12 / 15 | Regular | `.callout` |
| Podpis pod polem, data w wierszu | SF | 11 / 14 | Regular | `.subheadline` |
| Treść notatki | SF | 14 / 22 | Regular | `NSTextView` tylko do odczytu (D6): `NSParagraphStyle` z interlinią 22 pt, wcięciem punktów 18 pt i odstępem 16 pt między akapitami |
| Nagłówek w notatce | SF | 15 / 20 | Semibold | `.system(size: 15, weight: .semibold)` |

- Szeryf **tylko** w dwóch tytułach. Nagłówki sekcji, przyciski, statusy i dane zawsze SF.
- Czasy i liczniki: `.monospacedDigit()` (§5).
- Szerokość kolumny treści ogranicza długość wiersza notatki do ~75 znaków (640 pt przy 14 pt).

### 11.3 Odstępy, promienie, głębia

- **Siatka 4 pt.** Kroki: 4, 8, 12, 16, 22, 28. Między grupami więcej (22–26), w grupie
  mniej (8–12). Nad nagłówkiem sekcji więcej miejsca niż pod nim (22 / 8).
- **Kolumna treści**, wyśrodkowana w obszarze szczegółów: lista spotkań 580 pt, spotkanie
  i Settings 640 pt, Presets 700 pt (lista 196 + edytor). Górny margines 54 pt, bo pod
  paskiem tytułu.
- **Promienie:** karta 12, pole tekstowe i popup 7, zaznaczenie w liście 8, panel
  pigułki 20. Przyciski i pigułka nagrywania to pełna kapsuła. Rogi okna rysuje system
  (w macOS 27 jednakowe dla wszystkich aplikacji); karta 12 ma ich nie przekraczać.
- **Głębia:** w treści tylko obwódka 0,5 pt (`line`), **bez cieni**. Cień i materiał ma tylko
  pływająca pigułka (Liquid Glass, §6.2). Zakaz łączenia obwódki z szerokim cieniem.
- **Wiersze:** wiersz listy spotkań ma 9 pt w pionie i separator `line2`, wiersz formularza
  10 / 16 pt z etykietą w kolumnie 130 pt.

### 11.4 Komponenty wspólne

Wdrażane raz i używane we wszystkich widokach (por. F15-T13 część B pkt 3). Bez makr:
`ButtonStyle`/`ViewModifier` jako zwykłe struktury, stan przez `ObservableObject`.

| Komponent | Opis | Stany |
|---|---|---|
| `PageTitle`, `DocumentTitle` | tytuły New York z §11.2 | — |
| `SectionHeader` | SF 13 Semibold, opcjonalny dopisek `text2` („— optional”) i kontrolka po prawej (`Toggle`) | — |
| `Card` | `card` + obwódka 0,5 pt + promień 12; zawartość to wiersze z separatorami | — |
| `FormRow` | etykieta (130 pt, `text2`) + kontrolka; pod kontrolką opcjonalny podpis 11 pt | błąd: podpis w `rec` |
| `PillButtonStyle` | kapsuła; `.primary` (wypełniona `primary`), `.secondary` (`card` + obwódka), `.small` (24 pt) | hover: tło `sunk`; wciśnięty: krycie 0,7; nieaktywny: tekst `text3`; fokus: systemowy pierścień ⚠️ sprawdzić w migawkach, czy własny `ButtonStyle` go zachowuje |
| `StateLabel` | ikona SF Symbol + słowo, 12 pt; rodzaje: `ok` (`accent`, ✓), `bad` (`rec`, ✗), `live` (`rec`, kropka, Semibold, licznik; **w pigułce słowo w `text`, czerwona tylko kropka** — D2), `neutral` (`text2`), `progress` (mały `ProgressView` lub pasek 38×4 + %) | — |
| `ModelField` | popup „Dostawca · id ⌄” (dostawca w `text2`), otwiera `ModelPicker` | — |
| `FieldMenuStyle` | **wszystkie popupy** (preset na karcie Record i w pigułce, Language, Notes language, Provider, szablon) wyglądają jak pole: `card`/`sunk`, obwódka, promień 7, mały ⌄. Pod spodem standardowe `Menu`/`Picker` (D8) | — |
| `MetaLine` | jedna linia `text2`: „Oct 15, 11:29 · 42 min · Preset Polish” | — |

**Na ekranie jest najwyżej jeden przycisk `.primary`:** Record, Save, Save & verify. Wyjątek (D4):
w rozwiniętym formularzu dodawania dostawcy „Save & verify” to mały primary (24 pt) obok Save
w dolnym pasku, jak na `b-add.png`.

### 11.5 Ekrany (stan zatwierdzony)

- **Strona główna** (`b-home.png`): tytuł i wyszukiwarka-kapsuła, karta „Record a meeting”
  (popup presetu + „PL · model” w `text2` + Record jako `.primary` z czerwoną kropką), pod
  nią lista po dniach, bez ikon w wierszach, ze stanem po prawej. „Correction failed” ma obok
  małą pigułkę Retry.
- **Widok spotkania, Summary** (`b-meeting.png`): przycisk wstecz (kapsuła) i „⋯” w pasku,
  tytuł New York, `MetaLine`, zakładki tekstowe z podkreśleniem 2 pt. Pasek generowania we
  wnęce `sunk`: popup szablonu, kontekst (jedna linia, obcięta), model w 11 pt, Regenerate
  (ikona `arrow.clockwise`, nie iskierki) i Copy. Niżej notatka (§11.2), cała jako jeden
  zaznaczalny `NSTextView` (D6). **Wstecz i „⋯” są (D5)**; „⋯” zawiera Copy notes, Show in
  Finder i Delete meeting…, a każda z tych akcji jest też w menu aplikacji (§3).
- **Presets** (`b-presets.png`): lista presetów (zaznaczenie `selection`, „default” w
  metadanych zamiast znaczka) i edytor: nazwa w polu, sekcje Speech to text / Correction
  (`Toggle`) / Summary jako karty z `FormRow`. Wynik sondy to linia `StateLabel` pod wyborem
  języka. Na dole pasek: „Unsaved changes” oraz Cancel / Save.
- **Settings** (`b-settings.png`, `b-add.png`): karta Providers z wierszami „nazwa, adres,
  stan, ⋯”. Ograniczenie dostawcy jest w adresie („correction and summary only, no
  transcription”). Ostatni wiersz karty to **„Add: OpenRouter · Ollama · Custom…”** (małe
  pigułki; dodany już dostawca jest nieaktywny). Klik **rozwija formularz w miejscu**, w
  karcie: gotowy adres, pole klucza, wynik weryfikacji w tej samej linii („✓ Verified · 312
  models available” albo „✗ Key rejected (401). Check the key and try again.”), Cancel /
  Save & verify. **Decyzja użytkownika z 2026-10-15:** kafelki z uwagi 7 i arkusz z
  spec §5.4 zostają zastąpione, a funkcja się nie zmienia. Pod spodem karta Archive search
  i zdanie z odnośnikiem „Open Presets”.
- **Pigułka** (`b-pill.png`): `NSPanel` z Liquid Glass (`.glassEffect()` ⚠️, macOS 26+, wariant
  regular). Przed startem: preset ⌄ + Record. Zwinięta: kropka, poziom, licznik, Stop
  (kapsuła z czerwonym kwadratem i słowem), ⌃. Rozwinięta (tylko odczyt): stan i licznik,
  preset, dwa mierniki (System audio, Microphone) z ✓, **nazwa mikrofonu pogrubiona**,
  Open note / Stop. Reduce Motion: poziom bez animacji (§7). **Bez przycisku zamknięcia
  podczas nagrywania (D3**, odstępstwo 1, W§1). Przed startem pigułkę chowa pozycja w menu
  Window („Hide Recording Window”). Okno pigułki dopasowane do treści, bez przezroczystego
  marginesu łapiącego kliknięcia.
- **Templates** (`b-templates.png`, odbiór 2026-10-16, uwaga 2): układ jak Presets (lista 196 pt +
  edytor). Szablon to **lista sekcji** (wzór Granola): karta z tytułem (SF 13 Semibold) i
  instrukcją (`text2`), uchwyt ⋮⋮ do zmiany kolejności, ✕ do usunięcia (to samo w menu
  kontekstowym), pod listą „Add section”. Nad sekcjami opcjonalne pole „About this meeting type”.
  Pola rosną z treścią, bez własnego przewijania (koniec szarego toru paska przewijania). Prompt dla
  modelu składa się z sekcji po kolei. Nowe pole `sections` jest opcjonalne (E6); stary szablon z
  jednym promptem wczytuje się jako jedna sekcja. **Wbudowane szablony da się edytować w miejscu**
  (decyzja użytkownika 2026-10-16, zmienia spec §5.4 „tylko do odczytu”): oznaczenie „Built-in ·
  edited”, w „⋯” Duplicate i Reset to default. Własne: w „⋯” Duplicate i Delete template… z
  potwierdzeniem. Wbudowanych nie da się usunąć, bo wystarcza reset. Dół: „Unsaved changes”,
  Cancel / Save. Bez ikon i emoji przy szablonach (§11.6).
- **Pasek narzędzi okna** (odbiór 2026-10-16, uwaga 1): bez osobnego tła i linii pod spodem; ciepłe
  `background` sięga górnej krawędzi okna, tytułu w pasku nie ma (tytuł strony jest w treści). W pasku
  zostają tylko przycisk sidebara i, w widoku spotkania, wstecz i „⋯”.
- **Sidebar (D7):** Meetings na górze; Presets / Templates / Settings na dole, **bez nagłówka
  sekcji** („Setup” znika).

Decyzje D1–D8 podjął użytkownik 2026-10-15 po wdrożeniu na `faza15-design-b`
(raport `docs/superpowers/reports/F15-T13-czesc-B.md`).

### 11.6 Czego nie robimy (wynik testu „product slop”)

Te elementy były w pierwszej wersji makiet i zostały usunięte:

- ikony w kwadracikach przy każdym wierszu, jeśli nie niosą informacji;
- pastelowe tła pod statusami (stan = ikona + słowo w kolorze, bez tła);
- szeryf w etykietach, nagłówkach sekcji i przyciskach;
- siatki jednakowych kart „ikona + nagłówek + opis” oraz wymyślone logotypy dostawców;
- etykiety wersalikami nad nagłówkami („ADD A PROVIDER”);
- modal tam, gdzie wystarcza rozwinięcie w miejscu;
- monospace jako ozdoba (adresy URL to zwykły tekst; monospace tylko dla kodu i pomiarów);
- iskierki ✨ jako ikona „AI”;
- rzędy chipów z ikonami na metadane (zamiast tego jedna linia tekstu);
- obwódka połączona z cieniem na kartach.

### 11.7 Weryfikacja wdrożenia

Migawki T0 (§9) przed i po, w obu motywach, porównane z `b-*.png`. Kontrast nowych par
mierzony liczbowo, nie na oko. Pełna obsługa klawiaturą (Tab przez pigułki, fokus widoczny).
Odbiór na żywo u użytkownika.

### 11.8 Kontekst: trendy UX na macOS i Windows (research 2026-10-15)

Po co: sprawdzić, czy kierunek B nie zestarzeje się zaraz po wdrożeniu. Źródła są na końcu.
Pewność oznaczona: **mocne** (ogłoszenie producenta, recenzja wydanej wersji), **średnie**
(relacja z drugiej ręki, analizy systemów designu), **słabe** (listy trendów agencji).

**Teraz (2026)**

- **macOS 27 „Golden Gate” (wydany 09.2026) koryguje Tahoe — mocne.**
  - Liquid Glass ma bardziej jednolitą refrakcję i lepszy kontrast. W Ustawieniach → Wygląd
    jest suwak przezroczystości („ultra-clear” → „fully tinted”).
  - Sidebar wraca do krawędzi okna, z ciemniejszym tłem i kolorowymi ikonami.
  - Paski narzędzi znów są paskami, a nie pływającymi przyciskami.
  - Rogi okien są jednakowe we wszystkich aplikacjach.
  - Z pozycji menu zniknęła większość ikon.
  - Kierunek Apple: szkło zostaje, ale spokojniejsze i regulowane przez użytkownika.
- **Liquid Glass jest na stałe — średnie.** Według relacji z rozmów w Apple Xcode 27 nie
  będzie respektował flagi odraczającej szkło, a od I kw. 2027 ma być włączone wszędzie.
  My budujemy na CLT, więc dostajemy wygląd tego SDK, którym kompilujemy.
- **Windows trzyma się Fluent 2 i WinUI 3 — mocne.** Na Build 2026 Microsoft ogłosił, że
  nie będzie nowego frameworka ani języka wizualnego. Starsze dialogi w powłoce są wymieniane na
  WinUI (Mica, Acrylic, zaokrąglone rogi, tryb ciemny), a rozwój toczy się publicznie na
  GitHubie. Tło: krytyka aplikacji na WebView2/Electron za zużycie pamięci.
- **Natywne aplikacje Maca nadal przeważają — średnie.** W próbce 2440 aplikacji (III 2026)
  70,8% jest natywnych, a 19,3% to Electron. Głośna jest krytyka Electronu za pamięć i baterię.
- **Ciepły minimalizm w narzędziach do notatek — średnie.** Notion, Granola i Craft mają
  kremowe lub ciepłe tło, szeryfowe tytuły i tekst w sansie, zamiast zimnych szarości. To dokładnie
  kierunek B.
- **Spokojniejsze interfejsy narzędzi — mocne (Linear).** Refresh Lineara z 2026 przygasza
  sidebar, żeby wyróżnić treść, ogranicza ikony, zmiękcza separatory i ujednolica nagłówki,
  zachowując gęstość informacji. To ta sama linia co test „slop” w §11.6.
- **AI w miejscu pracy zamiast czatu z boku — słabe/średnie.** Wynik AI pojawia się tam, gdzie
  się pracuje. Ważne są: widoczne źródło (który model, z czego powstało), kontrola człowieka,
  wznowienie przy błędzie i jawne stany oczekiwania.

**Za rok (2027) — niska pewność**

- Apple dalej łagodzi szkło i oddaje kontrolę użytkownikowi. Szkło nie znika.
- Windows wymienia kolejne dialogi na WinUI. Wielkie aplikacje webowe (Teams, Outlook) mogą
  zostać przy WebView jeszcze długo.
- O „generatywnym UI” i nawigacji rozmową piszą głównie agencje, twardych danych nie ma.
- Ciepła typografia redakcyjna raczej zostanie, ale to opinia, nie pomiar.

**Wnioski dla MeetNotes**

1. Kierunek B jest zgodny z tym, co w 2026 robią najlepsze narzędzia do notatek. Test
   „slop” idzie w tę samą stronę co Linear. Nic do zmiany w palecie ani typografii.
2. **Sidebar, pasek narzędzi i rogi zostawiamy systemowi** (tak już mówi zasada §11), bo
   zmieniają się co wersję macOS. Makiety B pokazują już macOS 27.
3. **Pozycje menu bez ikon** (macOS 27). Dotyczy menu aplikacji i menu kontekstowych.
4. **Szkło tylko w pigułce i tylko systemowe** (`.glassEffect()`), żeby suwak przezroczystości
   użytkownika działał też u nas. Żadnego własnego rozmycia.
5. Notatka już pokazuje źródło (model, szablon, kontekst w pasku generowania). Pomysł do fazy 2:
   punkty notatki z odnośnikiem do miejsca w transkrypcie, czyli widoczne źródło.

**Źródła**

- MacRumors, „Apple Announces macOS 27 Golden Gate…”, 2026-06-08 —
  https://www.macrumors.com/2026/06/08/apple-announces-macos-golden-gate/
- Six Colors, „macOS 27 Golden Gate review”, 2026-09 —
  https://sixcolors.com/post/2026/09/macos-27-golden-gate-review-bridging-the-tahoe-gap/
- 9to5Mac, zmiany dla krytyków Tahoe, 2026-06-09 —
  https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/
- Michael Tsai, „Liquid Glass Is Permanent”, 2026-03-23 —
  https://mjtsai.com/blog/2026/03/23/liquid-glass-is-permanent
- Windows Latest, powrót natywnych aplikacji, 2026-08-29 —
  https://www.windowslatest.com/2026/08/29/windows-11s-native-app-era-is-coming-back-after-years-of-web-app-slop-and-microsoft-is-finally-building-it-in-public/
- Fluent 2, Windows — https://fluent2.microsoft.design/components/windows
- Linear, „Behind the latest design refresh” — https://linear.app/now/behind-the-latest-design-refresh
- Desktop Insights, „State of desktop app development 2026” —
  https://desktopinsights.com/blog/state-of-desktop-app-development-2026
- Analizy ciepłego minimalizmu (Notion, Craft): https://getdesign.md/notion/design-md,
  https://www.webdesignhot.com/design.md/craft/
- AI UX: https://www.lazarev.agency/articles/ai-ux-patterns,
  https://aiindigo.com/blog/beyond-the-chatbot-5-ai-native-ux-patterns-for-modern-document-apps

---

## Źródła

Apple Human Interface Guidelines, pobrane 2026-09-24 jako JSON z
`developer.apple.com/tutorials/data/design/human-interface-guidelines/<strona>.json`,
strony: typography, buttons, layout, windows, panels, color, materials, accessibility,
keyboards, the-menu-bar, sidebars, toolbars, settings, dark-mode, sf-symbols.
Zasady trybu Operate: impeccable `skill/reference/operate.md` i `craft-floor.md`
(commit z 2026-09-22).
