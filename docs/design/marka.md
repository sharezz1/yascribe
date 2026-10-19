# Marka: nazwa, logo, ikona

> Status: **w toku, 2026-10-19**. Zapadły: nazwa, motto, kompozycja znaku. **Tymczasowo zestaw 3**
> (użytkownik: „na razie v3”, kolory można zmienić później; konsultuje z żoną). Ikona **jest
> podpięta do paczki** (zgoda użytkownika 2026-10-19), z wersją na małe rozmiary. Logotyp **zaakceptowany**
> (2026-10-19). Czeka: warstwy pod macOS 27, licencja kroju przed publicznym użyciem.
> Sesja designu nie dotyka `Sources/` ani `Tests/`; `scripts/bundle.sh` i `Resources/Info.plist`
> zmienione tylko za zgodą (sekcja „Ikona w paczce”).

## Zapadło (decyzje użytkownika)

| Co | Decyzja | Uwagi |
|---|---|---|
| Nazwa | **Yascribe** (jedno r) | „Y” jak [firma] + „scribe”. Wariant z dwoma r odrzucony po zobaczeniu słów obok siebie |
| Motto (EN) | **What's it like to be a scribe?** | Nawiązanie do monologu skryby z „Asterix i Obelix: Misja Kleopatra”. Polskie źródło: „Jak to jest być skrybą?”. Francuskie „C'est une bonne situation, ça, scribe ?” znaczy „czy to dobra posada”; angielskie napisy tłumaczą to dosłownie i bez sensu. Motto jest własnym sformułowaniem, nie cytatem napisów |
| Znak | **Pióro między dwiema falami dźwięku** | Słupki po bokach to dwa kanały nagrania (system i mikrofon), pióro to zapis. Kompozycja pochodzi z obrazu wygenerowanego przez ChatGPT (`marka/zrodlo-chatgpt-zlote-pioro.png`), przerysowana płasko |
| Litera Y | **tylko w logotypie** (nazwa „Yascribe”), nie w ikonie | Do potwierdzenia przy logotypie. Próby z Y w znaku (kierunki 1–8) użytkownik odrzucił |
| Gradienty, połysk | **nie** | „Z daleka widać, że to AI slop” (użytkownik). Zgodne z §11.6 w `macos.md` |

## Kolizje nazwy (sprawdzone 2026-10-19, tylko wyszukiwarka i whois)

- Brak aplikacji, firmy ani produktu „Yascribe” w wynikach. Najbliższe brzmieniem:
  [YouScribe](https://en.wikipedia.org/wiki/YouScribe), francuska biblioteka cyfrowa.
- Domeny: `yascribe.pl`, `.io`, `.net` wyglądają na wolne; `.com` zajęta (OVH, odpowiada 403);
  `.app` prawdopodobnie zajęta (whois zwraca status ACTIVE, niepewne).
- **Nie sprawdzono:** znaków towarowych (EUIPO, UPRP, USPTO), App Store.

## Znak: pliki

`docs/design/marka/`:

| Plik | Co |
|---|---|
| `w1.svg` … `w4.svg` | ikona 1024×1024 w czterech zestawach kolorów (poniżej) |
| `podglad-wersje-kolorow.png` | podgląd zestawów, 300/128/64/32/16 px |
| `ksztalty.json` | wyciągnięte kształty: kontur pióra (z szparą) i prostokąty słupków |
| `wektoryzuj.py` | obraz źródłowy → `ksztalty.json` (marching squares, tylko Python + Pillow) |
| `zloz-ikone.py` | `ksztalty.json` → SVG i podgląd HTML. Zestawy kolorów są w tablicy `V` |
| `zrodlo-chatgpt-zlote-pioro.png` | obraz źródłowy (461×428, złote pióro, turkusowe słupki, granat) |

Pióro ma kontur z nacięciami i szparą jako otwór (`fill-rule: evenodd`). Słupki to zaokrąglone
prostokąty o stałej szerokości. Tło to superelipsa n=5 w polu 824 pt (w środku kanwy 1024),
przybliżenie squircle'a macOS.

## Zestawy kolorów do wyboru

| # | Tło | Pióro | Słupki | Uwagi |
|---|---|---|---|---|
| 1 | granat `#0F1A33` | złoto `#F2BD55` | turkus `#2EC4B6` | dokładnie kolory z obrazu użytkownika |
| 2 | ciepły tusz `#22211E` | złoto `#F2BD55` | mięta `#7CC39C` | paleta B (§11.1); **rekomendacja sesji** |
| 3 | ciepły tusz `#22211E` | złoto `#F2BD55` | turkus `#2EC4B6` | tylko tło ciepłe |
| 4 | zieleń akcentu `#2F6B4F` | złoto `#F2BD55` | krem `#F7F6F2` | najmocniej odcina się w Docku |

Złoto `#F2BD55` jest bliskie ciemnemu `warn` z §11.1 (`#E0B050`), więc w ikonie nie wprowadza
obcego koloru, ale **nie mierzono jeszcze kontrastu** ikony w Docku jasnym i ciemnym.

## Ikona w paczce (2026-10-19)

Zestaw 3 jest ikoną tymczasową. Zmiana koloru to: edycja tablicy `V` w `zloz-ikone.py`
(albo wybór innego `wN.svg`), potem `docs/design/marka/zrob-icns.sh wN.svg`.

- `docs/design/marka/zrob-icns.sh`: SVG → Chrome headless (PNG 1024 z alfą) → `sips` (16…512 i @2x)
  → `iconutil` → `Resources/AppIcon.icns`. Działa na samych Command Line Tools **plus Google Chrome**
  (do rasteryzacji SVG; `rsvg-convert`, ImageMagick i Inkscape nie ma). `.icns` jest w repo, więc
  budowa paczki Chrome nie wymaga.
- `Resources/Info.plist`: `CFBundleIconFile` = `AppIcon`. `scripts/bundle.sh`: kopiuje
  `Resources/AppIcon.icns` do `Contents/Resources/`. `scripts/check-bundle.sh` przechodzi.
- **Sprawdzone:** `NSWorkspace.icon(forFile:)` na zbudowanej paczce zwraca naszą ikonę w squircle'u
  z cieniem systemu, **bez szarego tła** (tło 824 pt w kanwie 1024 mieści się w masce).
- **Nie sprawdzone na żywo w Docku:** w chwili zmiany działała instancja użytkownika (PID 11254),
  której nie ruszano. Ikona pojawi się po przebudowie `scripts/run.sh` (LaunchServices może
  trzymać starą w pamięci podręcznej; pomaga `touch .build/MeetNotes.app` albo `killall Dock`).
- **Ograniczenie CLT (bez Icon Composera):** to zwykłe `.icns`, a więc **jedna płaska warstwa**:
  brak warstw pod Liquid Glass, brak wariantów ciemnego, Clear i Tinted. System może je
  przetworzyć automatycznie (np. Tinted), ale jakości tego nie mierzono. Warstwowy format
  `.icon` wymaga Icon Composera z Xcode. Zbadać, czy da się go złożyć ręcznie (to JSON plus SVG-i),
  bo wtedy Xcode niepotrzebny; **niesprawdzone**.
- **Wersja na małe rozmiary (2026-10-19):** `mN.svg`, rozmiary do 64 px w `.icns` (16, 32, 32@2x=64).
  Pióro bez szpary i większe (skala 2,25 zamiast 2,0), sześć grubszych słupków zamiast dziesięciu.
  Na podglądzie 1:1 przy 32 i 64 px wyraźnie czytelniejsza niż duża; przy 16 px to wciąż
  rozpoznawalny kształt (pióro i dwie fale), ale bez detalu. Rozmiary od 128 px: wersja pełna.

## Logotyp (zaakceptowany przez użytkownika 2026-10-19)

Znak (squircle z piórem i falami) plus nazwa **Yascribe** w New York Regular (§11.2, jak tytuły
stron), kerning −2 przy rozmiarze 200. Dwa układy, każdy w wersji na jasne (`#F7F6F2`, tekst
`#22211E`) i ciemne tło (`#1C1C1B`, tekst `#ECEBE6`): **poziomy** (znak i nazwa obok siebie) oraz
**pionowy** z mottem *What's it like to be a scribe?* kursywą New York w `text2`.
Podgląd: `marka/podglad-logo.png`. Pliki: `marka/logo-poziome-{jasne,ciemne}.svg`,
`marka/logo-pionowe-{jasne,ciemne}.svg`.

- Litery są **konturami**, nie tekstem: `marka/napis-na-krzywe.swift` (CoreText) → `marka/logotyp-krzywe.json`
  → `marka/zloz-logo.py`. SVG nie zależy więc od fontu w systemie.
- **Dwa niezałatwione punkty.** (1) Licencja: New York to krój systemowy Apple; **nie sprawdzono**,
  czy jego kontury wolno stosować jako logo (aplikacja jest prywatna, dla jednego użytkownika, ale
  przed jakimkolwiek publicznym użyciem trzeba to rozstrzygnąć albo wziąć inny krój). (2) Na ciemnym
  tle squircle ikony (`#22211E`) ledwo odcina się od tła `#1C1C1B` (trzyma go tylko cienka obwódka);
  jeśli to przeszkadza, tło logotypu na ciemno może być głębsze (np. `#121211`).
- Duże Y wynika z samego kroju (kapitalik przy małych literach); osobnego wyróżnienia koloru
  Y nie robiono. Wariant ze złotym Y (jak pióro) jest możliwy, ale na jasnym tle złoto
  `#F2BD55` ma kontrast ok. 1,6:1, więc wymagałby ciemniejszego odcienia.

## Do zrobienia

1. **Wybór zestawu kolorów** (użytkownik; na razie 3).
2. ~~Ikona na małe rozmiary~~ zrobione 2026-10-19 (zob. „Ikona w paczce”).
3. **macOS 27:** warstwy pod Liquid Glass (tło, pióro, fale jako osobne warstwy), wariant ciemny,
   Clear, Tinted (ograniczenia CLT w sekcji „Ikona w paczce”). Zakaz SF Symbols w ikonie i logo
   (macos.md §7).
4. ~~Logotyp~~ zaakceptowany 2026-10-19 (sekcja „Logotyp”). Otwarte tylko: licencja kroju.
5. ~~Podpięcie ikony do paczki~~ zrobione 2026-10-19 (zob. wyżej).

## Odrzucone kierunki (historia)

Osiem kierunków z literą Y w znaku (trzy kreski jak [firma], dwa kanały zlewające się w Y, pióro
kaligraficzne, stalówka z wyciętym Y, pióro-Y, fala-Y, fala+pióro=Y) obejrzał użytkownik w
rozmowie 2026-10-16 i 2026-10-19 i żaden mu się nie spodobał. Rysunki nie są w repo; zostały
tylko opisy w tym akapicie. Wniosek: użytkownik wolał rozpoznawalny, ilustracyjny znak (pióro i
fala) od abstrakcyjnego monogramu.
