# S5 — poprawka po sondzie S2: AEC wykłada `mic_raw` i głodzi tap

Gałąź `faza1`, baza `b744bbe`. Testy: `scripts/test.sh` → 53/53. **Nowych @Test brak.**

## Objaw (z dzienników)

- `/tmp/mn-s2`, `/tmp/mn-s2-r2` (tryb domyślny): `system` 0 ramek; `mic_raw` 0 ramek i
  `track.failed coreAudio("StreamFormat", 0)` kilka ms po `track.opened mic_aec`; `mic_aec` działa;
  inne audio ściszone na czas nagrania.
- `/tmp/mn-s2nr` (`--no-aec`): wszystko działa.

Kolejność w `SessionRecorder.start()`: najpierw `prepare()` wszystkich źródeł (tap tworzy tu
urządzenie zbiorcze, `mic_aec` włącza `setVoiceProcessingEnabled(true)`), potem `start()` po kolei.
Awaria `mic_raw` jest z `start()` (powód bez przedrostka `reopen:`), czyli już po włączeniu VP.

## Przyczyna (dowody: sondy właściwości Core Audio, bez startu IO i bez nagrywania)

Sama zmiana `setVoiceProcessingEnabled(true)` (bez `engine.start()`) przebudowuje urządzenia:

| | przed VP | po VP |
|---|---|---|
| mikrofon MacBooka, `kAudioDevicePropertyStreamFormat` (wejście) | 1 kan., 48 kHz, Float32 → `AVAudioFormat` OK | **3 kan.**, 48 kHz, Float32 → `AVAudioFormat(streamDescription:)` = **nil** |
| głośniki MacBooka, kanały wejściowe | 0 | **4** (referencja echa) |
| urządzenie zbiorcze tapu (podurządzenie: głośniki), bufory wejścia | `[2]` | **`[4, 2]`** — nowy strumień głośników przed tapem |
| nowe urządzenia | — | `VPAUAggregateAudioDevice-…`, `CADefaultDeviceAggregate-…` (7 wej./2 wyj.) |

1. **`mic_raw`:** `CoreAudioDevices.inputFormat` robił `AVAudioFormat(streamDescription:)`, które
   dla > 2 kanałów bez układu kanałów zwraca nil. Status Core Audio był `0` (odczyt się udał),
   stąd dokładnie `coreAudio("StreamFormat", 0)`. Kandydat (a) z zadania trafił w miejsce, ale nie
   w mechanizm: 16 kHz nie jest forsowane na urządzeniu (HALCapture zawsze konwertował z natywnego).
2. **tap (`system`):** VP dokłada głośnikom 4 kanały wejściowe, więc urządzenie zbiorcze tapu
   wystawia teraz dwa strumienie `[4, 2]`. `HALCapture` budował
   `AVAudioPCMBuffer(pcmFormat: 2 kan., bufferListNoCopy: całaLista)` → nil → `return` **bez
   żadnego zgłoszenia**. Stąd 0 ramek i brak `track.failed` przez 30 s.
3. Dodatkowo (sonda offline): `AVAudioConverter` z `downmix = true` z 3 kanałów dyskretnych do mono
   daje **ciszę** (0.5 w kanale 0 → próbka 0); `channelMap = [0]` → 16384 (poprawnie).

## Zmiana

- `CoreAudioDevices.format(_:)` — jedno miejsce budowy `AVAudioFormat`; dla > 2 kanałów dokłada
  układ `DiscreteInOrder`. Używane przez `inputFormat` i `tapFormat`.
- `FormatConverter` — wejście > 2 kanałów: `channelMap` na pierwsze kanały (zamiast `downmix`,
  który daje ciszę). 1–2 kanały bez zmian.
- `HALCapture` — IOProc bierze **ostatni** strumień z listy buforów (tap idzie po podurządzeniach;
  dla mikrofonu to jedyny strumień, więc zachowanie bez VP bez zmian) i gdy liczba kanałów strumienia
  różni się od formatu, przebudowuje format i konwerter pod działającym IOProc. Bufor, którego
  nie da się dopasować, zgłasza raz `.failed` zamiast znikać po cichu.
- `--no-aec`: lista buforów `[2]` / `[1]`, formaty ≤ 2 kanały, więc ścieżka ta sama co dotąd.

Pominięte: format nieprzeplatany w IOProc (HAL i tap wystawiają przeplatany; oznaczone `ponytail:`),
zdarzenie w dzienniku przy zmianie liczby kanałów (brak typu zdarzenia; dodać, jeśli sonda pokaże potrzebę).

Nie zweryfikowane na sprzęcie (proces nie ma uprawnień): ile kanałów IOProc mikrofonu faktycznie
poda pod VP. `kAudioDevicePropertyStreamFormat` mówi 3, `kAudioDevicePropertyStreamConfiguration`
mówi `[1]`. Kod działa w obu wariantach (adaptacja do liczby kanałów w buforze).

## Ducking — nie da się wyłączyć na macOS (decyzja użytkownika)

Sprawdzone w nagłówkach SDK:

- `kAUVoiceIOProperty_DuckNonVoiceAudio` (`AudioUnitProperties.h`) jest w `#if TARGET_OS_IPHONE`,
  `API_DEPRECATED("not longer supported", ios(3.0, 7.0)) API_UNAVAILABLE(macos)`. Na macOS nie istnieje.
- `kAUVoiceIOProperty_OtherAudioDuckingConfiguration` / `AVAudioInputNode.voiceProcessingOtherAudioDuckingConfiguration`
  (macOS 14+): poziomy wyłącznie `Default=0, Min=10, Mid=20, Max=30`. **Nie ma poziomu „wyłączony".**
  Kod już ustawia `Min` bez advanced ducking. Odczyt zwrotny po ustawieniu: `enableAdvancedDucking=false, level=10`.

Ducking działa tylko, póki działa jednostka VP (dziennik S2: po nagraniu głośność wraca), więc wymóg
„po nagraniu inna muzyka nie jest ściszona" jest spełniony. Wymóg „w trakcie bez ściszenia" przy
AEC na żywo spełnić się nie da. Opcje do decyzji:

1. Zostawić `Min` (obecnie).
2. Spróbować `enableAdvancedDucking: true` + `Min`. Wg dokumentacji ścisza wtedy tylko przy aktywności
   głosowej, a nie stale. Wymaga sondy uchem, niesprawdzone.
3. Domyślnie bez AEC na żywo (`--no-aec` jako domyślne), a AEC offline na plikach. To zmiana architektury.

## Proponowany test (NIE dodany — przesuwa liczby w planach, do decyzji)

`FormatConverter`: 3 kanały Float32 48 kHz (układ `DiscreteInOrder|3`, wzór `CoreAudioDevices.format`)
→ mono Int16 16 kHz; kanał 0 = 0.5, reszta 0 → próbki ≈ 16384, a nie 0. Ten test łapie regresję pkt 3.

## Weryfikacja na sprzęcie (użytkownik)

Głośniki, nie słuchawki; w tle mowa z YouTube'a.

```sh
swift build -c release --product meetnotes-cli
B=$(swift build -c release --show-bin-path)/meetnotes-cli
rm -rf /tmp/mn-s5
$B record /tmp/mn-s5 --seconds 30          # tryb domyślny: system + mic_raw + mic_aec
$B summarize /tmp/mn-s5                    # oczekiwane: ramki > 0 na KAŻDEJ ścieżce, brak track.failed
grep -c failed /tmp/mn-s5/journal.jsonl    # oczekiwane: 0
$B fit /tmp/mn-s5/system.caf /tmp/mn-s5/mic_raw.caf   # korelacja wyraźnie > 0,12 (echo w surowym)
$B fit /tmp/mn-s5/system.caf /tmp/mn-s5/mic_aec.caf   # korelacja ≤ 0,12 (T3)
afplay /tmp/mn-s5/mic_raw.caf              # słychać pokój/echo, nie ciszę
# regresja --no-aec:
rm -rf /tmp/mn-s5nr && $B record /tmp/mn-s5nr --seconds 30 --no-aec && $B summarize /tmp/mn-s5nr
```

Jeśli `system` nadal ma 0 ramek, a w dzienniku jest `track.failed "buffer list does not match …"`
albo `"cannot adapt …"`, to hipoteza „tap to ostatni strumień" jest fałszywa. Taki wynik
wraca do mnie z dziennikiem.

## Runda 2 — advanced ducking (eksperyment)

Decyzja użytkownika z 2026-09-29: ściszenie innych aplikacji w trakcie nagrania nadal słychać, więc
próbujemy opcji 2 z sekcji „Ducking".

**Co zmienione.** Tylko jedna linia, `Sources/MeetNotesRecording/MicrophoneSources.swift:87` w
`VoiceProcessedMicrophoneSource.prepare()`: `enableAdvancedDucking: false` → `true`. Poziom nadal
`.min`. Nic więcej nie ruszone, w tym tor `mic_raw` (osobne zlecenie). Plan
`2026-09-24-faza1-01-fundament-i-nagrywanie.md:2557` nadal ma `false`. Świadomie go nie zmieniam,
bo to eksperyment. Po sondzie trzeba albo poprawić plan, albo cofnąć zmianę w kodzie.

**Co mówi SDK** (`AVFAudio/AVAudioIONode.h:83–95, 259–267`; `AudioToolbox/AudioUnitProperties.h:2682–2725`):

- `enableAdvancedDucking`: „Enables advanced ducking which ducks other audio based on the presence
  of voice activity from local and/or remote chat participants". Ściszanie jest więc sterowane
  aktywnością głosową, i to zarówno lokalnego mówcy (mikrofon), jak i zdalnych uczestników.
  Nagłówek nie mówi wprost, że bez głosu ściszenia nie ma wcale, ani czym jest „zdalny uczestnik"
  dla jednostki VP (prawdopodobnie sygnał odtwarzany przez jej wyjście). **Nie wiadomo więc, czy
  głos z Teams odtwarzany przez system też wyzwala ściszenie.** To ma rozstrzygnąć sonda.
- Poziomy bez zmian: `Default=0, Min=10, Mid=20, Max=30`. Poziomu „wyłączony" nie ma.
- Brak dodatkowych wymagań i właściwości. Struktura ma tylko dwa pola, dostępność macOS 14+
  (spełniona, cel `macos14.0`). Domyślnie advanced jest wyłączony, poziom `Default`.

**Odczyt zwrotny** (skrypt `/tmp/duck-readback.swift`: `setVoiceProcessingEnabled(true)`, ustawienie
konfiguracji, odczyt; bez `engine.start` i bez tapu, więc nic nie nagrano):
`enableAdvancedDucking=true, level=10`. System przyjął wartość.

**Testy:** `scripts/test.sh` → 53/53. Testy nie pokrywają duckingu, bo to zachowanie sprzętowe.

**Co ma ocenić użytkownik (sonda uchem).** Muzyka z innej aplikacji (np. Spotify/YouTube) gra na
stałej, znanej głośności przez cały czas.

```sh
B=$(swift build -c release --show-bin-path)/meetnotes-cli   # jak w rundzie 1
rm -rf /tmp/mn-duck && $B record /tmp/mn-duck --seconds 60
```

W trakcie 60 s:
1. **0–20 s: cisza w pokoju, nie mów.** Czy muzyka jest ściszona względem stanu sprzed startu?
   Oczekiwanie przy advanced: nie, albo wyraźnie mniej niż w rundzie 1.
2. **20–40 s: mów ciągle do mikrofonu.** Czy muzyka ścisza się, gdy mówisz, i wraca w pauzach?
3. **40–60 s: puść w drugiej aplikacji nagranie mowy (np. podcast/Teams) obok muzyki, sam milcz.**
   Czy muzyka ścisza się od głosu odtwarzanego przez system?
4. Po zakończeniu: czy głośność wraca do normy (jak w S2)?

Zapisz wynik jako trzy odpowiedzi tak/nie (1–3) plus pkt 4. Decyzja:
- **1 = nie ściszona** → zostawić advanced, poprawić plan (`:2557`).
- **1 = ściszona jak wcześniej** → advanced nic nie daje. Wrócić do `false` (albo zostawić, bo jest
  neutralny) i rozważyć opcję 3 (`--no-aec` domyślnie, AEC offline).
- **3 = ściszona** → w realnym spotkaniu Teams ściszenie będzie praktycznie ciągłe (ktoś zawsze
  mówi), więc advanced nie rozwiązuje problemu dla kanału systemowego.

## Runda 3 — mic_raw pod VP

Baza `70193e6`. Testy: `scripts/test.sh` → **54/54. Dodany 1 nowy @Test**
(`mixesMicArrayChannelsWithGain` w `FormatConverterTests.swift`). Plany są wyrównane do 53, więc
przesunięcie liczb w planach to osobna decyzja użytkownika.

**Objaw.** Ten sam głos i ta sama sesja: `--no-aec` daje `mic_raw` RMS −22,0 dBFS, a tryb domyślny
−57,3 dBFS. Różnica to ok. 35 dB.

**Przyczyna.** Pod VP wbudowany mikrofon nie wystawia już swojego zwykłego toru. Wystawia
**surowe kapsuły macierzy mikrofonów**, bez beamformingu i bez DSP/wzmocnienia sterownika.
Tor raw brał z nich kanał 0, czyli jedną kapsułę przed całym wzmocnieniem.

Dowody pochodzą z sondy `/tmp/vp-chan-probe.swift`. Robi tylko `setVoiceProcessingEnabled(true)`
i odczyt właściwości, bez IO i bez nagrywania. Sprzęt: `Mac16,12` (MacBook Air M4, macierz 3 mikrofonów).

| mikrofon MacBooka (id 91) | przed VP | po VP |
|---|---|---|
| `StreamFormat` (wejście) | 1 kan. | 3 kan. |
| `StreamConfiguration` (wejście) | `[1]` | **`[3]`** (w rundzie 1 odczyt dał `[1]`, teraz obie właściwości się zgadzają) |
| strumień 92: format **fizyczny** i wirtualny | 1 kan. | **3 kan.** (zmienia się tryb sprzętu, to nie jest przemapowanie) |
| nazwy elementów 1…n | `1` | `1`, `2`, `3` (same numery, brak etykiet) |
| `PreferredChannelLayout` | tag 0, etykiety `Unknown` | tag 0, 3× `Unknown` |
| głośność wejścia (master, jedyna kontrolka `vlme`) | 0,941 / **+10,6 dB** | 0,941 / **+10,6 dB** |
| głośność per kanał | brak | brak |
| `AVAudioInputNode` format | — | 7 kan. (3 mikrofony + 4 referencje głośników) |

Wniosek: suwak głośności wejścia jest taki sam w obu trybach, więc różnica nie bierze się
z ustawień wzmocnienia OS. Liczba kanałów (3) odpowiada liczbie kapsuł, a format fizyczny też
się zmienia. VP zabiera więc urządzenie w tryb surowej macierzy, bo sam robi beamforming, AEC i AGC
(stąd `mic_aec` ma poziom normalny, −26 dBFS). Toru „1 kanał po DSP" pod VP nie da się otworzyć:
urządzenia zbiorcze VP (`VPAUAggregate…`, `CADefaultDeviceAggregate…`) mają `[3, 4]`, czyli te same
3 kapsuły. Dlatego sam wybór kanału nie odzyska 35 dB. Każdy kanał to kapsuła bez wzmocnienia.

**Zmiana.**
- `HALCapture` dostaje opcjonalne `arrayGain`. Przekazuje je tylko `RawMicrophoneSource`, tap
  nie dostaje nic. Gdy bufor ma > 2 kanały, `mixArray` liczy średnią kanałów × wzmocnienie,
  obciętą do ±1, a konwerter dostaje mono Float32. Średnia utrzymuje poziom jednej kapsuły, więc
  kalibracja zmierzona na kanale 0 pozostaje ważna, a nieskorelowany szum kapsuł spada o ok. 4,8 dB.
  Nie ma znaczenia, która kapsuła jest „najlepsza".
- `RawMicrophoneSource.arrayGainDB = 35`. To gałka kalibracyjna ustawiona z pomiaru
  `mn-mic-a` vs `mn-mic-b`. Oznaczona `ponytail:`: zmierzona na jednym MacBooku Air, na innym
  sprzęcie potrzebna nowa sonda.
- `FormatConverter` **bez zmian** w logice (dodane tylko `recordFailure()`). Jego ścieżka
  `channelMap` dla > 2 kanałów obsługuje też `mic_aec` (węzeł VP ma 7 kanałów, kanał 0 to wyjście VP),
  więc zmiana tam zepsułaby `mic_aec`.
- `--no-aec` bez zmian: mikrofon ma 1 kanał, a miks włącza się tylko przy > 2. Tap ma 2 kanały
  i nie dostaje `arrayGain`.

Pominięte: AGC/normalizacja w locie. Tor ma zostać surowy, a stałe wzmocnienie jest liniowe
i odwracalne. Dodać, jeśli sonda pokaże duży rozrzut między sesjami.
Ryzyko: przy bardzo bliskiej mowie +35 dB może obcinać. W `--no-aec` peak też był 0,0 dBFS,
więc zachowanie jest porównywalne, zgodnie z poleceniem, by na razie tego nie ruszać.

**Weryfikacja na sprzęcie (użytkownik).** Cisza w pokoju, ten sam tekst, ta sama odległość co w `mn-mic-a/b`.

```sh
swift build -c release --product meetnotes-cli
B=$(swift build -c release --show-bin-path)/meetnotes-cli
rm -rf /tmp/mn-mic-c && $B record /tmp/mn-mic-c --seconds 30            # tryb domyślny, mowa w 0–15 s
$B summarize /tmp/mn-mic-c        # oczekiwane: mic_raw RMS ≈ −20…−30 dBFS (było −57,3); brak track.failed
rm -rf /tmp/mn-mic-d && $B record /tmp/mn-mic-d --seconds 30 --no-aec   # regresja: ≈ −22 dBFS jak mn-mic-a
$B summarize /tmp/mn-mic-d
$B fit /tmp/mn-mic-c/mic_aec.caf /tmp/mn-mic-c/mic_raw.caf              # korelacja wyraźnie > 0; współczynnik a ≈ 1 zamiast 15×
afplay /tmp/mn-mic-c/mic_raw.caf  # słychać normalny głos, bez przesteru
```

Jak czytać wynik: jeśli `mic_raw` (c) różni się od (d) o więcej niż ok. 5 dB, trzeba skorygować
`arrayGainDB` o tę różnicę. Wzmocnienie jest liniowe, więc to jedna liczba. Jeśli słychać
przester albo zniekształcenia fazowe (średnia kapsuł na wysokich częstotliwościach), wynik wraca
do mnie. Wtedy alternatywą jest sam kanał 0 × 35 dB.

## Runda 4 — opcja B wdrożona (decyzja użytkownika)

Źródło: `S5-ducking-konsultacja.md`, gdzie rekomendacja brzmiała „B teraz, C później". Decyzja użytkownika: „robimy tak jak mówi Opus". Bez nagrywania dźwięku.

### Zmiany plik po pliku

- `Sources/MeetNotesRecording/MicrophoneSources.swift`: eksperyment z rundy 2 jest cofnięty (`enableAdvancedDucking: false`, poziom `.min` zostaje; zgodnie z plan01:2557). W komentarzu klasy dopisane: minimum nadal ścisza, dlatego tor jest opcją `--aec`.
- `Sources/meetnotes-cli/CLI.swift`: `record` bez flagi nagrywa `system` + `mic_raw`. `VoiceProcessedMicrophoneSource` powstaje tylko z `--aec`. `--no-aec` nadal jest akceptowane i równa się domyślnemu (plany i runbook go używają). Usage pokazuje `[--aec]`.
- `SessionRecorder` / rdzeń: bez zmian, bo źródła przychodzą z zewnątrz, a jedynym miejscem, które tworzyło tor AEC, był CLI. Powrót do `mic_raw`: `TranscriptionRunner` jeszcze nie istnieje w kodzie. W planie `tracks(in:)` bierze `mic_aec`, a jeśli go nie ma, `mic_raw` (plan 05, poprawka E3 i test `["system", "mic_raw"]`). Sesja bez `mic_aec` trafi więc na `mic_raw` bez żadnej dodatkowej zmiany.
- `arrayGainDB` (35 dB): bez zmian. `HALCapture.converterInput` włącza miks kapsuł tylko przy >2 kanałach wejścia, czyli pod VP. Bez `--aec` gałka nie działa.
- `docs/superpowers/specs/2026-09-24-rdzen-nagrywania-design.md`: pod tabelą §2 i przy T3 dopisane korekty ✏️ z datą 2026-09-29 i odwołaniem do konsultacji/sondy. Treść: domyślnie bez VP, `mic_aec` opt-in (`--aec`) ze stałym ściszaniem, AEC offline (`mic_raw` + `system`) po planie 05. Runbook nie jest ruszany (przełącznik w Ustawieniach zrobi R5 b).

### Testy

`scripts/test.sh`: 54/54. Żaden istniejący test nie zakładał domyślnego AEC. Test `SessionRecorderTests.swift:266` używa `mic_aec` tylko jako nazwy pompy. Nowych `@Test` nie dodano.

### Do sprawdzenia przez użytkownika

1. Świeży build: `swift build`.
2. `meetnotes-cli record <katalog>` bez flagi, z muzyką w tle: w katalogu są dwie ścieżki (`system.caf`, `mic_raw.caf`), nie ma `mic_aec.caf`, a muzyka **nie cichnie** w trakcie nagrania.
3. `meetnotes-cli record <katalog> --aec`: trzy ścieżki, muzyka ściszona przez całe nagranie. To znane ograniczenie trybu opt-in.
