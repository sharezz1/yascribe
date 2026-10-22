# ROADMAP — co dalej po fazie 1.5a

> Zebrane 2026-10-16 z dokumentów źródłowych; **przydział do fazy jest tylko tam, gdzie zapadła
> decyzja** (źródło w nawiasie). Pozycje bez decyzji są w sekcji „Nieprzypisane” — fazę wybiera
> użytkownik przy planowaniu. Przy sprzeczności wygrywa dokument źródłowy, nie ten plik.

## Gdzie jesteśmy

- **Faza 1** — zamknięta 2026-10-13 (`master`).
- **Faza 1.5a** — zamknięta 2026-10-16, tag `faza-1.5a` → `b4f5804`, gałąź `faza15` na GitHubie:
  język wizualny B ([macos.md §11](../design/macos.md)), trzy odbiory na żywo, ElevenLabs
  bezpośrednio, szablony z sekcjami, Recordings z retencją audio
  ([raport F15-T13 część B](reports/F15-T13-czesc-B.md)).
- **Faza 1.5b, kamień milowy „wyciszanie torów”** — scalone do `faza15` 2026-10-19, tag `faza-1.5b-wyciszanie`
  (345/345, odbiór na żywo zaliczony; [raport F15b-wyciszanie](reports/F15b-wyciszanie.md)). 1.5b trwa dalej.
- **Faza 1.5 (1.5a + 1.5b + 1.6 + „Coming up”) — scalona do `master` 2026-10-19** (`--no-ff`, tag `faza-1.5` na commicie scalenia; `faza-1.6` → `49c4980`), 355/355. Przegląd całości: [F15-przeglad-calosci](reports/F15-przeglad-calosci.md) (0 blokujących); poprawki P1, P2, P4: [F15-poprawki-P1-P2-P4](reports/F15-poprawki-P1-P2-P4.md).
- **Faza 2.0 „Lokalne modele"** — **scalona do `master` 2026-10-20 przez PR #1** (commit scalenia `7eebaea`, `--merge`, tag `faza-2.0`), 580/580, wraz z poprawkami P1–P7 po odbiorach (`reports/F20-lista-poprawek.md`). Cofnięcie: `git revert -m 1 7eebaea`. Zostają kroki wyłącznie użytkownika (sekcja niżej).
- **Faza 2.0.1 „Zmiana modelu w spotkaniu"** — scalona do `master` 2026-10-22 (PR #19 `bed13d5`, PR #20 `0409a3f`), 592/592; wybór modelu podsumowania i korekty przy sesji (`notes/meta.json`). Odbiór na żywo zaliczony przez użytkownika 2026-10-22 (regeneracja Summary i transkryptu, restart, „Use preset”, zagnieżdżony popover, wznowienie z własnym modelem korekty) ([spec](specs/2026-10-22-zmiana-modelu-w-spotkaniu-design.md), [plan](plans/2026-10-22-faza201-zmiana-modelu.md)).
- **Faza 2.0.2 „Nagrywanie na słuchawkach"** — przypisana przez użytkownika 2026-10-22, niezaczęta (spec i plan do napisania): tor `system` na słuchawkach Bluetooth (format tapa czytany raz, pomiar, ostrzeżenie o torze z mniejszą ilością audio); pigułka z PR #17 to pierwszy krok. Wybór mikrofonu i wyjścia przed startem: do ustalenia, czy w tej fazie. Źródło: BACKLOG „PRIORYTET WYSOKI … słuchawki Bluetooth".
- **Faza 2.1 „Słownik"** — decyzja użytkownika 2026-10-21: obowiązkowa następna faza (sekcja niżej).

## Faza 1.5b (zostało: T11 i drobne)

| Pozycja | Źródło |
|---|---|
| ✅ **Wyciszanie torów w pigułce** (cisza zamiast przerwy, „Muted”, okresy w dzienniku, zakaz wyciszenia obu) — zrobione 2026-10-19, [raport](reports/F15b-wyciszanie.md) | [macos.md §11.5](../design/macos.md) |
| ✅ Zdarzenie w dzienniku przy pierwszym dźwięku po `allZeros60s` (trwałe odróżnienie ciszy na początku od braku uprawnień) — `track.audible`, razem z wyciszaniem | decyzja (b), [F15-T13 część B](reports/F15-T13-czesc-B.md) |
| **Pomiar języka Auto i pary PL+EN (T11)** — czeka na nagranie mieszane i klucz w terminalu użytkownika; wynik decyduje o fazie 2 | [spec 1.5 §9 pkt 11, decyzja 8](specs/2026-10-14-faza15-design.md), [F15-T13 uwagi, C](reports/F15-T13-uwagi-uzytkownika.md) |
| ✅ Przegląd całości przez Opusa (2026-10-19, [raport](reports/F15-przeglad-calosci.md)), potem scalenie `faza15` → `master` (2026-10-19, `--no-ff`) | [spec 1.5 §9 pkt 13](specs/2026-10-14-faza15-design.md) |
| Drobne z przeglądów T5/T6/T10 (tytuły z `\r`, `MarkdownBlocks` dla tabel, wyścig `updateMeta`, `AutoTitle.clean`, `ContextError`, wygaszanie poziomów…) — bez rundy poprawek, do sesji porządkowej | [BACKLOG](BACKLOG.md) |

**Równolegle, poza fazami:** nazwa (**Yascribe**), logo i ikona aplikacji — sesja designu w toku;
podpięcie ikony do paczki (`scripts/bundle.sh`, `Info.plist`) i ewentualna zmiana nazwy to
osobny krok po decyzji.

## Faza 1.6 „Kalendarz i wykrywanie spotkań" (decyzja użytkownika 2026-10-16, przed fazą 2)

Spec do przeglądu: [faza16-kalendarz](specs/2026-10-16-faza16-kalendarz-design.md) — Apple Calendar
jako opcja w Settings, pigułka przy starcie spotkania (kalendarz i rozmowa ad hoc w Teams), auto-start
jako przełącznik, wykrywanie końca przez aplikację (nie kalendarz), tytuł z wydarzenia, ręczne
powiązanie wydarzenia z notatką. Google Calendar / Outlook / Slack: tylko wyszarzone wiersze „Coming soon".
Wymaga spike'a na sprzęcie (lista procesów audio, Teams, OOO w Exchange) przed planem.

**Stan (2026-10-19):** kod T0–T12 scalony do `faza15`, odbiór na żywo T10/T11 zaliczony przez użytkownika (zbiorczo), przegląd całości: [F16-przeglad](reports/F16-przeglad.md) (0 blokujących). **Niezamknięte:** poczekalnia Teams (kryterium §6 pkt 2) bez pomiaru i decyzji; wizyta u lekarza, urodziny i OOO pokryte tylko testami z pomiaru T0. Tag `faza-1.6` → `49c4980`. „Coming up" zrobione ([F16-coming-up](reports/F16-coming-up.md)); zostają integracje Google/Outlook/Slack.

## Faza 2.0 „Lokalne modele" (scalona do `master` 2026-10-20, PR #1, tag `faza-2.0`; zostają kroki użytkownika)

Lokalna ścieżka **obok API**, nie zamiast niego (decyzja użytkownika 2026-10-19, [spec §3](specs/2026-10-19-faza20-lokalne-modele-design.md)).
**Stan (scalona do `master` przez PR #1, `7eebaea`, tag `faza-2.0`, 580/580):** Zrobione jest to, co
dało się bez rąk użytkownika: **S1** ([raport](spikes/2026-10-20-f20-s1-jakosc-asr.md), `6f2da98`), **odbiór 2.0a** ([T8](reports/F20-2.0a-odbior.md), `cec0263`/`aca4260`; wykryta U1 naprawiona w `11fb41d`),
**odbiór 2.0b i przegląd całości** ([T14](reports/F20-2.0b-odbior.md), [przegląd](reports/F20-przeglad-calosci.md), `a8ad702`). **Znalezisko przed scaleniem:** Ollama + `bonsai-2` obcina wejście po cichu
(obrona `usage.prompt_tokens` vs długość promptu — wdrożona w T14b, `606ee39`; [spec §14 „Korekta po T14”](specs/2026-10-19-faza20-lokalne-modele-design.md)).
**Tylko użytkownik** (usunięcie modelu, „Download” i lokalna transkrypcja presetem „Parakeet PL” w `.app` zaliczone 2026-10-22; stan Wi-Fi nie zapisany w danych): nagranie na żywo dla kryterium 3.1 i pary PL+EN (T11),
oMLX z modelem mieszczącym się w pamięci i własnym kluczem, baseline API (klucz, koszt, wysyłka do chmury), decyzje z przeglądu §5. Decyzje: [F20-decyzje-opusa](reports/F20-decyzje-opusa.md) (z listą „Do potwierdzenia rano").

| Pozycja | Stan | Źródło |
|---|---|---|
| **2.0a** — lokalny ASR: Parakeet TDT v3 w procesie przez FluidAudio (`exact: "0.17.7"`), moduł `MeetNotesLocalASR`, karta modelu z pobieraniem po kliknięciu, odmowa bez modelu i bez cichego fallbacku do API | kod T2–T7 na gałęzi; S0 = GO (`697e056`, `76fab16`); **S1 wykonany** (`6f2da98`); **odbiór T8 bez kroków użytkownika** (`cec0263`, `aca4260`) — Wi-Fi off, „Download”, 3.1 czekają na użytkownika | [spec §4](specs/2026-10-19-faza20-lokalne-modele-design.md), [S0](spikes/2026-10-20-f20-s0-fluidaudio.md), [S1](spikes/2026-10-20-f20-s1-jakosc-asr.md), [T8](reports/F20-2.0a-odbior.md) |
| **2.0b** — Ollama / llama.cpp / oMLX jako lokalni dostawcy tekstu: limity czatu, `finish_reason: "length"` = błąd, `reasoning_effort: "none"`, budżet kontekstu („Context window"), numeracja partii korekty 1…N | kod T10–T13 na gałęzi; S2 wykonany (`38ac47f`); **odbiór T14 na sprzęcie** (`a8ad702`: map-reduce 60 min przy 4096/8192 kończy się jawnym błędem, potrzebny kontekst ≥ 16384; **ciche obcięcie wejścia na Ollamie + `bonsai-2`** — obrona T14b w toku); oMLX i baseline API niezmierzone | [spec §5, §14](specs/2026-10-19-faza20-lokalne-modele-design.md), [S2](spikes/2026-10-20-f20-s2-serwery-tekstowe.md), [T14](reports/F20-2.0b-odbior.md), [przegląd](reports/F20-przeglad-calosci.md) |
| ✅ **Długie transkrypty (map-reduce)** dla podsumowania — **tylko dla dostawców lokalnych**; korekta dzieli na partie z budżetu kontekstu. Dla API nadal bez dzielenia (`ContextBudget.resolve` daje `nil`, komunikat „Splitting long transcripts arrives later" zostaje) | część lokalna zamknięta w 2.0b; **część API otwarta** | [spec 1.5 decyzja 20, §10](specs/2026-10-14-faza15-design.md), [spec 2.0 §5.2](specs/2026-10-19-faza20-lokalne-modele-design.md) |
| ✅ **Lokalny ASR w procesie (Parakeet v3)** — zamknięte w kodzie 2.0a; **Cohere Transcribe lokalnie nie jest zrobione** (zostaje w „Nieprzypisane") | kod na gałęzi, odbiór bez kroków użytkownika wykonany (T8) | [wymagania §0, §2](../wymagania.md) |
| Odłożone z 2.0 (`.int8` vs `.int8V2`, przypięcie rewizji HF, większe okna lokalnego ASR, bramka dat/liczb w lokalnej korekcie, drobiazgi z przeglądów) | do decyzji użytkownika | [BACKLOG „Z fazy 2.0"](BACKLOG.md) |

## Faza 2.1 „Słownik" (decyzja użytkownika 2026-10-21: obowiązkowa, następna po 2.0)

Powód: test korekty na żywo (sesja z 2026-10-21, [lista poprawek](reports/F20-lista-poprawek.md)) pokazał, że ASR i korekta poprawiają tylko przerywniki; nazwy własne zostają błędne
(„Jarla" zamiast Jarka, „Zoe"/„Zoey"/„Zoim" zamiast **Zowie**, „Doomem"/„Zoomem"). Korektor nie wie, kim są uczestnicy ani jakie nazwy występują w firmie.

| Pozycja | Źródło |
|---|---|
| **Własny słownik** (terminy + aliasy „co usłyszał → co miało być", format = `replacements.tsv`, 166 terminów i 223 pary w `GCX/dictation/`), zakładka Dictionary, pętla „klik na słowo → poprawka → alias" | [wymagania §3](../wymagania.md), [macos.md §9](../design/macos.md) |
| **Word boosting** w lokalnym ASR (FluidAudio ma `customVocabulary`; dla ścieżki API boosting nie istnieje, tam zostaje podmiana po transkrypcji i słownik w poleceniu korektora) | [wymagania §3](../wymagania.md) |
| Do rozstrzygnięcia w specyfikacji (nie ustalone): gdzie słownik działa (po ASR, w poleceniu korektora, w podsumowaniu), czy uczestnicy z wydarzenia kalendarza trafiają do kontekstu automatycznie, czy słownik jest globalny czy per preset | — |

## Faza 2.1+ (kandydaci po 2.0; fazę wybiera użytkownik)

| Pozycja | Źródło |
|---|---|
| **Wbudowany model tekstowy** pobierany i uruchamiany przez aplikację (`llama-server` jako sidecar zarządzany przez aplikację: pobranie GGUF z sumą kontrolną i zgodą, start, health-check, zatrzymanie po bezczynności). Decyzja użytkownika: „w fazie 2.1 albo dalszej, nie priorytet"; furtka w 2.0: lokalny model to zwykły `Provider` mówiący `/v1/*`, więc preset, `Corrector` i `NoteGenerator` nie zauważą różnicy | [spec 2.0 §2 (nie-cele), §3 pkt 4, §8](specs/2026-10-19-faza20-lokalne-modele-design.md) |
| **Diaryzacja lokalna** — spec 2.0 zostawia ją „pod swoim numerem"; **bez przydziału do fazy**, wiersz w „Nieprzypisane" poniżej pozostaje obowiązujący. (Słownik/word boosting: przeniesiony do fazy 2.1, patrz wyżej.) | [spec 2.0 §2](specs/2026-10-19-faza20-lokalne-modele-design.md), [wymagania §3–§5](../wymagania.md) |

## Faza 2 (decyzje już zapadły)

| Pozycja | Źródło |
|---|---|
| Transkrypt na żywo w trakcie spotkania | [spec 1.5 decyzja 1](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md), [wymagania 🆕](../wymagania.md) |
| „Resume” — wznowienie nagrania do tej samej notatki (wiele segmentów sesji) | [spec 1.5 decyzja 1](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md) |
| Wybór mikrofonu przed startem (rdzeń: źródło + dziennik + obserwator urządzeń) | [spec 1.5 decyzja 4](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md) |
| Długie transkrypty: dzielenie na części (map-reduce) dla korekty i notatki — ✅ dla dostawców lokalnych w 2.0b (gałąź `faza20`, patrz wyżej); **dla API nadal otwarte** | [spec 1.5 decyzja 20, §10](specs/2026-10-14-faza15-design.md) |
| Odzyskiwanie odmówionej zgody TCC (instrukcja + „Reset permission”) i klucze TCC w `Info.plist` | [BACKLOG](BACKLOG.md), aneks S18 |
| Target testowy aplikacji (`MeetNotesApp` jako biblioteka + testTarget) | [BACKLOG](BACKLOG.md), aneks S18 |
| `reloadSessions()` poza MainActorem, debounce zapisu ustawień | [BACKLOG](BACKLOG.md), aneks S18 |
| Minimalna wersja macOS (`.macOS(15.0)` vs `LSMinimumSystemVersion 27.0`) | [BACKLOG](BACKLOG.md), aneks S18 |
| Oś i czas trwania nagrań bez dźwięku systemowego („0 min”) | [BACKLOG](BACKLOG.md), [spec 1.5 §10](specs/2026-10-14-faza15-design.md) |
| **PRIORYTET WYSOKI (użytkownik, 2026-10-22):** AEC offline (echo głośników w mikrofonie; w 1.5 jest filtr tekstowy, który w prawdziwym spotkaniu oznaczył 32 z 58 linii „Me”, ale nie łapie krótkich) | [F15-T13 uwagi, A #2](reports/F15-T13-uwagi-uzytkownika.md) |
| Decyzja o „Auto” / parze języków na podstawie pomiaru T11 | [spec 1.5 decyzja 8](specs/2026-10-14-faza15-design.md) |

## Faza 3 (decyzja już zapadła)

| Pozycja | Źródło |
|---|---|
| Wyszukiwanie w archiwum (embedding, indeksowanie; model wybierany już dziś w Settings) | [spec 1.5 §10](specs/2026-10-14-faza15-design.md) |

## Nieprzypisane (z wymagań — fazę wybiera użytkownik)

| Pozycja | Źródło |
|---|---|
| ✅ Lokalny ASR w procesie: FluidAudio + Parakeet v3 — kod w 2.0a na gałęzi `faza20` (S1 i odbiór T8 wykonane; kroki użytkownika otwarte). **Zostaje:** Cohere Transcribe lokalnie | [wymagania §0, §2](../wymagania.md) |
| Diaryzacja lokalna z nastawialnym progiem, edycja rozmówców, automatyczne nazwiska; tożsamość mówcy aż do zadań | [wymagania §4, §5](../wymagania.md) |
| **→ Faza 2.1.** Słownik i word boosting (format aliasów = `replacements.tsv`), klik na słowo → poprawka → alias (zakładka Dictionary) | [wymagania §3](../wymagania.md), [macos.md §9](../design/macos.md) |
| Kalendarz Apple: „Coming up” na stronie głównej — **design gotowy 2026-10-19** (wariant B: karta najbliższego spotkania ≤ 60 min + mały Record ad hoc w nagłówku, [macos.md §11.5](../design/macos.md)); **wdrożone 2026-10-19** na gałęzi `claude/infallible-wu-2aef0e` ([F16-coming-up](reports/F16-coming-up.md); D1 potwierdzone, D2–D9 u użytkownika; scalone do `faza15` i z nią do `master` 2026-10-19) (sam EventKit i wykrywanie → faza 1.6; koniec sesji z kalendarza **uchylony**) | [wymagania §5](../wymagania.md), [spec 1.6](specs/2026-10-16-faza16-kalendarz-design.md) |
| Chat nad spotkaniem i nad archiwum (RAG, „Ask anything”) | [wymagania §4](../wymagania.md), [spec 1.5 §2](specs/2026-10-14-faza15-design.md) |
| Zakładka zadań (zależna od tożsamości mówcy) | [wymagania §4](../wymagania.md) |
| Dyktowanie na żywo (osobny tryb) | [wymagania §1](../wymagania.md) |
| MCP dla Claude, eksport notatek do plików markdown | [wymagania §6](../wymagania.md) |
| Kompresja audio do Opusa po sesji (wznawialny krok) | [spec rdzenia nagrywania](specs/2026-09-24-rdzen-nagrywania-design.md) |
| Punkty notatki z odnośnikami do miejsca w transkrypcie (widoczne źródło) | [macos.md §11.8](../design/macos.md) |
| Historia wersji notatek w UI, wyszukiwarka w widoku transkryptu | [spec 1.5 §2](specs/2026-10-14-faza15-design.md) |
| Odsłuch zmiksowany (po wyrównaniu, oryginały zostają); nagrywanie ekranu (rekomendacja: nie w v1) | [wymagania §7](../wymagania.md) |
