# Marka: nazwa, logo, ikona

> Status: **w toku, 2026-10-19**. Zapadły: nazwa, motto, kompozycja znaku. **Tymczasowo zestaw 3**
> (użytkownik: „na razie v3”, kolory można zmienić później; konsultuje z żoną). Ikona **jest
> podpięta do paczki** (zgoda użytkownika 2026-10-19). Czeka: ikona na małe rozmiary, warstwy pod
> macOS 27, logotyp.
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
- Wersja na 16 i 32 pt jest ta sama co duża (słupki zlewają się). Uproszczona wersja jest
  w „Do zrobienia”.

## Do zrobienia

1. **Wybór zestawu kolorów** (użytkownik; na razie 3).
2. **Ikona na małe rozmiary (16, 32 pt):** mniej słupków, grubsze, bez nacięć pióra. Pomiar
   czytelności na podglądzie 1:1.
3. **macOS 27:** warstwy pod Liquid Glass (tło, pióro, fale jako osobne warstwy), wariant ciemny,
   Clear, Tinted (ograniczenia CLT w sekcji „Ikona w paczce”). Zakaz SF Symbols w ikonie i logo
   (macos.md §7).
4. **Logotyp:** „Yascribe” w New York (§11.2), duże Y, ułożenie znaku i nazwy, wersja na jasne
   i ciemne tło.
5. ~~Podpięcie ikony do paczki~~ zrobione 2026-10-19 (zob. wyżej).

## Odrzucone kierunki (historia)

Osiem kierunków z literą Y w znaku (trzy kreski jak [firma], dwa kanały zlewające się w Y, pióro
kaligraficzne, stalówka z wyciętym Y, pióro-Y, fala-Y, fala+pióro=Y) obejrzał użytkownik w
rozmowie 2026-10-16 i 2026-10-19 i żaden mu się nie spodobał. Rysunki nie są w repo; zostały
tylko opisy w tym akapicie. Wniosek: użytkownik wolał rozpoznawalny, ilustracyjny znak (pióro i
fala) od abstrakcyjnego monogramu.
