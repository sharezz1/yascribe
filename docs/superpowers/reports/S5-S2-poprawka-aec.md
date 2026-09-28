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
