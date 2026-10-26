# S5 — konsultacja: ducking innych aplikacji przy żywym AEC

Gałąź `faza1`, HEAD `9f6a6e3`. To konsultacja: kod bez zmian, bez nagrywania, bez commitu.
Dane wejściowe: sonda użytkownika (advanced = true, poziom `Min`). Ściszenie trwa od startu do końca
nagrania, niezależnie od tego, czy ktoś mówi. Po nagraniu głośność wraca.

## (a) Werdykt

**Przy żywym AEC platformowym (`mic_aec`) nie da się tego wyłączyć** żadnym publicznym ani
znalezionym środkiem. Ściszenie jest skutkiem działania jednostki VP, a nie opcją, którą
da się wyłączyć. Jedynym sposobem, żeby go nie było, jest nie uruchamiać VP w trakcie nagrania.

Poprawka do interpretacji sondy: wniosek „głos z systemu też je wyzwala” jest za mocny. Muzyka była
ściszona już w 0–20 s, bez żadnego głosu, więc advanced ducking na tym sprzęcie nie ma **żadnego
widocznego efektu** i ściszenie jest po prostu stałe. Wniosek praktyczny się nie zmienia.

## Kąty sprawdzone

### 1. Właściwości VP (nagłówki SDK + sonda)

Publiczne właściwości (`AudioUnitProperties.h:2620–2760`, `AVAudioIONode.h:135–267`):

| właściwość | co robi | czy pomaga |
|---|---|---|
| `BypassVoiceProcessing` (2100) / `voiceProcessingBypassed` | wyłącza przetwarzanie **toru mikrofonu** | nie: zabija AEC, a jednostka VP dalej działa, więc ducking zostaje (dokumentacja łączy ducking z samą sesją VP, nie z torem up-link) |
| `VoiceProcessingEnableAGC` (2101) | AGC | nie |
| `MuteOutput` (2104), `MutedSpeechActivityEventListener` (2106) | wyciszenie up-linku / VAD | nie |
| `OtherAudioDuckingConfiguration` (2108) | advanced + poziom `0/10/20/30` | **brak poziomu „off”**; sonda: `Min` + advanced = ciągłe ściszenie |
| `DuckNonVoiceAudio` (2102) | jedyny przełącznik off | tylko iOS, wycofany w iOS 7, `API_UNAVAILABLE(macos)`; w nagłówku wprost: „In the future, ducking will always be on” |
| `VoiceProcessingQuality` (2103) | jakość | wycofany od macOS 10.9 |

Sonda `/tmp/vpscan/scan.swift`: `AudioComponentInstanceNew(VoiceProcessingIO)` + `AudioUnitGetPropertyInfo`
dla ID 2000–2200, **bez `Initialize`/`Start`, więc nic nie otwarto ani nie nagrano**. Jednostka
obsługuje dodatkowo **nieudokumentowane** ID: 2105 (132 B), 2110–2113, 2115, 2116, 2118–2123, 2125–2128,
2130–2132, 2134–2137. Wartości domyślne to w większości 0. Nazw i semantyki nie znamy. Szukanie „na ślepo”
(zapis 1 do każdej i odsłuch) jest technicznie możliwe, ale **odradzam**: to prywatne API bez gwarancji,
może zmienić znaczenie w każdej wersji macOS, a każdy krok wymaga sondy uchem na sprzęcie. W sieci
(wątek Apple Developer Forums 664346, 2020–2023) problem jest znany i nie ma rozwiązania.

### 2. `AVAudioEngine.voiceProcessingEnabled` a bezpośrednie `kAudioUnitSubType_VoiceProcessingIO`

To ta sama jednostka. Węzeł wejścia silnika opakowuje AUVoiceIO (`AVAudioIONode.audioUnit`), a
właściwości 2100–2108 są te same. Bezpośrednia jednostka daje tylko dostęp do prywatnych ID z pkt 1
i wybór urządzeń (`CurrentDevice`). **Nie zmienia duckingu.**

### 3. Kontekst urządzeń

- **Inne urządzenie wyjściowe dla VP** (np. wirtualne), żeby ducking „trafił obok”: bez sensu. Referencja
  echa to pętla zwrotna urządzenia wyjściowego (runda 1: głośniki dostają 4 kanały wejściowe).
  Jeśli Teams gra na innym urządzeniu niż VP, AEC nie widzi jego sygnału i nie działa.
- **Agregaty**: VP i tak tworzy własne (`VPAUAggregate…`, `CADefaultDeviceAggregate…`). Nie mamy wpływu
  na politykę duckingu w `coreaudiod`.
- **Tryb mikrofonu (Standard / Voice Isolation / Wide Spectrum)**: `AVCaptureDevice.preferredMicrophoneMode`
  jest tylko do odczytu, a ustawia go użytkownik w Centrum sterowania. Dotyczy up-linku, nie duckingu.
  Nagłówek mówi tylko, że Voice Isolation i Wide Spectrum mają pierwszeństwo przed Bypass.
- **Słuchawki**: echa brak, więc AEC niepotrzebny. Ducking i tak by był, gdyby VP działał.

### 4. Własny AEC

Mamy już wszystko, czego potrzebuje AEC z referencją: `mic_raw` (w `--no-aec` to normalny tor 1 kan.
po DSP sterownika), `system` z tapu (dokładnie to, co idzie do głośników) oraz wspólną oś czasu
(`Timebase`, kotwice zegara). `docs/plan.md:54` przewidział to wprost: surowy mikrofon archiwizujemy po to,
żeby AEC dało się powtórzyć offline z kanałem systemowym jako odniesieniem.

| wariant | trudność | uwagi |
|---|---|---|
| **Offline AEC na (`mic_raw`, `system`)** po nagraniu, przed ASR | średnia | Transkrypcja (plan C) i tak czyta pliki po sesji, więc „na żywo” nic nie daje. Kandydaci: **SpeexDSP** `speex_echo` (C, BSD, kilka plików, łatwo zwendorować przez SwiftPM) albo **WebRTC AEC3** (lepszy przy double-talk i nieliniowościach, ale duży C++ z zależnościami, więc realnie kilka dni integracji). Offline wolno zrobić to, czego żywy AEC nie może: najpierw wyrównać opóźnienie korelacją (`AudioFit` już to liczy), potem filtrować. Ryzyka: nieliniowość małych głośników MacBooka (Speex radzi sobie słabiej), zmiana głośności systemu w trakcie (tap jest przed suwakiem, a filtr adaptacyjny to nadrabia). Test: istniejące T3 (`korelacja ≤ 0,12`) na wyjściu offline zamiast `mic_aec`. |
| **Sam `CrosstalkFilter`** (plan 05 E3), bez AEC | niska, już zaplanowane | Wyrzuca przed ASR fragmenty `mic` skorelowane z `system` (≥ 0,8, lag ≤ 0,3 s). Nie usuwa echa **pod** mową użytkownika (double-talk), więc cudze słowa mogą wtedy wejść do „Me”. |
| **Żywy własny AEC** (Speex/AEC3 w IOProc na `mic_raw` z tapem jako referencją) | wysoka | Dwa niezależne strumienie HAL w czasie rzeczywistym: bufor opóźnienia, dryf, praca na wątku audio, dodatkowa ścieżka awarii w rdzeniu. **Zero zysku** względem offline, bo nic nie konsumuje `mic_aec` w trakcie nagrania. Nie polecam. |

Uwaga pomiarowa: w PR screenpipe #7285 autorzy piszą, że „VPIO ducking is a confound” w pomiarze
wycieku echa. U nas może być podobnie: część niskiej korelacji `mic_aec × system` w T3 może
wynikać ze ściszenia głośników, a nie z AEC. Nie sprawdzałem, czy tap widzi dźwięk przed ściszeniem
czy po nim. Offline AEC nie ma tego problemu.

### 5. „Bez żywego AEC domyślnie” — produktowo

**Zyskujemy:** zero ściszania innych aplikacji, w tym Teams, czyli wymóg użytkownika jest spełniony.
Znika cała klasa problemów z rund 1–3: przebudowa urządzeń pod VP, 3 kapsuły zamiast toru po DSP
(`arrayGainDB = 35`), strumień `[4, 2]` w agregacie tapu, restart `mic_aec` przy zmianie wejścia.
`mic_raw` wraca do toru po DSP sterownika (−22 dBFS bez kalibracji). Mniej CPU w trakcie.

**Tracimy:** czyste „Me” przy głośnikach **do czasu offline AEC**. Echo zostaje w `mic_raw`, a
`CrosstalkFilter` łapie tylko fragmenty, w których użytkownik milczy. W słuchawkach nie tracimy nic.

**Spec:** §2 („AEC: platformowy `setVoiceProcessingEnabled`, na kopii; surowy mikrofon zawsze
zachowany”) i T3 zakładają `mic_aec`. Zmiana to **odchylenie od zamkniętej decyzji §2**, więc wymaga
✏️ korekty specu. Uzasadnienie jest mocne: dowód sprzętowy (ta sonda) plus `docs/plan.md:54`, który
przewidział offline AEC. Kod: runner (plan 03/05) już cofa się do `mic_raw`, gdy `mic_aec` brak, więc
brak `mic_aec` nie psuje potoku. Runbook R5 przewidział przełącznik „Echo cancellation copy (mic_aec)”.

### 6. Inne pomysły (odrzucone)

- **Kompensacja ściszenia** (podbijanie głośności innych aplikacji): nie ma publicznego API
  per-proces, a ściszenie robi `coreaudiod`. Odpada.
- **VP tylko w pierwszych sekundach** (kalibracja, potem wyłączenie): AEC działa tylko, gdy
  jednostka działa. Odpada.
- **VP tylko przy głośnikach, bez VP przy słuchawkach**: realna, tania optymalizacja, ale nie usuwa
  problemu tam, gdzie AEC jest potrzebne (głośniki). Warto najwyżej jako uzupełnienie opcji B.
- **Proces pomocniczy z VP**: ducking jest systemowy, więc osobny proces nic nie zmienia.

## (b) Opcje

| # | opcja | wykonalność | koszt | ściszanie |
|---|---|---|---|---|
| A | Zostawić żywy VP (`Min`) | działa | 0 | **ciągłe** przez całe nagranie |
| B | **`--no-aec` domyślnie** (tylko `system` + `mic_raw`), `mic_aec` jako opcja w Ustawieniach (runbook R5 b) | pewna | mały: domyślna wartość flagi/przełącznika, korekta specu §2 i T3, plan 05 E3 bez zmian | **brak** |
| C | B + **offline AEC** (SpeexDSP) jako krok potoku przed `CrosstalkFilter`/ASR, zapis `mic_aec_offline` w `runs/` albo obok | wysoka | średni: nowy moduł + test (T3 na pliku z syntetycznym echem, mutacja „bez filtra” → czerwień) | brak |
| C′ | jak C, ale WebRTC AEC3 | wysoka | większy: integracja C++ | brak |
| D | prywatne właściwości VP (2105, 2110+) | nieznana | wysoki, kruche | może |
| E | żywy własny AEC | średnia | wysoki | brak, ale bez zysku względem C |

## (c) Rekomendacja

**B teraz, C jako osobne zadanie po planie 05 (i tylko jeśli dane pokażą potrzebę).**

1. Faza 1: domyślnie bez VP. Nagrywamy `system` + `mic_raw`, a `mic_aec` jest opt-in („dla nagrań
   na głośnikach, kosztem ściszenia innych aplikacji”). Spec §2 i T3 dostają ✏️ korektę z odwołaniem do
   tej sondy. Gałka `arrayGainDB` zostaje, bo działa tylko pod VP, czyli w trybie opt-in.
2. `CrosstalkFilter` (E3) jest pierwszą linią obrony i tak jest już zaplanowany.
3. Po kilku realnych spotkaniach na głośnikach trzeba zmierzyć, ile cudzych słów przecieka do „Me”
   przy double-talk. Jeśli dużo, wchodzi C (SpeexDSP offline; AEC3 dopiero, gdy Speex nie wystarczy).
   Surowe pliki są w archiwum, więc AEC offline da się też zastosować wstecz do starych sesji.
4. Nie grzebać w prywatnych ID VP (D) i nie budować żywego AEC (E).

Do decyzji użytkownika: B (zmiana zamkniętej decyzji §2) i ewentualne otwarcie zadania C.
Eksperyment `enableAdvancedDucking: true` (`MicrophoneSources.swift:87`) nie daje efektu. Jeśli VP
zostaje jako opt-in, trzeba go cofnąć do `false` zgodnie z planem `:2557`.

Źródła zewnętrzne: [Apple Developer Forums 664346](https://developer.apple.com/forums/thread/664346),
[screenpipe PR #7285](https://github.com/screenpipe/screenpipe/pull/7285),
[dokumentacja `voiceProcessingOtherAudioDuckingConfiguration`](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration).
