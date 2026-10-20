# F20 — lista poprawek zgłoszonych przez użytkownika

Błędy i zmiany zgłoszone przez użytkownika na gałęzi `faza20` po odbiorach T8/T14 (stan kodu: `79f3e6b`, 561/561).
Pozycje dopisywane w kolejności zgłoszenia; decyzje są użytkownika, zapis niżej to ustalenia z rozmowy 2026-10-20.
**Stan (2026-10-20, wieczór):** P1, P3 i P4 zrobione na gałęzi `faza20-poprawki` (odgałęzienie od `79f3e6b`, cztery commity, **571/571**,
bez scalenia i bez pushu). P2 i P5 celowo bez kodu: czekają na decyzję (P2) i pomiar na działającej aplikacji (P5).
Aplikacja uruchomiona u użytkownika to **stary build** — poprawki zobaczy po `scripts/bundle.sh` albo `scripts/run.sh` (nie podmieniałem `~/Applications/MeetNotes.app`).

## P1 — „Correction failed: the model didn't answer within 120 s" (API, OpenRouter)

**Stan: zrobione w `9602466`** (przyczyna ustalona wcześniej, poniżej).

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

**Stan: bez kodu, do decyzji.** Opcje (asystent), od najmniejszej:
- **A. Tylko polecenia dla modelu.** Gotowy tekst do pola „Extra instructions" korekty (np. „Remove filler sounds such as yyy, eee, mhm; do not remove words that carry meaning"). Zero kodu,
  ale model bywa niekonsekwentny (próba B zostawiła „yy"), a pole jest per preset.
- **B. Filtr deterministyczny na wyniku korekty** (po modelu, przed zapisem `corrected.json`). Korekta i tak podmienia tylko `text` (czas i mówca z oryginału), więc czasy słów nie cierpią.
  Surowy transkrypt zostaje nietknięty, filtr działa tylko na tekście poprawionym. Lista w Settings (edytowalna, domyślnie polska + angielska), przełącznik. Brak korekty = brak filtra.
- **C. Filtr na tekście ASR** (jak FluidVoice, przed zapisem `transcript.json`). Działa także bez korekty, ale zmienia `Utterance.text` bez zmiany `words`, a czasy słów dalej wskazują usunięte
  słowa; zmiana ścieżki, którą czytają wyszukiwanie i podsumowanie. Odradzam bez decyzji o `words`.
Rekomendacja: A od razu (zero ryzyka), B po decyzji o liście domyślnej i miejscu w Settings.

## P3 — Settings: Parakeet to model Yascribe, nie dostawca

**Stan: zrobione w `148d9ea`.** Pierwotny zakres: `Sources/MeetNotesApp/SettingsView.swift`, `ModelCardView.swift`, `ProviderLogos.swift`,
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

**Stan: zrobione w `8736c68` i `849e25f`.** `Sources/MeetNotesApp/PresetsView.swift` (`RoleSection`, `providers` na linii 275 to dziś **wszyscy** dostawcy w każdej roli).

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

**Stan: zgłoszone, przyczyna nieustalona, nie zrobione.** Zgłoszenie użytkownika: po wejściu w Meetings i wybraniu spotkania zmienia się szerokość sidebaru.

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
