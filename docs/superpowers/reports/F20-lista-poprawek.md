# F20 — lista poprawek zgłoszonych przez użytkownika

Błędy i zmiany zgłoszone przez użytkownika na gałęzi `faza20` po odbiorach T8/T14 (stan kodu: `f9c1867`, 561/561).
Pozycje dopisywane w kolejności zgłoszenia; decyzje są użytkownika, zapis niżej to ustalenia z rozmowy 2026-10-20.
**Stan (2026-10-20, wieczór):** P1, P3 i P4 zrobione na gałęzi `faza20-poprawki` (odgałęzienie od `f9c1867`, cztery commity, **571/571**,
bez scalenia i bez pushu). P2 i P5 celowo bez kodu: czekają na decyzję (P2) i pomiar na działającej aplikacji (P5).
Aplikacja uruchomiona u użytkownika to **stary build** — poprawki zobaczy po `scripts/bundle.sh` albo `scripts/run.sh` (nie podmieniałem `~/Applications/MeetNotes.app`).

## P1 — „Correction failed: the model didn't answer within 120 s" (API, OpenRouter)

**Stan: zrobione w `853fbf8`** (przyczyna ustalona wcześniej, poniżej).

**Co zmieniono.** `OpenAICompatibleClient.chat(thinking:)`: dla API wysyła `reasoning: {"enabled": false}`, z jednym ponowieniem bez pola po 400/422
wspominającym „reasoning" albo „think" (ścieżka lokalna bez zmian: `reasoning_effort: "none"`). Korekta zawsze `thinking: false`; sonda korekty też
(inaczej „Test" wisiałby na modelu, który w korekcie działa); sonda podsumowania i **tytuł bez zmian** (tytuł niepotwierdzony — ryzyko to samo, jeśli kiedyś się zawiesi).
Podsumowanie: `GlobalSettings.summaryThinking` (opcjonalne, E6; `nil` = myślenie włączone, jak dotąd), przełącznik w Settings → Summary → Thinking, zapis od razu,
działa tylko dla API (lokalne zawsze bez myślenia; napisane w podpisie przełącznika).

**Zweryfikowane.** 6 nowych testów (treść żądania dla API/lokalnego, ponowienie, korektor, sonda, generator, zgodność starego `settings.json`); mutacja
(usunięcie linii dodającej pole `reasoning`) wywróciła 5 testów, plik przywrócony.
**Niezweryfikowane.** Żywe wywołanie OpenRoutera po zmianie w kodzie (jedyna próba na żywo to `curl` z tą samą treścią, jedna próbka); wygląd przełącznika
w Settings (migawki nie sięgają tak nisko — kod się buduje); działanie na prawdziwym modelu notatki z wyłączonym myśleniem.

**Dlaczego domyślnie „myślenie włączone" dla podsumowania:** zachowuje obecne zachowanie, a użytkownik chciał to najpierw przetestować. Jedna obserwacja: w tej samej
sesji istnieje `notes/summary.json`, czyli notatka z myśleniem zmieściła się w limicie 180 s. To jeden punkt danych, nie wniosek.

**Objaw.** Ostatnia sesja (`2026-10-20T12-10-37Z-5852`, 4 wypowiedzi, 4143 znaki, preset „Polski",
`deepseek/deepseek-v4.1-flash` przez OpenRouter) kończy korektę błędem z `Deadline.swift:7`. Retry daje to samo.
Hipoteza „trzeba dzielić na fragmenty" nie trafia: korekta już dzieli (API: do 6000 znaków na partię,
`Corrector.swift:47`), a ta sesja to jedna partia.

**Dowód (odtworzenie poza aplikacją, `curl`, to samo wywołanie na danych z sesji, jedna próbka na wariant).**

| Wariant | Wynik |
|---|---|
| A — jak w aplikacji (bez pól o rozumowaniu) | przez 200 s tylko puste linie keep-alive od OpenRoutera, brak odpowiedzi |
| B — z `reasoning: {"enabled": false}` | pełna odpowiedź po ok. 33 s, dostawca DeepInfra, `finish: stop`, 1464 tokeny wyjścia, `reasoning_tokens: 0` |

**Przyczyna (najlepsze wyjaśnienie, nie dowód).** Model domyślnie „myśli", a dla API `chat` nie wysyła nic o rozumowaniu
(`reasoning_effort: "none"` idzie tylko do dostawców lokalnych, `OpenAICompatibleClient.swift:150`). Keep-alive odświeża
`timeoutInterval`, więc zadziała dopiero limit `withDeadline` (120 s). Tokenów rozumowania w wariancie A nie widziano,
bo odpowiedź nigdy nie nadeszła; mógł się nałożyć wolny dostawca. `withDeadline` działa (błąd się pojawia), hipoteza o zawieszeniu odpadła.

**Ustalenia użytkownika.**
1. **Korekta: myślenie wyłączone dla każdego modelu** — do poprawy tekstu niepotrzebne. API: `reasoning: {"enabled": false}`
   w treści żądania; lokalnie już jest `reasoning_effort: "none"`. Test z atrapą HTTP sprawdza treść żądania.
2. **Podsumowanie (notatka, części mapy): przełącznik trybu myślenia w ustawieniach.** Wpływ na jakość notatki
   trzeba przetestować, zanim wybierzemy domyślną wartość. Notatka ma ten sam model w presecie i limit 180 s, więc ryzykuje to samo.
3. Tytuł: bez myślenia — propozycja asystenta, niepotwierdzona.

**Przy implementacji.** Nowe pola w zapisywanych typach (ustawienie, preset) tylko opcjonalne (lekcja E6).
Do wyboru: przełącznik globalny czy per preset.

## P2 — Przerywniki i wtrącenia w transkrypcie (yy, mhm, pauzy)

**Stan: kierunek ustalony, szczegóły otwarte.**

**Obserwacja.** Odpowiedź modelu w próbie B zostawiła „yy" w tekście; korekta modelem tego nie gwarantuje.
Wzorzec z FluidVoice (`ASRService.removeFillerWords`, przeczytana tylko ścieżka dyktowania, nie spotkań): deterministyczny filtr
słów z listy (um, uh, er, ah, hmm, mm…), bez modelu, natychmiast. Lista FluidVoice jest tylko angielska; pauz nie usuwa (Parakeet ich nie zwraca).

**Ustalenia użytkownika.**
1. Filtry mają być **własne użytkownika: w ustawieniach i w poleceniach dla modelu** (pole „Extra instructions" korekty już istnieje).
2. Dodatkowo można mieć filtr **w backendzie** (deterministyczny, jak w FluidVoice).
3. Otwarte: czy lista jest edytowalna w Settings, jaka jest domyślna lista polska (yyy, eee, mhm…) i czy filtr backendowy jest domyślnie włączony.

**Stan: zrobione w `517a197` (opcje A i B, decyzja użytkownika 2026-10-20: „rób A i B z domyślną polską listą").**

**Co zrobiono.** Jedno ustawienie steruje obiema częściami: Settings → Correction → Filler sounds (przełącznik, domyślnie włączony) i pole Words (lista po przecinku, Return zapisuje, Reset wraca do domyślnej).
**A:** lista (pierwsze 8 słów) trafia do polecenia systemowego korektora („Exception: remove filler sounds and hesitations…"). **B:** `FillerWords.remove` po odpowiedzi modelu, także dla linii z nieudanych
partii; całkowita porażka korekty bez zmian. Interpunkcja i wielka litera po usuniętym początku zdania zachowane; rozciągnięte „yyyyy" pasują, pojedyncze „m" nie; wypowiedź złożona wyłącznie z przerywników zostaje (bez pustych).
Lista domyślna: `yyy, eee, ehm, yhm, mhm, mmm, hmm, ym, um, uh, er, erm, uhm` (bez słów z znaczeniem: no, tak, wiesz, znaczy). Filtr działa na tekście poprawionym; surowy transkrypt i `words` nietknięte.
**Zweryfikowane.** 9 testów (filtr, interpunkcja, brzegi, korektor A i B, zgodność starego `settings.json`, prawdziwe zdanie z próby P1), trzy mutacje wywróciły testy, pliki przywrócone.
**Niezweryfikowane.** Wygląd sekcji Correction w Settings (migawki nie sięgają tak nisko), prawdziwa korekta z modelem po zmianie. Filtr nie dotyczy korekt zrobionych wcześniej (są zapisane w `corrected.json`): „Retry" je przeliczy.
**Poza zakresem (świadomie).** Pauzy; edycja listy per preset; czyszczenie surowego transkryptu (opcja C odradzana).

Opcje przedstawione użytkownikowi (dla historii), od najmniejszej:
- **A. Tylko polecenia dla modelu.** Gotowy tekst do pola „Extra instructions" korekty (np. „Remove filler sounds such as yyy, eee, mhm; do not remove words that carry meaning"). Zero kodu,
  ale model bywa niekonsekwentny (próba B zostawiła „yy"), a pole jest per preset.
- **B. Filtr deterministyczny na wyniku korekty** (po modelu, przed zapisem `corrected.json`). Korekta i tak podmienia tylko `text` (czas i mówca z oryginału), więc czasy słów nie cierpią.
  Surowy transkrypt zostaje nietknięty, filtr działa tylko na tekście poprawionym. Lista w Settings (edytowalna, domyślnie polska + angielska), przełącznik. Brak korekty = brak filtra.
- **C. Filtr na tekście ASR** (jak FluidVoice, przed zapisem `transcript.json`). Działa także bez korekty, ale zmienia `Utterance.text` bez zmiany `words`, a czasy słów dalej wskazują usunięte
  słowa; zmiana ścieżki, którą czytają wyszukiwanie i podsumowanie. Odradzam bez decyzji o `words`.
Rekomendacja: A od razu (zero ryzyka), B po decyzji o liście domyślnej i miejscu w Settings.

## P3 — Settings: Parakeet to model Yascribe, nie dostawca

**Stan: zrobione w `c53eb15`.** Pierwotny zakres: `Sources/MeetNotesApp/SettingsView.swift`, `ModelCardView.swift`, `ProviderLogos.swift`,
`Sources/MeetNotesProviders/ProviderSetup.swift`.

**Ustalenia użytkownika.**
1. Z listy **Providers** znika wiersz „On this Mac · Parakeet" — to nie jest dostawca.
2. Sekcja „On-device speech model" (karta modelu: pobieranie, usuwanie) **przechodzi na górę Settings**, nad Providers,
   i nazywa się **„Yascribe model"**.
3. Karta dostaje **czarno-białą ikonę Yascribe** (znak: pióro między dwiema falami), w tym samym kafelku co logo OpenRouter, ElevenLabs i Ollamy.
4. Dodać ikony **llama.cpp** i **oMLX** (dziś zastępcze symbole SF: `terminal`, `memorychip`).
5. **Archive search → Embedding model:** użytkownik widzi tylko OpenRouter, a ma być dostępny każdy skonfigurowany dostawca.

**Co zrobiono.** Karta „Yascribe model" nad Providers, ikona Yascribe (jednobarwna, template); wiersz Parakeeta usunięty z Providers (także przycisk „Enable"); rekord `.fluidAudio` zostaje
i jest dopisywany przy starcie, gdy go brak (`ProvidersFile.ensureOnDeviceProvider`, po rodzaju API, idempotentnie; zapis tylko `providers.json`); ikony llama.cpp i oMLX (jednobarwne),
źródła i odstępstwo w `ZRODLA.md`; trzy testy przepisane na nowe zachowanie i jeden nowy.
**Zweryfikowane.** `scripts/snapshot.sh` (jasny i ciemny): kolejność sekcji, ikony w kafelkach, brak Parakeeta na liście; SVG przez `NSImage` (ten sam mechanizm co aplikacja);
mutacja (zdjęcie filtra `.fluidAudio` z wierszy) wywróciła test, plik przywrócony.
**Niezweryfikowane.** Uruchomienie w prawdziwej aplikacji (klik w kartę, „Download", stan po restarcie z istniejącym `providers.json`).

**Ustalone przy czytaniu kodu (zostawione dla pamięci).**
- Dostawca `.fluidAudio` musi nadal istnieć jako rekord (presety trzymają jego `providerID`), tylko ukryty na liście. Dziś tworzy go
  przycisk „Enable" w wierszu, który znika (`SettingsView.swift:283`); bez tego nic go nie utworzy. Propozycja asystenta, niezatwierdzona:
  `AppModel.load()` dopisuje go, gdy go brak. Wiersz `ProviderListRow.rows` musi go też odfiltrować (inaczej wpadnie do „własnych").
- **Embedding prawdopodobnie nie jest błędem kodu:** `EmbeddingChoice.providers` (`ProviderSetup.swift:124`) już zwraca każdego skonfigurowanego
  dostawcę OpenAI-compatible (OpenRouter, Ollama, llama.cpp, oMLX, własne). W `.devdata/providers.json` są tylko OpenRouter i Parakeet,
  więc widać jeden. ElevenLabs nie ma embeddingów i słusznie odpada. **Do zweryfikowania z użytkownikiem**, czy chodzi o coś więcej
  (np. nowy dostawca nie pojawia się po konfiguracji, albo komunikat pustej listy `SettingsView.swift:113`).
- Ikony: nie ma ich w repo. Źródła sprawdzone 2026-10-20: llama.cpp `media/llama1-icon.svg` (repo `ggml-org/llama.cpp`, MIT),
  oMLX `menubar-filled.svg` (repo `jundot/omlx`, Apache-2.0), znak Yascribe z `docs/design/marka/ksztalty.json` (geometria jak w `zloz-ikone.py`).
  Wersje czarno-białe (template) już wygenerowane i leżą w `docs/design/makiety/logo-dostawcow/`: `yascribe-mark-mono.svg`, `llamacpp-mono.svg`,
  `omlx-mono.svg` (nieśledzone w git, nie wpisane do `ZRODLA.md`, niepodpięte w kodzie). Znaki towarowe właścicieli — jak przy pozostałych logo.

## P4 — Edytor presetu: dostawcy w rolach

**Stan: zrobione w `4a20caf` i `9e14f0f`.** `Sources/MeetNotesApp/PresetsView.swift` (`RoleSection`, `providers` na linii 275 to dziś **wszyscy** dostawcy w każdej roli).

**Ustalenia użytkownika.**
1. Rola **Speech to text → Provider:** zamiast „On this Mac · Parakeet" pokazać **„Yascribe"**. Model zostaje ten sam (jest jeden: `parakeet-tdt-0.6b-v3`).
2. Role **Correction** i **Summary:** usunąć „On this Mac · Parakeet" — ten model nie służy do notatek.
3. W obu sekcjach wybieramy **tylko dostawców, którzy obsługują poprawę i podsumowanie transkrypcji** (czat tekstowy).

**Co zrobiono.** `Provider.supports(_:)` + `RoleProviders.choices`: Correction i Summary oferują tylko dostawców OpenAI-compatible (znika Yascribe/Parakeet **i ElevenLabs**);
ASR bez filtra. „Yascribe" to **etykieta** (`Provider.roleLabel`) w menu Provider i w polu Model; rekord w `providers.json` i jego nazwa bez zmian (brak migracji).
Preset, który już wskazuje nieobsługującego dostawcę, zachowuje go w menu jako bieżący wybór (żeby nie pokazać „None" przy istniejącym przypisaniu; niczego nie kasujemy).
**Zweryfikowane.** 3 nowe testy, mutacja (zdjęcie reguły roli) wywróciła je, plik przywrócony; migawka edytora presetu: „Yascribe" w polu Provider i w polu Model.
**Niezweryfikowane.** Wygląd menu Provider w rolach Correction i Summary (migawki nie pokazują rozwiniętego menu).

**Wnioski z kodu (nie ustalenia użytkownika).**
- Z reguły 3 wynika też wykluczenie ElevenLabs (tylko transkrypcja, `ProviderPreset.elevenLabs`); użytkownik wymienił wprost tylko Parakeeta.
  Do potwierdzenia, że ElevenLabs też ma zniknąć z tych dwóch ról.
- Nazwa „Yascribe" to nazwa wyświetlana. Rekord dostawcy w `providers.json` nazywa się „On this Mac · Parakeet" (test `ProviderSetupTests` sprawdza tę nazwę),
  więc zmiana nazwy dotyka rekordów już zapisanych u użytkownika. Do decyzji: zmienić etykietę tylko w widoku czy też nazwę rekordu.
- Istniejące presety, które mają Parakeeta w korekcie albo podsumowaniu (preset „Parakeet PL" w `.devdata` ma tam OpenRouter, więc bez konfliktu),
  wymagają ścieżki migracji albo komunikatu — do ustalenia przy implementacji.

## P5 — Meetings → wybór spotkania zmienia szerokość bocznego paska

**Stan: zamknięte 2026-10-20 — nie odtworzono, użytkownik sprawdził i „jest ok" (bez poprawki w kodzie).** Zgłoszenie użytkownika: po wejściu w Meetings i wybraniu spotkania zmienia się szerokość sidebaru.

**Pomiar 2026-10-20 (wieczór): NIE odtworzono.** Druga instancja (surowy plik binarny `MeetNotesApp` na tymczasowych danych z jednym spotkaniem, wykrywanie rozmów, auto-start i kalendarz wyłączone;
tymczasowa instrumentacja, cofnięta, nigdzie niezacommitowana). Przejście: lista Meetings → otwarte spotkanie → lista → spotkanie → zakładka Presets, przez zmianę stanu modelu (nie prawdziwe kliknięcia).
Mierzone: ramki kolumn `NSSplitView`, pozycje elementów paska narzędzi i widoków wizualnych, zrzuty okna renderowane przez samą aplikację. Okna: 900, 1300 i **1235×833 z zapisanym u użytkownika paskiem 160**.
Wynik we wszystkich stanach: sidebar `0..160`, granica `160–161`, detal `161..koniec`, bez żadnej zmiany; pasek narzędzi dostaje przy otwartym spotkaniu dwa elementy (przycisk „Meetings" x166–202 i menu „⋯" x210–230), a separator i elementy wizualne bez zmian;
zrzuty (lista vs spotkanie) mają granicę paska w tym samym miejscu. **Wniosek: w tym układzie to nie jest zmiana szerokości kolumny.** Hipoteza z toolbaru (`ToolbarItem(.navigation)` przesuwa kolumny) nie potwierdzona.
**Czego nie wiadomo.** Czy u użytkownika zmienia się granica kolumny, czy coś, co wygląda jak zmiana paska (np. wygląd paska narzędzi, tło, zaznaczenie wiersza); różnice między prawdziwym kliknięciem a zmianą stanu; wpływ budu `.app` (pomiar na surowym pliku binarnym) i dłuższej zawartości spotkania.
**Ślad po pomiarze (posprzątany):** surowy plik binarny utworzył `~/Library/Preferences/MeetNotesApp.plist`; usunięty, preferencje prawdziwej aplikacji (`io.github.sharezz1.meetnotes`) nietknięte.
**Drugi pomiar (ta sama noc, na prośbę użytkownika): prawdziwa aplikacja** (`scripts/run.sh`: paczka `.build/MeetNotes.app` na `.devdata`, okno 1235×833, prawdziwe spotkania), zrzuty okna `screencapture -l` i prawdziwe kliknięcie w wiersz spotkania.
Lista Meetings i otwarte spotkanie (okno aktywne): granica paska identyczna (160 pt, x≈260 na zrzucie 2000 px), przycisk „Meetings" i „⋯" tuż za granicą. **Szerokość paska się nie zmienia.**
Jedyna widoczna różnica: odcień tła paska (na liście jaśniejszy, przy otwartym spotkaniu ciemniejszy). Prawdopodobnie przezroczystość (vibrancy) zależna od tego, co jest pod oknem; nie sprawdzono, czy to to, co widzi użytkownik.
**Następny krok:** użytkownik ocenia zrzuty (lista i otwarte spotkanie) i mówi, co się różni; bez tego żadnej poprawki.

**Fakty z kodu (nie diagnoza).**
- Układ: `NavigationSplitView` w `ContentView` (`MeetNotesApp.swift:75`), sidebar ma `.navigationSplitViewColumnWidth(min: 160, ideal: 180)` bez `max`.
- Detal Meetings to `NavigationStack`, który po wyborze **wypycha** `MeetingDetailView` przez `.navigationDestination(item:)` (`MeetingsView.swift:40, 69`). Widok spotkania zmienia pasek okna:
  `.navigationBarBackButtonHidden(true)`, własny `ToolbarItem(placement: .navigation)` z przyciskiem „Meetings" i menu „⋯" (`MeetingDetailView.swift:54, 65`).
  Lista Meetings tego nie ma. Okno ma `.toolbar(removing: .title)` i ukryte tło paska (`MeetNotesApp.swift:92`).
- Treść obu stron to `ScrollPage` z kolumną 600 / 640 i stałą szerokością (`DesignSystem.swift:89`), okno ma `minWidth: 820` (`MeetNotesApp.swift:26`).

**Hipotezy (niesprawdzone).**
1. Dodanie elementu `.navigation` do paska okna na macOS przesuwa lub przelicza kolumny `NavigationSplitView`.
2. Brak `max` w `navigationSplitViewColumnWidth` pozwala systemowi zmienić szerokość przy przeliczeniu układu.

**Do ustalenia przy naprawie.** Powtórzyć na `.app` i zmierzyć szerokość sidebaru przed i po wyborze spotkania (zrzut ekranu z linijką albo `AXUIElement`),
sprawdzić, czy to samo dzieje się przy samych przyciskach paska (bez wypychania widoku), i dopiero wtedy wybierać poprawkę. Nie zgadywać.

## Pytania po spacerze

1. **ElevenLabs** też zniknął z Correction i Summary (reguła „tylko dostawcy z czatem"). Zgoda?
2. **Podsumowanie z myśleniem czy bez?** Domyślnie włączone (jak było). Przełącznik w Settings → Summary → Thinking. Test: ta sama notatka z włączonym i wyłączonym, porównać jakość i czas.
3. **Rekord Yascribe wraca przy starcie**, jeśli ktoś go kiedyś usunął; dostaje nowy UUID, więc presety, które wskazywały usunięty rekord, nadal wskazują nieistniejący. Czy potrzebna naprawa takich presetów?
4. **Ikona llama.cpp jednobarwna** zamiast barwnej od właściciela (odstępstwo od `ZRODLA.md`, opisane tam). Zostawić?
5. **Embedding (P3):** w `.devdata` skonfigurowany jest tylko OpenRouter, stąd jeden dostawca. Czy po skonfigurowaniu Ollamy/llama.cpp/oMLX/własnego pojawiają się u Ciebie w „Archive search"? Jeśli nie — to nowy błąd.
6. **P2:** którą opcję (A/B/C) i jaka lista domyślna?
7. **P5:** pasek się zwęża czy poszerza i czy wraca po „Meetings"? Pomiar zrobię na żywej aplikacji, gdy pozwolisz.
8. **Scalanie:** gałąź `faza20-poprawki` leży obok `faza20`, nic nie scalałem ani nie pushowałem.

## Odpowiedzi użytkownika (2026-10-20, wieczór)

1. **ElevenLabs znika z Correction i Summary** — potwierdzone.
2. **Podsumowanie: przełącznik on/off, porównamy różnicę** — to jest już w kodzie (Settings → Summary → Thinking, `853fbf8`); test jakości jeszcze przed nami.
3. **Rekord Yascribe wraca przy starcie** — „jest ok".
4. **Ikona llama.cpp jednobarwna** — potwierdzone, zostaje.
5. **Embedding (P3):** „nie pojawiają się". Stan `.devdata/providers.json` (zmieniony ostatnio 14:09) to tylko OpenRouter i rekord Yascribe, więc nie ma jeszcze nikogo innego do pokazania.
   Kod (`EmbeddingChoice.providers`) pokazuje każdego skonfigurowanego dostawcę OpenAI-compatible. **Do wyjaśnienia z użytkownikiem**, czy dostawcy zostali skonfigurowani i nie widać ich w menu (wtedy to błąd), czy oczekiwana jest lista także nieskonfigurowanych,
   albo wiersz „Provider" widoczny zawsze (dziś ukryty przy jednym dostawcy: `EmbeddingChoice.showsProviderRow`).
6. **P2:** użytkownik nie zrozumiał opcji A/B/C — do wyjaśnienia prostszym językiem.
7. **P5 zawężone:** inny rozmiar paska ma **tylko widok otwartego spotkania**; po kliknięciu innej zakładki pasek wraca do normalnego. Nie podano, czy się zwęża, czy poszerza.
   To wspiera hipotezę, że winny jest widok spotkania (pasek okna z własnym przyciskiem „Meetings" w `ToolbarItem(placement: .navigation)` albo szerokość treści), a nie sam `NavigationSplitView`.

## Wyniki testów na żywo (2026-10-21, wieczór)

Aplikacja zbudowana z `master` (`fc180da`) przez `scripts/run.sh`, dane z `.devdata/`. Treści spotkań nie cytuję; sesja `2026-10-21T07-29-08Z-62de`.

### Podsumowanie z myśleniem i bez (P1)
Ta sama sesja (135 wypowiedzi, 20 097 znaków po korekcie), ten sam model `deepseek/deepseek-v4.1-flash` przez OpenRouter, ten sam szablon `standard`; zmienia się tylko Settings → Summary → Thinking.
Jedna próba na wariant, więc **wynik nie rozstrzyga** (model jest niedeterministyczny).

| | Myślenie włączone (21:04) | Myślenie wyłączone (22:04) |
|---|---|---|
| Długość | 6711 znaków | 5617 znaków |
| Czas | nie mierzony | „wyjątkowo szybko" (użytkownik), nie mierzony |
| Rozmówca przypisany do zespołu na podstawie pytania retorycznego, choć padło sprostowanie | błąd | poprawnie |
| Kroki niewynikające z rozmowy (YouTube, „kontynuować IVR-y") | 2 | 0 (zostały 3 wywnioskowane: zakres AI, obrona kwoty, roadmapa) |
| Sprzeczne liczby (2,5 mln rocznie kontra 150 tys.) | oznaczone jako niejasne | zlane przez „czyli" (fałszywa precyzja) |
| Uwaga, że zapis jest chaotyczny | jest | brak |
| Nagłówki | polskie | angielskie przy preset „Polski" (nie wiadomo, czy to efekt myślenia) |
| Dopisek bez pokrycia w rozmowie | brak | jeden (o płatności miesięcznej) |
| Udział rozmowy luźnej (naklejki) | ok. 1/3 | ok. 1/3 |

Wnioski: (1) korekta zostaje na stałe bez myślenia; (2) dla podsumowania wyłączone myślenie nie wypadło gorzej na zgłoszonych błędach, ale wprowadziło dwa nowe; (3) domyślne ustawienie (włączone) **bez zmian**, decyzja użytkownika 2026-10-21; (4) żeby rozstrzygnąć, trzeba 2–3 próby na wariant.
Przy okazji: plik `summary-<czas>.json` zachowuje poprzednią wersję, więc obie są do porównania w `notes/`.

### Korekta tej sesji (stary build)
`corrected.json` z 09:46: 3 partie, **1 nieudana** („The model didn't answer within 120 s"), 1 odrzucona linia. Zrobiona starą aplikacją, **przed P1**, więc nie testuje poprawki. Nowy build ma P1 od 21:00; korektę tej sesji da się powtórzyć przyciskiem Retry.

### Inne
- **Embedding (P3):** użytkownik potwierdził, że menu pokazuje dostawców i wyszukiwanie działa (`embeddinggemma-2:270m` przez Ollamę). Pytanie 5 z listy zamknięte.
- **Zapis w Settings (P6, nowe):** po przełączeniu Thinking nie było widać zapisu (Save/Cancel wyszarzone, bo obsługują tylko Archive search). Ustawienie zapisywało się (`settings.json`: `summaryThinking: false`). Poprawka: stopka pokazuje „Saved" (PR #4).

### Trzecia próba (2026-10-21, 22:46): szablon `weekly-team`, myślenie wyłączone
Ten sam model i sesja, ale **inny szablon** (`weekly-team`: Summary, Progress, Blockers and risks, Decisions, Next steps), więc próba nie jest czysta. Notatka ma 4907 znaków.
- Błąd z zespołem Pawła Szota (zespół przypisany do voicebota mimo sprostowania w rozmowie) **wrócił**, mimo wyłączonego myślenia.
- Krok „zdecydować o publikacji audiobooków na YouTube" **wrócił**.
- Liczby (2,5 mln rocznie, 150–200 tys. „w piku") znów zestawione bez zastrzeżenia, że w rozmowie były niespójne.
- Sekcja Decisions zawiera „decyzje", których w rozmowie nie podjęto (przerobienie dokumentu na Confluence'a, dołożenie AI do subskrypcji); sekcja Blockers zawiera ryzyko, którego nikt nie wypowiedział („klient jej nie przyjmie"). Wygląda to na skutek szablonu, który wymaga wypełnienia tych sekcji.

Zestawienie trzech prób (błąd Szota / krok YouTube / zlane liczby): myślenie włączone — tak / tak / nie; wyłączone, `standard` — nie / nie / tak; wyłączone, `weekly-team` — tak / tak / tak. Błędy pojawiają się i znikają niezależnie od myślenia, więc **nie ma dowodu, że myślenie je poprawia lub psuje**. Trzy próby to nadal za mało na wniosek; decyzja o domyślnym ustawieniu pozostaje przy użytkowniku (bez zmiany: włączone).

### P1 potwierdzone na żywo (2026-10-21, 23:11)
Sesja `2026-10-21T07-29-08Z-62de`, 135 wypowiedzi, 3 partie, ten sam model `deepseek/deepseek-v4.1-flash` przez OpenRouter. Przed P1 (09:53, stary build): `failedBatches: 1`, „The model didn't answer within 120 s".
Po P1 (nowy build, „Improve transcript" po PR #6): **`failedBatches: 0`**, 3 odrzucone linie (`rejectedLines: 3`, zostają jak usłyszane). Zmieniło się 31 wypowiedzi, tekst skrócił się z 20 052 do 19 835 znaków.
Filtr przerywników (P2): przerywniki w liniach poddanych korekcie — 74 → 8 (zliczenie przybliżone); wszystkie 8 to wypowiedzi złożone wyłącznie z „Mhm."/„yy", które zostają z założenia. W 32 wypowiedziach pominiętych (echo toru, flaga języka) przerywniki zostają (19), bo nie idą do korekty.
Czas trwania korekty nie zmierzony (przycisk kliknięty przed rozpoczęciem monitora).

### P4 potwierdzone przez użytkownika (2026-10-21)
Menu Provider w presetach (Correction, Summary) nie oferuje ElevenLabs ani Yascribe; użytkownik sprawdził w aplikacji: „działa dobrze".

### Testy użytkownika (2026-10-22): lokalna transkrypcja i poprawki P8–P10
- **Lokalna transkrypcja po ponownym pobraniu modelu — zaliczona.** Sesja `2026-10-21T22-26-49Z-9a67`, preset „Parakeet PL": przebieg na `local://fluidaudio`, 2 okna (56 s audio), 0 nieudanych, 4 wypowiedzi, 2 s. Korekta przez API poszła o 00:29 (`failedBatches: 0`), więc **sieć była włączona przy korekcie**; stan Wi-Fi w czasie samej transkrypcji nie jest zapisany w danych — „offline" przyjmuję z deklaracji użytkownika, nie z pomiaru.
- **P8** (Improve transcript ukryty bez wypowiedzi), **P9** (pełna nazwa presetu w nagłówku Meetings), **P10** (tor systemowy bez próbek to informacja, czas z najdłuższego toru): użytkownik potwierdził, „wszystko działa jak należy".
- **Nowe, priorytet wysoki:** echo głośników w mikrofonie (BACKLOG, ROADMAP).
