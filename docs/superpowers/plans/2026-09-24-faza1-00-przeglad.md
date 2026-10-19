# Faza 1 — przegląd planu implementacji

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** pierwsza używalna wersja MeetNotes: nagrywanie spotkania dwoma kanałami, zapis, transkrypcja przez OpenRouter z przypiętym językiem, presety i ustawienia dostawców.

**Architektura:** pakiet SwiftPM z czterema bibliotekami (`MeetNotesSessionFormat`, `MeetNotesRecording`, `MeetNotesProviders`, `MeetNotesTranscription`), narzędziem `meetnotes-cli` i aplikacją SwiftUI `MeetNotesApp` składaną w `.app` bez Xcode. Rdzeń nagrywania nie zależy od ASR — pilnuje tego graf zależności w `Package.swift`, nie komentarz.

**Stos:** Swift 6.4 (tryb języka 6), Command Line Tools, SDK macOS 27.0, `swift-testing`, Core Audio (process tap), AVFoundation, SwiftUI + AppKit (`NSPanel`), Security (pęk kluczy), URLSession. Zero zależności zewnętrznych.

**Specyfikacje:**
- `docs/superpowers/specs/2026-09-24-rdzen-nagrywania-design.md`
- `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md`
- `docs/design/macos.md` (referencja platformy dla interfejsu)

---

## 0. Instrukcja dla Hermesa (wykonawca)

**Hermes jest orkiestratorem**: prowadzi sesje z runbooka (`2026-09-25-faza1-runbook.md`), przydziela je agentom według modeli niżej, czyta raporty i przeglądy, decyduje, czy iść dalej. Autorem planu jest Claude Code; plan zmienia się tylko przez użytkownika. Decyzje projektowe (bramki, STOP) idą do użytkownika.

**Kolejność:** 0 → A1…A9 → **E1** → A10 → B1…B3 → **E2** → B4, B5 → C1…C3 → **E3** → C4, C5 → D1, D2 → **E4** → D3.

**Zasady:**

1. Jedno zadanie = jedna sesja. Przed startem przeczytaj §4 (ograniczenia) i całe zadanie.
2. Kod przepisuj dosłownie. Nie „ulepszaj", nie zmieniaj nazw, nie dodawaj zależności.
3. Po każdym „Uruchom" porównaj wynik z „oczekiwane". Rozbieżność = **STOP i raport**, nie naprawa na ślepo. Wyjątek: zadania ⚠️ — błąd *kompilacji* napraw minimalnie i opisz w raporcie.
4. Kroki „wymaga użytkownika": wypisz polecenia, poczekaj na wynik. Nie przestawiasz Ustawień systemowych ani pęku kluczy, nie czytasz i nie wpisujesz klucza API.
5. „STOP" w planie = agent zatrzymuje się i zgłasza orkiestratorowi. Orkiestrator nie podejmuje decyzji projektowych — przekazuje je użytkownikowi.
6. Testy wyłącznie przez `scripts/test.sh`. Commit po zadaniu, poleceniem z planu.

**Raport po zadaniu** — plik `docs/superpowers/reports/<zadanie>.md` i ta sama treść w odpowiedzi: zadanie, hash commita, ostatnia linia `scripts/test.sh`, odchylenia od planu z powodem, pytania do orkiestratora.

**Modele** (decyzja użytkownika 2026-09-25):

| Rola | Model | Dostawca | Zadania |
|---|---|---|---|
| **szybki** | `deepseek-v4.1-flash` | OpenCode Go | ✅ przepisanie zweryfikowanego kodu (A1–A8, B1–B3, C1–C3), zadanie 0, prowadzenie sesji z użytkownikiem (A10, B5, C5, D3) |
| **kodowy** | Claude Opus 5.5 | Claude Code | kod 🔧/⚠️ i poprawki (A9, B4, C4, D1, D2, E1–E4) |
| **przegląd** | GPT 6 Sol | OpenRouter | przegląd po każdej sesji oznaczonej „Przegląd po: tak" i przegląd całej gałęzi (S18) |

Przegląd robi zawsze inna rodzina modeli niż wykonawca.

---

## 1. Jak czytać ten plan

Faza 1 to cztery podsystemy, więc cztery plany, każdy z działającym i testowalnym wynikiem:

| Plan | Plik | Wynik | Zależy od |
|---|---|---|---|
| **A** | `2026-09-24-faza1-01-fundament-i-nagrywanie.md` | pakiet, skrypt testów, format sesji, rdzeń nagrywania, CLI `record` | — |
| **B** | `2026-09-24-faza1-02-dostawcy-i-presety.md` | klient OpenAI-zgodny, sonda, presety, CLI `probe` | A1 (szkielet pakietu) |
| **C** | `2026-09-24-faza1-03-potok-transkrypcji.md` | bramka, pakowanie okien, scalanie, strażnik języka, CLI `transcribe` | A, B |
| **D** | `2026-09-24-faza1-04-powloka-aplikacji.md` | aplikacja: nawigacja, oś nagrań, presety, ustawienia, setup, pływające okno | A, B, C |
| **E** | `2026-09-24-faza1-05-poprawki-po-recenzjach.md` | poprawki po recenzjach, wplecione w kolejność (§0) | A–D |

B może iść równolegle z A2–A10, bo dzieli z A tylko szkielet pakietu.

## 2. Stan wyjściowy: spike z 2026-09-24

W trakcie pisania planu kod fazy 1 został napisany i przetestowany w katalogu roboczym sesji
(`/private/tmp/claude-501/-Users-michalprzytulski-meetnotes/b92290ab-1a66-431e-abb7-7664a03e80d7/scratchpad/mn`).
To wykroczyło poza zakres „napisz plan" i użytkownik to zauważył. Decyzja użytkownika: kodu
nie wyrzucać, włączyć go do planu. Katalog roboczy jest tymczasowy, dlatego **cały kod jest
w dokumentach planu** — plan nie zależy od tego, czy katalog przetrwa.

Każde zadanie ma w nagłówku status ze spike'a:

| Status | Znaczenie |
|---|---|
| ✅ **zweryfikowane** | kod i testy skompilowane i zaliczone w spike'u (Swift 6.4, `scripts/test.sh`: 83/83 w ostatnim przebiegu; sam skrypt sprawdzony w 5 czystych przebiegach przy 23 testach i dwiema mutacjami) |
| 🔧 **skompilowane** | kod skompilowany w trybie Swift 6, nigdy nie uruchomiony — dotyka sprzętu albo interfejsu |
| ⚠️ **nieweryfikowane** | kod napisany w planie, nigdy nie kompilowany. Wykonawca kompiluje go pierwszy |

Kod z ✅ i 🔧 jest wklejony do planu automatycznie z plików spike'a. Trzy wyjątki, każdy opisany
w swoim zadaniu: `CLI.swift` jest rozdzielony między A9, B4 i C4 (⚠️), `Helpers.swift` między
C1 (`Signals.swift`, z ograniczonymi importami) i C3 (`SessionFixtures.swift`), a nagrania próbne
są generowane skryptem. Po recenzji z 2026-09-24 kilka plików ✅ dostało małe poprawki — każda
jest opisana w zadaniu jako ⚠️ i ma swój krok. Tam, gdzie to się dzieje, „identyczny z tym, co
przeszło kompilator" dotyczy kodu **przed** poprawką. Poprawki i cały plan E sprawdzono potem przebiegiem kontrolnym 2026-09-25: 99/99, bez poprawek kompilacji (runbook §6).

## 3. Bramki

| # | Bramka | Kto | Przed |
|---|---|---|---|
| **G0** | Zatwierdzenie poprawek speców (zadanie 0 niżej) | użytkownik | A1 |
| **G1** | Sonda S1: co robi tap przy odmowie uprawnienia (błąd czy zera) | użytkownik przy komputerze | D (setup) |
| **G2** | Sonda S2: czy surowy mikrofon i mikrofon z AEC dają się nagrywać jednocześnie | użytkownik przy komputerze | zamknięcie planu A |
| **G3** | Sonda na żywo: `microsoft/mai-transcribe-2` z kluczem użytkownika | użytkownik (koszt: grosze) | C |

G2 może **zmienić spec**: jeśli oba strumienie mikrofonu nie działają naraz, użytkownik
decyduje, który porzucić. Plan wtedy się zatrzymuje.

## 4. Wspólne ograniczenia (obowiązują każde zadanie każdego planu)

- Toolchain: **Swift 6.4, Command Line Tools, SDK macOS 27.0, bez Xcode**. `swift-tools-version:6.0`, tryb języka Swift 6.
- Testy: wyłącznie **`swift-testing`** (`import Testing`). XCTest bez Xcode nie istnieje (📐: `unable to resolve module dependency: 'XCTest'`).
- 🔴 **Testy uruchamiasz wyłącznie przez `scripts/test.sh`, nigdy gołym `swift test`.** Silnik budowania Swift 6.4 niedeterministycznie gubi plugin makr `TestingMacros`, a następny przebieg potrafi zameldować `Test run with 0 tests ... passed` albo uruchomić 11 testów z 23 bez żadnego błędu (📐 w spike'u). Skrypt ładuje plugin jawnie i sprawdza, że uruchomiło się tyle testów, ile jest deklaracji `@Test`. Kody wyjścia: `0` zaliczone, `1` test pada albo błąd kompilacji, `3` błąd pluginu makr (to nie jest wynik — `rm -rf .build` i powtórz), `4` liczba testów się nie zgadza (wynik nieważny).
- 🔴 **Bez `@State`, `@Entry`, `@Animatable`, `#Preview`.** W SDK macOS 27 to makra, a pluginu `SwiftUIMacros` nie ma w Command Line Tools (📐: `plugin for module 'SwiftUIMacros' not found`). Stan lokalny widoku: `ObservableObject` pod `@StateObject`. Model aplikacji: `@Observable` przez `@Environment`/`@Bindable`. `@Observable` działa (plugin `ObservationMacros` jest w CLT).
- Platforma: `platforms: [.macOS("15.0")]` w pakiecie; `LSMinimumSystemVersion` **27.0** w `Info.plist` — deklarujemy tylko to, co przetestowane.
- Zero zależności zewnętrznych w fazie 1.
- Interfejs po angielsku (`docs/design/macos.md`), komentarze i dokumenty po polsku.
- `MeetNotesRecording` **nie zależy** od `MeetNotesProviders` ani `MeetNotesTranscription` (spec rdzenia §3).
- Pliki sesji: `system.caf` (częstotliwość i kanały tapu, Int16), `mic_raw.caf` (16 kHz mono Int16; `mic_aec.caf` tylko w sesjach z AEC — build aplikacji nagrywa `system` + `mic_raw`, decyzja S5), `journal.jsonl`, `session.json`, `runs/<id>/`.
- 🔴 Nigdy `auto` przy języku: `LanguageCode` nie powstaje z `"auto"` ani z pustego napisu.
- Dane w trakcie prac: `.devdata/` przez `MEETNOTES_DATA_DIR` (już w `.gitignore`).
- Bez sandboxa, bez ScreenCaptureKit, bez prośby o nagrywanie ekranu.
- Commit po każdym zadaniu, poleceniem z planu. Stopkę współautorstwa wykonawca dodaje według własnej konwencji — plan jej nie narzuca.

## 5. Pułapki znalezione w spike'u — gdzie są obsłużone

| Pułapka | Pomiar | Obsługa |
|---|---|---|
| `AVAudioFile.read(into:)` oddaje mniej ramek niż pojemność bufora | 63 454 z 64 000 w jednym wywołaniu | własny `CAFReader` (A4); czytniki systemowe zawsze w pętli |
| `AVAudioConverter` przetrzymuje ramki przy buforach > 4096 | 4096 z 4800; przy 512 ramkach 0 przetrzymanych | krojenie na plasterki po 1024 ramki (A7) |
| Rozgrzewanie filtra konwertera przesuwa wyjście | ~16 ms | `primeMethod = .none` (A7) |
| Dryf zegara urządzenia vs zegar hosta | rząd 200 ppm (Narada: 213 ms na 901 s) | luki liczone między **sąsiednimi** porcjami + kotwice `track.clock` co 10 s (A3, A5) |
| Przetwarzanie głosu ścisza inne aplikacje (w tym Teams i kanał systemowy) | domyślne zachowanie `setVoiceProcessingEnabled` | `duckingLevel: .min` (A8) — do sprawdzenia uchem w S2 |
| Brak publicznego API stanu uprawnienia dźwięku systemowego | Wispr Flow i Spokenly używają prywatnego TCC | sprawdzenie działania tonem testowym (A8, D) — zamyka O5 bez prywatnego API |
| Katalog OpenRoutera pomija model transkrypcyjny | 458 modeli, 47 z audio, `mai-transcribe-2` nieobecny | wpisanie modelu z ręki + sonda (B, D) |
| Zasoby SwiftPM psują podpis ręcznie składanego `.app` | lądują w korzeniu paczki | nagrania próbne jako base64 w źródle (B1) |
| Kompilator gubi się we wnioskowaniu typów w domknięciach mieszających słownik i napis | `failed to produce diagnostic for expression` | pomocniki `ok()`/`fail()` w stubach (B1) |
| Pamięć przy transkrypcji długiej sesji | szacunek z kodu (recenzja Hermesa R6): ścieżka systemowa 85 min to ~979 MB jako `[Int16]`; spike robił z niej jeszcze dwie kopie — szczyt ~3 GB | usunięta zbędna kopia w `CAFReader` (A4); pomiar szczytu pamięci z progiem 3 GB (C5) i plan awaryjny |

## 6. Zadanie 0: poprawki speców (bramka G0)

Spike i pisanie planu wykazały błędy w specach. Wykonawca wprowadza je **po** zatwierdzeniu
przez użytkownika, jednym commitem, przed A1.

**Pliki:**
- Zmień: `docs/superpowers/specs/2026-09-24-rdzen-nagrywania-design.md`
- Zmień: `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md`
- Zmień: `docs/wymagania.md`

- [x] **Krok 1: Rdzeń, §9 — T8.** Zamień wiersz zaczynający się od `| **T8** |` na:

```markdown
| **T8** | Sesja 85+ min | czas hosta dowolnej ramki, odtworzony z kotwic `track.clock`, różni się od prawdziwego o ≤ 50 ms; rzeczywista częstotliwość każdej ścieżki jest zapisana w podsumowaniu | liczyć czas z nominalnej częstotliwości → czerwień |
```

i pod tabelą, w miejscu akapitu **„T8 rozdziela dwie różne rzeczy."**, dopisz:

```markdown
✏️ **Korekta z pisania planu.** Pierwsza wersja T8 porównywała czas hosta z długością liczoną
z nominalnej częstotliwości i żądała ≤ 50 ms na ścieżkę. To nie przejdzie na żadnej długiej
sesji: zegar urządzenia dryfuje względem zegara hosta o setki ppm (Narada: 213 ms na 901 s),
czyli o ~0,5 s na 85 minut — i to nie jest błąd, tylko fizyka. Rdzeń zapisuje więc kotwice
`(ramka, czas hosta)` co 10 s i po każdej luce, a T8 sprawdza odtworzenie czasu z kotwic.
```

- [x] **Krok 2: Rdzeń, §9 — T4.** Zamień wiersz zaczynający się od `| **T4** |` na:

```markdown
| **T4** | Zero miksu w odsłuchu. W słuchawkach (bez echa akustycznego), użytkownik mówi, nic nie gra: dopasowanie `system ≈ a·mic_raw` | a ≈ 0 | domieszać mikrofon do ścieżki systemowej → czerwień |
```

i dopisz pod tabelą: `✏️ **Korekta.** Pierwsza wersja dopasowywała mic_raw ≈ a·system i żądała a ≈ 0 — ale surowy mikrofon przy głośnikach musi zawierać echo systemu. Intencja testu: mikrofon nie trafia do pliku odsłuchu.`

- [x] **Krok 3: Rdzeń, §4 — zdarzenia dziennika.** W akapicie „Zdarzenia:" pod `SessionJournal` dopisz po `track.firstSample`: `` `track.clock` (indeks ramki, czas hosta — kotwica dla T8), `` i po `track.permissionDenied (...)`: `` `track.failed` (powód: błąd źródła, a także `allZeros60s` — T9), ``.

- [x] **Krok 4: Rdzeń, §2.1 wiersz 📐10 i §8 „Bez Xcode".** W obu miejscach dopisz: `⚠️ Poprawka: prawdziwe dla SwiftUI bez makr. W SDK macOS 27 @State, @Entry, @Animatable i #Preview są makrami z pluginu SwiftUIMacros, którego nie ma w Command Line Tools. Bez Xcode stan lokalny widoku idzie przez ObservableObject/@StateObject.`

- [x] **Krok 5: Rdzeń, §11 — nowe ryzyko.** Dopisz wiersz: `| Czy surowy mikrofon (HAL) i mikrofon z AEC (AVAudioEngine + przetwarzanie głosu) dają się nagrywać jednocześnie | sonda S2 w planie A (A10). Jeśli nie — decyzja użytkownika, który strumień porzucić |`.

- [x] **Krok 6: Faza 1, §1.5 — sonda honorowania języka.** Zamień punkt 2 listy „Trzy wymagania, które z tego wynikają" na:

```markdown
2. **Sonda honorowania języka** — nagranie w **innym** języku niż preset (dla presetu polskiego
   „one, two, three"), wysłane trzy razy: A z językiem presetu, B1 i B2 bez języka. B1 ≠ B2 →
   model niedeterministyczny → „nie wiadomo". A = B1 → parametr nic nie robi → „automatyczny".
   Inaczej → „wymuszony". Odrzucony parametr języka → „automatyczny" (P10). ✏️ Pierwsza wersja
   wysyłała nagranie w języku presetu — na nim model z działającym parametrem dałby ten sam
   wynik co bez niego i zostałby błędnie uznany za „automatyczny".
```

- [x] **Krok 7: Faza 1, §3 — dialekty.** Zamień zdanie o dwóch dialektach na: `**Dialekt** — kształt API, kod nasz. W fazie 1 jeden: zgodny z OpenAI. Ollama, oMLX i LM Studio wystawiają /v1/*, więc natywny dialekt Ollamy okazał się zbędny (YAGNI).`

- [x] **Krok 8: Faza 1, §8 — koszt.** Zamień `**wersję słownika, datę, liczbę kawałków, koszt i wynik strażnika języka**` na `**wersję słownika, datę, liczbę okien i żądań, sekundy audio wysłane do API i wynik strażnika języka**. Koszt = sekundy × cena modelu; cena nie przychodzi z API transkrypcji, więc nie jest zapisywana.`

- [x] **Krok 9: Faza 1, §12 — O5.** Zamień wiersz O5 na: `| ~~O5~~ | ~~Stan uprawnienia dźwięku systemowego~~ → **rozstrzygnięte:** sprawdzamy działanie, nie flagę — setup odtwarza ton i mierzy, czy tap go usłyszał (SystemAudioCheck). Publiczne API, niezależne od tego, czy odmowa daje błąd, czy zera | — |`.

- [x] **Krok 10: Rdzeń, §9 — mutacja T7.** W wierszu `| **T7** |` zamień ostatnią kolumnę (dziś: skasować fsync → czerwień) na `zapisać rozmiar bloku data 0 zamiast -1 → czerwień`, a pod tabelą dopisz: `✏️ **Korekta.** Usunięcie fsync nie da się wykazać testem: po kill -9 dane z pamięci podręcznej systemu i tak trafiają na dysk, fsync chroni tylko przed utratą zasilania. Mutacją T7 jest więc nagłówek CAF.`

- [x] **Krok 11: Rdzeń, §9 — zakres T9.** Pod akapitem „⚠️ **T9 wyrasta z hipotezy…**" dopisz: `Zakres: strażnik zer obejmuje ścieżkę system. Odmowę mikrofonu wykrywa publiczne API (AVCaptureDevice.authorizationStatus) w prepare(); gdyby mikrofon przy odmowie oddawał zera zamiast błędu, nic tego nie wykryje — świadoma luka fazy 1, do rozszerzenia strażnika, jeśli S1 albo D3 pokażą taki przypadek.`

- [x] **Krok 12: Faza 1, §1.1 — dowód P9.** Po akapicie kończącym się na `założenia dyktowanie wymusi później przepisanie warstwy.` dopisz: `Realizacja w fazie 1: transcribeFile to TranscriptionRunner, a transcribeUtterance to OpenAICompatibleClient.transcribe wołane wprost, jednym żądaniem, bez cięcia. Dowód testem: B1 transcriptionSendsLanguageAndAsksForWordTimestamps i sonda ASR (B2), która wysyła ~2 s audio jednym żądaniem. Osobnej funkcji o tej nazwie nie ma — kontrakt jest ten sam.`

- [x] **Krok 13: Wymagania — liczba rozdziałów.** W `docs/wymagania.md`, linia 8, zamień `(18 rozdziałów,` na `(19 rozdziałów,`.

- [x] **Krok 14: Faza 1, §6.3 — przesłuch.** Na końcu podsekcji dopisz: `Uzupełnienie po recenzji ChatGPT: bramka energii nie odsiewa przesłuchu z głośników. Dla toru mikrofonu dochodzi CrosstalkFilter — fragment, którego obwiednia energii koreluje (≥ 0,8, opóźnienie do 0,3 s) z kanałem systemowym, odpada przed ASR (W§1, rozdz. 17).`

- [x] **Krok 15: Faza 1, §4.1 — kształt czatowy.** Akapit zaczynający się od „⚠️ Modele idące przez czat" zakończ zdaniem: `Decyzja 2026-09-24: kształt czatowy jest blokowany w presetach spotkań — zapis presetu i migawka przebiegu go odrzucają. Zostaje do dyktowania.`

- [x] **Krok 16: Faza 1, §1.5 — preset zamrożony.** W „Gdzie wybiera się preset" dopisz: `Preset jest zamrażany przy starcie nagrania (<sesja>/preset.json) i to on idzie do transkrypcji; zmiana chipa w trakcie nie zmienia bieżącej sesji. Pływające okno służy do wyboru presetu przed nagraniem, a w trakcie pokazuje zamrożony.`

- [x] **Krok 17: Rdzeń, §4 `EndCondition` — uczciwy zakres.** Dopisz: `Faza 1 bez kalendarza: koniec sesji to najlepsza próba — cisza na wszystkich torach albo 4 h. Muzyka albo rozmowa w pokoju po spotkaniu utrzymają nagranie. W§1 jest w pełni spełnione dopiero z kalendarzem (faza 3); zamknięcie okna rozmowy — backlog fazy 3.`

- [x] **Krok 18: Rdzeń, §4 `SessionRecorder` — nadzór torów.** Dopisz: `Każdy tor nadzorowany osobno: brak porcji przez 30 s → track.failed (stalled30s), sesja trwa z pozostałymi.`

- [x] **Krok 19: Commit.**

```bash
git add docs/superpowers/specs/ docs/wymagania.md
git commit -m "Specy: poprawki z pisania planu fazy 1 i recenzji Hermesa" -m "T8 przez kotwice zegara, T4 we wlasciwym kierunku, zdarzenia track.clock i track.failed, SwiftUI bez makr, sonda jezyka na nagraniu w innym jezyku, jeden dialekt, O5 zamkniete, mutacja T7 przez naglowek CAF, zakres T9, dowod P9."
```

## 7. Mapa pokrycia wymagań

Wymagania testowe ze speców → zadanie, które je spełnia. Tam, gdzie pokrycie jest strukturalne
albo częściowe, tabela mówi to wprost.

| Wymaganie | Gdzie | Uwagi |
|---|---|---|
| T1 odsłuch = tap (R² ≥ 0,999) | A7 (konwersja), A10 krok 4 (sprzęt) | |
| T2 rozjazd startu zmierzony | A6 `startOffsetIsMeasuredNotAssumed` | |
| T3 AEC (korelacja ≤ 0,12) | A7 (miara), A10 krok 3 (sprzęt) | |
| T4 zero miksu w odsłuchu | A5 (strukturalnie: jeden pisarz = jedna ścieżka), A10 krok 5 | kierunek po poprawce z zadania 0 |
| T5 koniec z ciszy | A6 `silenceEndsTheSession` + mutacja, A10 krok 9 (sprzęt, `--silence 60`) | |
| T6 przepięcie urządzenia | A5, A6 `deviceSwitchGapIsFilledAndJournaled`, A10 krok 6 | inna częstotliwość słuchawek tylko na sprzęcie |
| T7 `kill -9` | A2 (urwana linia dziennika), A3 (podsumowanie bez `session.ended`), A4 + mutacja (`data -1 → 0`), A10 krok 8 | mutacja tylko w A4 — usunięcie `synchronize()` nie zaczerwieni niczego, bo po `kill -9` dane z pamięci podręcznej systemu i tak trafiają na dysk (`fsync` chroni przed utratą zasilania). Spec po zadaniu 0 |
| T8 kotwice zegara | A3 `clockAnchorsAbsorbDeviceClockDrift` + mutacja, A10 krok 7 | po poprawce z zadania 0 |
| T9 odmowa = jawny błąd | A6 (odmowa w `prepare`, strażnik zer) + mutacja, A10 krok 2 | ścieżka zależna od wyniku S1. ⚠️ Strażnik zer obejmuje tylko `system`; odmowę mikrofonu łapie publiczne API w `prepare`, a zer z mikrofonu nic nie wykrywa — świadoma luka, zapisana w specu przez zadanie 0 |
| P1 Ollama odpada w ASR | B2 (stub), B5 krok 5 (na żywo) | |
| P2 model wpisany z ręki | B2, B5 krok 2 | |
| P3 model tylko czatowy | B2, B5 krok 4 | |
| P4 plik 85+ min | C3 (3 minuty, stub; 1 minuta 48 kHz stereo), C5 kroki 5–6 (w tym pamięć) | |
| P5 wznowienie bez płacenia | C3 + mutacja, C5 krok 3 | |
| P6 cisza bez żądań | C1 + mutacja, C3 | |
| P7 preset bez języka | B3 + mutacja, D3 krok 4 | |
| P8 klucz nie wycieka | B1, B5 krok 6, D3 krok 3 | |
| P9 krótkie okno tym samym kontraktem | B1 `transcriptionSendsLanguageAndAsksForWordTimestamps`, B2 (sonda = jedno żądanie z ~2 s audio) | funkcji o nazwie `transcribeUtterance` nie ma: krótkim oknem jest `OpenAICompatibleClient.transcribe` wołane wprost, bez `TranscriptionRunner`. Spec dostaje to zdanie w zadaniu 0 |
| P10 klasa obsługi języka | B2 + mutacja, B5 krok 3 | |
| P11 strażnik języka | C2, C3 + mutacja | |
| P12 migawka presetu | C3 (`RunSnapshot` zapisany w `run.json`) | ⚠️ strukturalnie: `run.json` jest pisany raz i nie odwołuje się do presetu. Testu „edytuj preset po przebiegu" nie ma |
| P13 jeden embedding | B3 (`GlobalSettings.embedding`, brak pola w `Preset`) | ⚠️ strukturalnie. W fazie 1 nie ma wektorów w archiwum; test wchodzi z RAG (faza 3) |
| Spec §4 krok 2: filtr po modalnościach | D2 krok 4 | ⚠️ luka spike'u, dopisana w planie jako kod nieweryfikowany |
| O6 głęboki link do Ustawień | D3 krok 1 | ⚠️ kotwica `Privacy_AudioCapture` z pamięci, nigdy nie sprawdzona |

## 8. Czego plan fazy 1 nie obejmuje

| Co | Dlaczego |
|---|---|
| Model lokalny, FluidAudio, diaryzacja wewnątrz kanału systemowego | faza 2 |
| Kalendarz, szyna „Coming up", wyróżnione najbliższe spotkanie | faza 3 (wymaga EventKit) |
| Notatki, korekta i podsumowanie **wykonywane** (presety je konfigurują i sondują) | faza 3 |
| Chat nad archiwum, zadania, słownik, dyktowanie | faza 3 i później |
| Migawki UI do PNG (`docs/design/macos.md` §9) | spike wierności renderowania poza ekranem nie był robiony; w fazie 1 przegląd ręczny sześciu ekranów |
| Notaryzacja, hardened runtime | po fazie 1 (Homebrew) |

## 9. Recenzja Hermesa (2026-09-24) — co przyjęte

Plik: `docs/superpowers/plans/2026-09-24-faza1-recenzja-hermes.md`. Fragmenty W2–W4 i sekcja 🟢
są częściowo zniekształcone (zdania przechodzą w inne języki) — tam, gdzie treść dało się
odczytać, jest oceniona niżej.

| Punkt | Decyzja | Gdzie |
|---|---|---|
| R1 brak sprzętowego T5 | przyjęte | A9 opcja `--silence`, A10 krok 9 |
| R2 mutacja T7 | przyjęte co do mapy; proponowana mutacja (`synchronize()`) odrzucona — nie da się jej zaczerwienić | przegląd §7, zadanie 0 krok 10 |
| R3 „kod identyczny" | przyjęte | przegląd §2 |
| R4 P9 / `transcribeUtterance` | przyjęte | zadanie 0 krok 12 |
| R5 sztywna lista źródeł w D2 | **bez zmian** (decyzja użytkownika 2026-09-25) — przy niepowodzeniu G2 plan i tak się zatrzymuje, a zmiana to jedna linia | — |
| R6 pamięć przy 85 min | przyjęte, ze zmierzoną większą skalą (~3 GB) | A4 (`CAFReader`), C5 krok 6 |
| R7 strażnik zer tylko na `system` | przyjęte jako zadeklarowana luka | przegląd §7, zadanie 0 krok 11 |
| R8 osobny prompt | **bez zmian** (decyzja użytkownika 2026-09-25) — separacja jest strukturalna (dwa pola), spec nie wymaga różnej treści | — |
| W1 brak obsługi `segments` | **odrzucone** — `OpenAICompatibleClient.words(_:)` zbiera `segments[].words`. Węższa prawdziwa luka: segmenty z czasem, ale bez słów, dadzą czas przybliżony | — |
| W3 zegar w `StallCondition` | odrzucone — porównuje czas hosta z czasem hosta ostatniej porcji, zgodnie z zamiarem | — |
| W4 „i" w obu listach słów | przyjęte | C2 |
| W5 brak testu potoku na 48 kHz stereo | przyjęte | C3 |
| W6 klucz cache sondy bez adresu | **bez zmian** (decyzja użytkownika 2026-09-25) — w fazie 1 adresu dostawcy nie da się edytować | — |
| W7 `CFBundleInfoDictionaryVersion` | przyjęte | D1 |
| W8 „18 rozdziałów" | przyjęte | zadanie 0 krok 13 |

## 10. Recenzje ChatGPT i Hermesa/DeepSeek (2026-09-24) — co przyjęte

Plan E zawiera poprawki; tu decyzje. Recenzje: `2026-09-24-faza1-recenzja-chatgpt.md` i `2026-09-24-faza1-recenzja-hermes-deepseek.md` (pierwsza recenzja Hermesa: `2026-09-24-faza1-recenzja-hermes.md`).

| Punkt | Decyzja | Gdzie |
|---|---|---|
| ChatGPT #1, Hermes 3.1 — przesłuch | przyjęte | E3 `CrosstalkFilter`, zadanie 0 krok 14 |
| ChatGPT #2, Hermes 4.1 — preset czytany po Stop | przyjęte | E4 (zamrożony przy starcie), zadanie 0 krok 16 |
| ChatGPT #3, Hermes 1.1 — brak presetu w pływającym oknie | przyjęte (decyzja użytkownika: dodać) | E4 |
| ChatGPT #4 — wznowienie z innym presetem | przyjęte | E3 `RunInput` |
| ChatGPT #5 — 429 jako „automatic" | przyjęte | E2 |
| ChatGPT #6 — cache sondy bez języka | przyjęte | E2 |
| ChatGPT #7 — model czatowy w spotkaniu | przyjęte (decyzja użytkownika: blokować) | E3, E4, zadanie 0 krok 15 |
| ChatGPT #8, Hermes 2.4 — „Me" z `system.caf` | przyjęte | E4 |
| ChatGPT #9, Hermes 1.2, 4.2 — nadzór torów, `mic_aec` przy zmianie wejścia | przyjęte | E1, E3 (powrót do `mic_raw`) |
| ChatGPT #10 — połykane błędy konwersji | przyjęte, bez testu jednostkowego (ryzyko wyjątku ObjC) | E1 |
| ChatGPT #11 — klucz w treści błędu | przyjęte | E2 |
| ChatGPT #12 — zakończona uszkodzona linia | przyjęte | E1 |
| ChatGPT #13 — `runID` z `../` | przyjęte | E3, C4 (domyślny runID bez `:`) |
| ChatGPT #14 — niepełna migawka | przyjęte | E3 |
| ChatGPT #15, Hermes 3.2 — 85 min nieobowiązkowe, słaby `jq` | przyjęte | E3 (test 85 min), C5 krok 5 |
| ChatGPT #16 — setup bez testu dźwięku systemowego, błędy torów niewidoczne | przyjęte | E4 |
| ChatGPT #17, Hermes 4.6 — wznowienie tylko w CLI, „ready" przy lukach | przyjęte | E4 |
| ChatGPT 🟡 wycieki Core Audio, Hermes 2.3 | przyjęte | E1 |
| ChatGPT 🟡 T3 bez okna ciszy użytkownika | przyjęte | A10 krok 3 (S2a/S2b) |
| ChatGPT 🟡 czasy luk bez zegara sesji, Hermes 2.5 | przyjęte | E3 |
| ChatGPT 🟡 koniec rozmowy przy dalszym dźwięku, Hermes 3.6 | przyjęte jako zadeklarowane ograniczenie | zadanie 0 krok 17 |
| ChatGPT 🟡 detal nieaktualny w trakcie transkrypcji | do sprawdzenia | D3 |
| ChatGPT 🟡 pusty model w presecie | przyjęte | E2 |
| ChatGPT 🟡 `fit` bez ujemnego opóźnienia | przyjęte jako ograniczenie narzędzia: wzorzec zawsze pierwszy | A10 |
| Hermes 2.1 — `tick` przed `start` | przyjęte | E1 |
| Hermes 2.2 — test B1 używa typu z B3 | przyjęte: test przeniesiony do B3 | B1, B3 |
| Hermes 2.6 — formaty > 2 kanałów | nie naprawiane: dotyczy tylko `session-from-file` z plikiem wielokanałowym, który kończy się jawnym błędem | — |
| Hermes 3.3 — czy dźwięk z Teamsa trafia do nagrania | przyjęte | D3 |
| Hermes 3.4 — rozmiar i „Multilingual" przy modelu | nie dotyczy modeli przez API (brak danych); wraca w fazie 2 | — |
| Hermes 4.5 — „Recovered" przy trwającym nagraniu | przyjęte | E4 |
| Hermes 4.7 — wzorzec T1 w 22 050 Hz | przyjęte | A10 krok 4 |
| Hermes 4.8 — test dźwięku w trakcie nagrania | przyjęte | E4 |

**Liczby testów:** po E1–E3 bezwzględne liczby w B–D są przesunięte względem spike'a — B1 51, B2 58, B3 65, E2 70, C1 80, C2 84, C3 92, E3 99 — po poprawkach S3+S4 i torze `mic_raw` rzeczywiste są o 7 wyższe (C1 87, C2 91, C3 99, E3 106; aktualne liczby trzyma tabela sesji w runbooku); gwarancją i tak jest porównanie z deklaracjami `@Test` w `scripts/test.sh`.
