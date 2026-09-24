# Recenzja pakietu `meetnotes-recenzja-chatgpt.md` — Hermes

**Jak powstała.** Przeczytany cały pakiet (wymagania, 19 rozdziałów, oba specy, przegląd, plany A–D). Gdzie dało się sprawdzić maszynowo, sprawdziłem na tej maszynie (macOS 27 / SDK 27):

- `scripts/test.sh` w spike'u (`scratchpad/mn`) — **83/83, kod 0** (przebieg powtórzony, także filtr pojedynczego testu);
- typecheck wywołań API skopiowanych z planu **verbatim** (`AudioDeviceCreateIOProcIDWithBlock` 5 parametrów, `CATapDescription`, klucze agregatu, voice processing, `AVAudioConverter`, `bufferListNoCopy`, `copyBytes`, `#if _endian`, `AVAudioFile.read(into:)`) — **kompiluje się, kod 0**; jedyny komunikat: `installTap(onBus:bufferSize:format:block:)` ma deprecation w macOS 27.0 (ostrzeżenie, nie błąd);
- sondy `AVAudioConverter` dla zmiany liczby kanałów (wynik w §2.6);
- `say`/`afinfo`/`afconvert` (wynik w §4.7);
- grepowe liczniki (`DeviceWatcher`, `lastEndReason`, `ProvidersFile`, `Merger.sort`) i kody znaków tam, gdzie narzędzia maskują literały `sk-…`.

Nie oceniam — szukam błędów; nie powtarzam punktów z §9 przeglądu (R1–R8, W1–W8). Gdzie nie mam dowodu — piszę „wymaga sondy".

**Uwaga o stanie dokumentu:** specy w pakiecie są sprzed zadania 0, plan po nim (np. §4/T8, §8, §1.5, O5). Zadanie 0 te rozjazdy domyka, więc ich nie punktuję — ale sygnalizuję: czytelnik speców bez przeglądu §6 dostanie sprzeczności z planem; warto dołączyć diff zadania 0 albo wygenerować pakiet po G0.

## 1. Sprzeczności wymagania ↔ spec ↔ plan

### 1.1 Panel nie pokazuje ani nie wybiera presetu (języka/modelu)
- Wymagania (wiersze 171–172): „**Pływające okno** ✅ — 🆕 **to jest miejsce na wybór języka i modelu** (§2), a nie tylko przycisk nagrywania."
- Spec (1688–1689, 1900–1903, 2147–2148): „🔴 Wybrany preset — z językiem — jest widoczny **przed** startem: chip przy przycisku nagrywania **i pływające okno**."
- Plan D2 (8082–8106): `RecordingPanelView` = ikona + `"Recording HH:MM:SS"` + `Stop` (⌘.). **Ani wyboru, ani presetu, ani języka.**
- Chip jest ✔ (8263/8268). Wiersz listy pokazuje preset (8275–8287) — ale na żywo (patrz 4.1), nie w panelu.
- Do decyzji: dodać do panelu menu presetu, najlepiej z pokazaniem „preset · JĘZYK" zamrożonego przy starcie; albo świadomie zawęzić wymagania/spec (wzorem zadania 0).

### 1.2 „Trzy obserwatory" w wymaganiach, dwa w planie
- Wymagania (64–66): „Trzeba obserwować zmianę domyślnego wejścia, wyjścia i listy urządzeń (…) Narada instaluje **trzy** obserwatory." Spec/lekcje (1383–1385): „Trzy obserwatory Core Audio: domyślne wejście, domyślne wyjście, lista urządzeń."
- Kod: `DeviceWatcher` — użycia: `SystemTapSource` (wyjście, 4838) i `RawMicrophoneSource` (wejście, 4955). **Brak obserwatora listy urządzeń; `VoiceProcessedMicrophoneSource` (mic_aec) nie ma żadnego.**
- Skutek w praktyce: 4.2. Kierunek: dodać brakujące obserwatory albo zawęzić wymaganie świadomie.

## 2. Błędy w kodzie

### 2.1 Wyścig: tick przed startem kończy sesję jako `silence` (A6 + A9)
- `SessionRecorder`: `lastLoudAt` startuje od zera (4178); `SilenceCondition.check` liczy `secondsBetween(now, lastLoudAt) >= seconds` (4064–4065); stan jest inicjowany dopiero wewnątrz `start()` (4227: `lastLoudAt = now`).
- CLI: ticker startuje **przed** `start()` (5197 vs 5198). Przy starcie trwającym >1 s pierwszy tick widzi `lastLoudAt = 0` → `.silence` → `finish(.silence)` zanim źródła ruszyły.
- Fix: flaga „started" (tick nic nie robi przed startem i po zakończeniu) + w CLI ticker po `start()`. Test: `tickBeforeStartDoesNothing`.

### 2.2 B1 nie osiągnie „49/49": test z B1 używa typu z B3
- `providerFileNeverContainsAKey` (testy B1) konstruuje `ProvidersFile` (pakiet 5496; repo: `@Test` na 179, użycie na 181; definicja `struct ProvidersFile` dopiero w pliku B3 — pakiet 6323, repo 1008).
- Krok 3 B1 (5502) nie wymienia `ProvidersFile` w oczekiwanych brakujących symbolach, a krok 5 (5864) oczekuje `49/49` — przy wykonaniu planu po kolei plik testów B1 **się nie skompiluje**, zanim B3 doda `Stores.swift`.
- Fix: przenieść ten test do B3 (B1 → 48/48, B2 → 55/55, od B3 dalej 62/62 i wyżej bez zmian) albo zaznaczyć zależność wprost.

### 2.3 `SystemTapSource.build()` — wyciek tapu i agregatu, gdy padnie odczyt formatu
- 4885–4894: tap jest sprzątany tylko w ścieżce błędu tworzenia agregatu; gdy rzuci `CoreAudioDevices.tapFormat(of:)` (4891), tap i agregat **nie są niszczone** (nie trafiają do stanu, więc `teardown()` ich nie zna). W `rebuild()` (4917–4928) = martwy kanał systemowy + wyciek do końca procesu.
- Fix: `do/catch` wokół `tapFormat`: destroy tap + agregat, rethrow.

### 2.4 Klik w czas wypowiedzi „Me" gra z `system.caf`
- `play(from:)` (8379–8385) zawsze otwiera `system.caf`; `UtteranceRow` (8393+) woła to dla każdego mówcy. Ścieżki nie są miksowane (spec rdzenia §5), więc dla „Me" zagra fragment bez głosu użytkownika — cudza mowa albo cisza w tym miejscu.
- Fix: dla `.me` plik mikrofonu + przeliczenie osi przez `SessionClock`; albo świadomie wyłączyć skok dla „Me".

### 2.5 Czasy `ChunkFailure` nie przechodzą przez zegar sesji
- C3 (7468–7469): `ChunkFailure(start:end:)` bierze `sourceStart/EndSeconds` bez `SessionClock` — dla ścieżki mikrofonu UI pokaże zakres przesunięty o offset i dryf. Drobne; fix: `sessionSeconds(track:trackSeconds:)`.

### 2.6 Formaty >2-kanałowe: plan używa konstruktorów, które zwracają `nil` (zmierzone)
- Zmierzone na tej maszynie (SDK 27): `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)` dla 4/6/8 kanałów zwraca **nil**; konstrukcja z jawnym `AVAudioChannelLayout` (5.1A/7.1A) **działa** (bez opcjonalności), a konwersje `6→2` i `6→1` (downmix) **działają** (status 0, ramki wychodzą).
- Plan używa konstruktorów po liczbie kanałów: `FormatConverter.init` (4479), `Resampler.toASR` (6622–6628); formaty urządzeń czyta przez `streamDescription:` bez layoutu (4709–4729). Dla ścieżki/urządzenia >2 kanałów (HDMI/amplituner/agregat) te konstrukcje zwracają nil → `FormatConverter.init` rzuca (`AudioSourceError.coreAudio("AVAudioConverter", -1)`) → `prepare()` ścieżki systemowej pada, a sesja idzie dalej bez „Them" (i bez komunikatu — patrz 4.3).
- Uczciwie: nie mam urządzenia wielokanałowego, więc nie wiem, czy ASBD prawdziwego urządzenia ratuje `streamDescription:` — to jest właśnie sonda do wykonania; dziś żaden krok tego nie sprawdza (T6 testuje przełączenia, nie liczbę kanałów).
- Sugestia: dodać do T6/A10 wyjście wielokanałowe + asercję; przy potwierdzeniu — konstrukcja z layoutem albo świadomy downmix >2→2 na wejściu (konwerter to robi — zmierzone), z zapisem odstępstwa od „bit w bit".

## 3. Wymagania 🔴/🆕 bez zadania/testu

### 3.1 Drugi tryb awarii bramki — przesłuch — bez realizacji i bez testu
- Wymagania (70–72): „🆕 🔴 Bramka mowy per kanał przed ASR. Dwa osobne tryby awarii… przesłuch z głośników → urywki cudzych zdań (52 z 53 ≤3 słowa)."
- Lekcja (1092–1093): „Przesłuch → **odrzuć segment skorelowany z drugim kanałem**."
- Stan: bramka w C jest wyłącznie energetyczna (spec §6.3, 2056–2075); jedyna implementacja korelacji to `AudioFit` (pomiar dla sond T1/T3, 4365+) i test syntetyczny (4448); żaden moduł nie odrzuca segmentów skorelowanych, automatycznego testu brak, a sprzętowy T3 (1526) dotyczy tylko `mic_aec`.
- Ryzyko wraca w całości, gdy `mic_aec` niedostępny/padnie (4.2) i runner cofa się do `mic_raw`.
- Do decyzji: próg korelacji w potoku (oba kanały są i tak w pamięci runnera) + mutacja, albo jedno świadome zdanie w specu, że faza 1 opiera się wyłącznie na AEC.

### 3.2 „>80 min" bez obowiązkowego testu; sprawdzenie w C5 jest słabe
- Wymagania (75–76): „(…) ⚠️ musi działać na plikach >80 min; testowe nagrania miały 85 minut."
- Realizacja: A10 krok 7 „(opcjonalnie…)" (5297); C5 krok 5 „**Jeśli** jest plik ≥ 85 min (…)" (7603); krok 6 „najdłuższej dostępnej" (7605). Bez korpusu wymaganie zostaje niesprawdzone.
- Asercja C5 kroku 5 (`jq '[.utterances[].start] | . == sort'`) bada tylko niemalejące początki, a `Merger` i tak sortuje (7373) — nie łapie przerw/nakładek na granicach okien.
- Sugestia: obowiązkowy deterministyczny fixture 85 min przez `session-from-file` (C4) + stub ASR w testach C3: pokrycie regionów, `end ≤ next start`, brak dziur między oknami; pomiar pamięci na sprzęcie zostaje w C5.

### 3.3 Brak sprawdzenia, że dźwięk z Teamsa trafił do nagrania
- Wymagania §7 mówią, że tap złapie ścieżkę Teamsa (MListLoopback) jak każde inne urządzenie; w D3 kroki sprawdzają okno/fokus, ale nie ma kroku, który po nagraniu z rozmowy Teams asertuje zawartość `system.caf` (np. RMS > progu). Sugestia: jeden dodatkowy krok w D3.

### 3.4 W§2: „rozmiar" i „Multilingual" bez pokrycia
- Wymagania (91–93): „🆕 Wybrany wariant modelu widoczny w UI — nazwa, **rozmiar**, znacznik „**Multilingual**", przycisk testu."
- Plan daje nazwę ✔, przycisk testu ✔, klasę języka (4 znaczniki); **rozmiaru i znacznika Multilingual nie ma** i nie ma zadania, skąd je wziąć. Do decyzji: zrobić (tabela znanych modeli? metadane OpenRouter?) albo zawęzić wymaganie.

### 3.5 P12 tylko strukturalnie
- Przegląd sam przyznaje (2411): „Testu «edytuj preset po przebiegu» nie ma". Sugestia taniego testu + mutacji: edycja presetu po przebiegu nie zmienia `run.json`; kolejny przebieg dostaje nową migawkę.

### 3.6 „Zamknięcie okna rozmowy" nie istnieje w żadnej fazie
- Wymagania (69): warunki mechaniczne końca to m.in. „zamknięcie okna rozmowy". Cisza ✔ (faza 1), kalendarz — faza 3 (zadeklarowane); „zamknięcie okna" nie pojawia się w planach żadnej fazy. Do decyzji: dopisać do fazy 3 albo wykreślić.

## 4. Scenariusze z życia, których testy nie łapią

### 4.1 Preset przełączony w trakcie nagrania zmienia transkrypcję po fakcie
- `startRecording` (7957–7969): przy zakończeniu nagrania czyta **bieżący** `activePreset`; `RecordingRow` pokazuje nazwę presetu na żywo (8217 — wiązanie do `model.activePreset`); panel nie pokazuje nic (1.1).
- Scenariusz: zmiana chipu PL→EN w trakcie spotkania → po Stop auto-transkrypcja poleci EN, bez sygnału — to klasa ryzyka opisana we specu samym (1905).
- Fix: zamrozić preset (id) w chwili startu i użyć zamrożonego; pokazywać go w panelu/wierszu.

### 4.2 Śmierć `mic_aec` (zmiana wejścia) + bezwarunkowa preferencja AEC w runnerze
- Brak obserwatora przy źródle AEC (1.2): po zmianie domyślnego wejścia silnik z voice processing przestaje dostarczać bufory i nikt go nie restartuje; konwerter nie jest odtwarzany (komentarz przy 5015 tego nie rozstrzyga — „wymaga sondy" na sprzęcie).
- Runner: `tracks(in:)` (7423–7428) preferuje `mic_aec`, gdy tylko istnieje w podsumowaniu (filtr `channels > 0` dotyczy otwarcia ścieżki, nie ramek); **brak fallbacku na `mic_raw` przy zerowych ramkach/`track.failed`**.
- Skutek: „Me" ginie do końca sesji, UI milczy (4.3).
- Fix: (a) restart silnika AEC przy zmianie konfiguracji; (b) `mic_aec` tylko gdy ma ramki i brak `track.failed`, inaczej `mic_raw`; (c) widoczność w UI.

### 4.3 Ciche awarie są niewidoczne: „85 minut niczego, wygląda na zdrową"
- `EndReason` z nagrania jest ignorowany w aplikacji (7959–7964: `{ [weak self] _ in … }`); `lastEndReason` zapisywany, **nigdzie nieczytany** (8024/8057).
- `SessionRow` (8304–8318) pokazuje tylko: postęp / „Recovered" / flagi języka / „Transcript ready" / „Not transcribed" — **brak `track.failed`, `trackPermissionDenied`, ścieżki z zerowymi ramkami**.
- Setup przy starcie pyta tylko o mikrofon (7845) — brak dźwięku systemowego nie pokaże setupu ani ostrzeżenia.
- Skutek: odmowa/mutacja dźwięku systemowego → spotkanie bez „Them" → lista pokaże „Transcript ready" z samego mikrofonu. To ich własne lekcje (1536, 1792).
- Fix: pokazać failed/permissionDenied/endReason w wierszu i szczegółach; stan dźwięku systemowego w gating setupu.

### 4.4 Uśpienie/awaria urządzenia kończy sesję po cichu (stall 30 s), bez wznowienia
- Standardowe warunki zawierają `StallCondition(seconds: 30)` (4089): po uśpieniu ekranu/śmierci urządzenia sesja kończy się powodem, którego UI nie pokazuje (4.3), a wznowienia nie ma. „Wymaga sondy": zachowanie przy `sleep` (domknięcie journala i ścieżek). Minimum: widoczny powód końca.

### 4.5 „Recovered" na sesji, która właśnie się nagrywa (drobne)
- Po starcie aplikacja woła `reloadSessions()` (7966); dopóki nie ma `session.ended`, `crashed == true` → wiersz pokazuje „Recovered" (8307–8308) w trakcie nagrywania. Fix: sprawdzać aktywność nagrania w statusie.

### 4.6 Ponowna transkrypcja płaci drugi raz; wznawianie istnieje tylko w CLI
- `transcribe` tworzy **nowy** `runID` przy każdym wywołaniu (7983); cache okien (P5) jest per-run → po częściowej awarii/przerwaniu klik w „Transcribe" płaci za wszystkie okna ponownie. Wznawianie działa tylko przez CLI z tym samym `--run` (C3/C4). Fix produktowy: wykrywać przebieg bez `transcript.json` i wznawiać z tym samym `runID` (albo „Resume").

### 4.7 T1: referencja z `say` to 22050 Hz — przy R²<0,999 najpierw łańcuch, nie tap
- Zmierzone: `say -v Zosia` daje AIFC 1 ch, **22050 Hz**, 16-bit BE; `system.caf` to 48 kHz; `fit` przepróbkowuje liniowo. Różne łańcuchy mogą zbić R² poniżej 0,999 przy poprawnym tapie. `say --data-format` nie działa (sprawdzone); `afconvert -f WAVE -d LEI16@48000 -c 1` daje 48 kHz (sprawdzone). Sugestia: w T1 użyć referencji 48 kHz albo przy nieudanym progu najpierw powtórzyć na 48 kHz, zanim uzna się tap za wadliwy.

### 4.8 „Test dźwięku systemowego" w trakcie nagrania
- `SystemAudioCheck.run` gra ton przez silnik aplikacji (5075–5087) — klik „Test" podczas nagrywania wprowadza ton do nagrania; obok tapu nagrania powstaje drugi tap (współistnienie — „wymaga sondy"). Fix: zablokować albo ostrzec przy aktywnym nagraniu.

## Aneks: surowe dowody z tej maszyny

```
$ bash scripts/test.sh   (scratchpad/mn)
test.sh: 83/83 testów uruchomionych i zaliczonych.        EXIT=0

$ swiftc -typecheck sdk_probe.swift     # wywołania planu verbatim
warning: installTap(...) deprecated in macOS 27.0
TYPECHECK_EXIT=0

$ ./convprobe5
AVAudioChannelLayout mono/stereo/5.1A/7.1A: OK
float 6 / int16 6 via commonFormat+channelLayout: OK (non-failable), ch=6
streamDescription+channelLayout: OK
A int16x6 -> float mono 16k (downmix): status=0 outFrames=1611
B floatx6 -> int16x2:                   status=0 outFrames=4800
C floatx6 -> int16x6:                   converter OK
D int16 6 via channels-init:            NIL        ← konstrukcja z planu

$ say -v Zosia -o z.aiff && afinfo z.aiff
Data format: 1 ch, 22050 Hz, lpcm, 16-bit big-endian (AIFC)

$ grep: DeviceWatcher — użycia: 4838 (wyjście), 4955 (wejście); klasa 4793; brak w mic_aec
$ lastEndReason: 8024 (deklaracja), 8057 (zapis) — brak odczytów
$ ProvidersFile: definicja 6323 (B3); użycie w teście B1 na 5496
$ Merger: `utterances.sort { $0.start < $1.start }` na 7373 — asercja C5 jest przez to pusta
```

**Uwaga recenzencka:** literały testowe mają kształt kluczy (`sk-or-…`). Część narzędzi pokazuje je w wynikach zamaskowane (np. jako `sk-or-...T123` albo `«redacted:sk-…»`) — cytaty i odsyłacze w tej recenzji były weryfikowane kodami znaków; na wyniki suite'u to nie wpływa.

**Czego nie da się rozstrzygnąć bez sprzętu (sondy do wykonania):** `streamDescription:` na prawdziwym urządzeniu >2-kanałowym (2.6); zachowanie `mic_aec` przy zmianie wejścia (4.2); współistnienie dwóch tapów (4.8); zachowanie przy `sleep` (4.4).
