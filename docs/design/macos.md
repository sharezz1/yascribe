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
  krój treści (impeccable, tryb Operate).
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
- **Kolor akcentu aplikacji działa tylko wtedy**, gdy użytkownik ma w ustawieniach akcent
  „wielokolorowy”. W każdym innym przypadku system podmienia go na kolor użytkownika (✅ color).
  **Wniosek: akcent nigdy nie niesie znaczenia.** Nie może oznaczać np. stanu nagrywania ani
  kanału „Me”.
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

Każde nowe odstępstwo dopisuj tutaj, z uzasadnieniem opartym na pomiarze albo wymaganiu.

---

## Źródła

Apple Human Interface Guidelines, pobrane 2026-09-24 jako JSON z
`developer.apple.com/tutorials/data/design/human-interface-guidelines/<strona>.json`,
strony: typography, buttons, layout, windows, panels, color, materials, accessibility,
keyboards, the-menu-bar, sidebars, toolbars, settings, dark-mode, sf-symbols.
Zasady trybu Operate: impeccable `skill/reference/operate.md` i `craft-floor.md`
(commit z 2026-09-22).
