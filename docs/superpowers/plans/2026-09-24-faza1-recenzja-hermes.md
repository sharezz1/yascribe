# Recenzja planów fazy 1 (Hermes, 2026-09-24, doubt-driven)

> **Dla Claude Code:** ten plik jest listą uwag do planów i speców w
> `docs/superpowers/plans/` oraz `docs/superpowers/specs/`. Traktuj go jako wejście
> do zadania 0 (bramka G0, plan `2026-09-24-faza1-00-przeglad.md` §6): każdy punkt
> 🔴 **C1–C6** to znaleziony defekt planu/specu z konkretnym miejscem do naprawy.
> Punkty 🟡 i 🟢 to ryzyka i drobiazgi — część też powinna trafić do zadania 0,
> reszta do zapamiętania przy wykonaniu.
>
> Recenzent nie pisał kodu; wszystko poniżej wywodzi się z przeczytania planów,
> speców i `docs/wymagania.md`. Nie zmieniono w repo ani jednej linii.
>
> Sprawdzone arytmetycznie: liczby testów spinają się (A: 4+7+6+6+11+7+3 = 44,
> B: 5+7+6 = 18, C: 10+4+7 = 21, razem 83; sumy narastające w planach poprawne:
> 0,4,11,17,23,34,41,44 → 49,56,62 → 72,76,83). Struktura statusów ✅/🔧/⚠️ jest
> spójna ze stanem spike'a. Defekty nie dotyczą tego, tylko treści.

Oznaczenia: 🔴 defekt do naprawy przed/głównie w G0 · 🟡 realne ryzyko wykonania ·
🟢 drobiazg/kosmetyka · Nagłówek mówi, którego pliku dotyczy punkt.

---

## 🔴 Disable do naprawy w G0 (zadanie 0 + teksty przegladu)

### R1. » przeglad §7 + spec rdzenia §1 — brak sprzętowego testu T5

Spec rdzenia §1 kryterium sukcesu: *„rdzeń przechodzi testy T1–T9 na własnym
sprzęcie"*, a T5 (§9) mówi wprost *„reason == silence w ciągu 90 s"* — czyli
kryterium sprzętowe. W przegladzie §7 T5 jest zmapowane wyłącznie na
`A6 silenceEndsTheSession + mutacja` (jednostka). Żaden krok A10 nie nagrywa
realnie milczącej sesji dopóty, dopóki warunek ciszy nie pobierze końca.
**Naprawa (do zadania 0):** dodać krok sprzętowy T5 do A10 (np. krok 6b:
`record --seconds 90` w ciszy, oczekiwanie `endReason == .silence` przed
90 s przy `SilenceCondition(60)`; mutacja: usunąć warunek → czerwień) albo
zmienić wiersz „przechodzi T1–T9 na własnym sprzęcie" w spec rdzenia §1 na
„T1–T4, T6–T9 na sprzęcie, T5 jednostkowo". Jedno z dwóch — dziś jest
sprzeczność między specem a planem.

### R2. » przeglad §7 — twierdzenie o mutacji T7 w A2 jest fałszywe

w przegladzie §7 T7 ma wiersz „A2, A3, A4 + mutacja, A10 krok 8", a spec rdzenia
§9 T7 ma mutację „skasować fsync → czerwień". Stan planów:
- **A2: zero wystąpień słowa „Mutacja"** — a to właśnie A2 trzyma `synchronize()`
  (odpowiednik fsyncu). Mutacji „skasować synchronize()" nikt nie napisał.
- A3: mutacja istnieje, ale dotyczy T8 (kotwice), nie T7.
- A4: jedyna realna mutacja T7 (`data -1 → 0`).
Czyli przeglad deklaruje pokrycie mutacyjne T7 w trzech miejscach; jest w jednym,
i to innym mechanizmem niż spec mówi. **Do zadania 0:** w A2 dodać krok mutacji
„usunąć `synchronize()` z `SessionJournal.append` → `readerSkipsTruncatedLastLine`
pada po `kill -9`", albo skorygować przeglad §7, żeby nie obiecywał, czego nie ma.

### R3. » przeglad §2 — „kod identyczny z tym, co przeszło kompilator" nie jest prawdą wprost

Tekst przegladu: *„Kod z ✅ i 🔧 jest wklejony do planu automatycznie z plików
spike'a, więc jest identyczny z tym, co przeszło kompilator."* Jednocześnie C1
mówi: *„`Signals.swift` to początek `Helpers.swift` ze spike'a — z **importami
ograniczonymi** do `Foundation` i `MeetNotesSessionFormat`"*, a C3 dostaje resztę
pliku „z oryginalnymi importami". Plik po zmianie importów i cięciu nie jest
„identyczny z tym, co przeszło kompilator" — status ✅ deklaruje więc więcej,
niż gwarantuje. **Do G0:** doprecyzować zdanie w przegladzie §2: fragmenty
przeniesione z cięciem/zmianą importów mają status deklarowany przez zadanie C
(and snapshot verification is string evidence, nie automat). Nie jest to bloker
— ale jest to twierdzenie o wiarygodności planu i nie może być falszywe.

### R4. » spec fazy 1 §1.1 ↔ przeglad §7 — `transcribeUtterance` rozjazd nie dymknięty w G0

Spec fazy 1 §1.1: 🔴 *„Faza 1 implementuje pierwszy i dowodzi testem, że drugi
[transcribeUtterance] jest osiągalny tym samym kontraktem. Bez tego założenia
dyktowanie wymusi później przepisanie warstwy."* przeglad §7 mapuje P9 na coś
innego (*„funkcji o nazwie transcribeUtterance nie ma... Kontrakt jest ten sam,
nazwa nie"*). Rozjazd jest więc świadomy, ale **zadanie 0 (kroki 1–10) go nie
dymka** — spec i przeglad zostają odmiennie zdefiniowane, co znaczy „dowodzi
testem". **Do zadania 0** dodać krok: albo dopisać do kroku 0 specyfikacyjnego
zdanie przy `transcribeUtterance` („adowod: B1 `transcriptionSendsLanguageAndAsksForWordTimestamps`
+ B2 sonda = jedno żądanie, nie oddzielna funkcja"), albo zmienić plan C, żeby
funkcja istniała. Nie ma trzeciej drogi: dziś artefakty się peravorzą.

### R5. » plan D2 — `RecordingController` nie obsługuje wyniku bramki G2

`RecordingController.start` składa źródła **na sztywno**:
`[SystemTapSource(), RawMicrophoneSource(), VoiceProcessedMicrophoneSource()]`.
G2 jest zdefiniowana w przegladzie §3 jako bramka, która **może zmienić spec**
(„jeśli oba strumienie mikrofonu nie działają naraz, użytkownik decyduje, który
porzucić. Plan wtedy się zatrzymuje"). Jeśli G2 wypadnie tak, czy patrz inne
warunki, to D2 wymaga edycji struktury źródeł bez żadnej pozycji konfiguracyjnej.
**Do G0 planu D2:** dodać w interfejsie `RecordingController` pole
`sources: [any AudioSource]` (albo config, np. `Settings` → „języki" —
zdecyduj) zamiast twardej listy; A10 swojego set-upu zrobić tak, by po S2
wykonawca **musiał** zmienić kroje D2 czy nie — i zapisywać to w
`docs/superpowers/spikes/2026-09-24-s1-s2-sprzet.md`.

### R6. » przeglad — “brak pamięci na P4 (plik 85+ min)" nie istnieje

`CAFReader` ładuje **cały** plik `[Int16]`; `Resampler.toASR` robi `[Float]`.
Dla sesji 85 min:
- `system.caf` 48 kHz stereo = ok. 979 MB jako `[Int16]` w RAM + ok. 330 MB
  `[Float]` 16k mono,
- `mic_*.caf` ~163 MB + ~110 MB.
Potok C3 buduje `plan: [(track, chunk, samples)]` dla **wszystkich** ścieżek,
więc system + mic są w RAM jednocześnie → ok. 1,5–2 GB peak na 16 GB,
w trybie debug więcej. Żaden test tego nie mierzy, przeglad nie ma tego
ryzyka w tabeli, spec też nie. **Do G0:** do A10 dodać krok pomiarowy
(85-minutowa sesja → `transcribe` z pomiarem `peak RSS`, próg np. < 3 GB),
albo wpisać ℞ do przeglad („przepróbkowanie per ścieżka przyChunk-owaniu",
bez trzymania całego `x` w plan — implementacja zamiast testu).

### R7. » przeglad §7 / spec rdzenia §9 — strażnik zer tylko na `system`

T9 (spec rdzenia §§1–3) mówi o **ścieżce wypełnionej zerami** w ogólności.
Przeglad mapuje to na A6 + test `systemTrackOfPureZerosIsFlagged`, bo w
kodzie A6 `zeroWatch: = ["system": 60]` jest na sztywno. Jak odmowa mikrofonu
przybędzie zerami (to samo, co S1 bada na systemie), to **mic_raw z samych zer
nie wytworzy `track.failed`**, a przeglad P9 traktuje T9 jako w pełni pokryte.
**Do G0:** dopisać w przegladzie, że T9 ma ściałość tylko na `system`, a
dla mikrofonu jest (nie ma) testu — albo w A2/A8 dodać wariant `zeroWatch` dla
mic, gdy S1 pokaże, że mikrofon też daje zera zamiast błędu.

### R8. » spec fazy 1 §2 redaktorzy — W§2 „osobny prompt" nie jest egzekwowane typem

Spec fazy 1 §1.5 / §5: 🔴 *„osobny system prompt, osobny od korekty"*
(podsumowanie). `RoleAssignment.prompt: String?` B3 traktuje to jako pole
opcjonalne i żaden `validate()` ani test nie pilnowania separacji promptów
(np. `summary.prompt != correction.prompt` albo obecność).
Spec↔plan dostałby w G0 taki krok (albo jawna decyzja, że separacja
promptów jest w fazie B UI, nie w walidatorze — ale nie jest obecnie
zapisana w przegladzie / planie). **Do G0** decyzja + 1 linijka w B3.

## 🟡 Ryzyka rzeczywiste (nie defekt planu; zapisane do pamięci wykonawczej)

### W1. » B1/C3 — format odpowiedzi `verbose_json`: `words` na top-level nie jest gwarantowany

`OpenAICompatibleClient.words(_:)` czyta wyłącznie `obj["words"]`; nie ma
fallback `segments`. Jeśli realny MAI-Transcribe-2 zwróci segmenty,
to `words == nil` dla **każdej** okna, wszystko idzie jako
`approximateTiming`, a P4 (cięcie/scalanie po słowach) przejscie
jednostkowe testy i tak — bo korzysta ze stuba zwracającego `words`.
G3 krok 2 to wychwyci na żywym API — **ale nie ma wpisanego planu
awaryjnego** (merge z segmentów i poprawienie testu). Kto ruja wie,
ma dopisać: „jeśli format odpowiedzi to `segments` (nie `words`),
C3 Merger.zniżka doczytanie `segments[]` z czasami słów po stronie
Azure/MAI". Nie jest zapisane — gdy wykonawca trafi to w G3, będzie
improvisował.

### W2. » „Spec T5 progi 90 s" w przegladzie potrzebujesz sprzętu; „revolatile
condition 600s" nie jest� konkrem stawczny (do decyzji: test sprzętowy nak za
10-minutową ciszę jest drogi; może być krótszy wariant testowy). Nie jest to
strukturally umieszczony punkt, ale wymaga świadomej decyzji.

### W3. » `StallCondition(30s)` a słabe źródła (mic bez AEC po odmowie)

Standardowy zestaw warunków (`.standard`) zawiera `StallCondition(30s)`;
w RecordingController i w CLI `record` jawnie wchodzi do condis. Po
odmowie mikrofonu RecordingController kontynuuje tylko `system`; `tick()`
u的状况 `clock.now()` (czas mach), a `lastChunkAt` jest z chunk produkowanych
by tap — dobry przypadek. Ale Realny test niczego nie wykryje, когда
nie ma żadnego ścieżki (diod-être). Not a formal bug, ale **drewniany
defekt**: consider dodanie w przegladzie fixacji, że StallCondition
w rzeczywistości porównuje czas machowego zegara (nie przyszłego sample time).

### W4. » `LanguageGuard` (C2) — heurystyka „en > pl*2" przy bezcytzyjące trali

Case `.polish`: `!hasPolishLetters && en >= 2 && en > pl * 2`. Słowa
funkcyjne są pewnie raczej — ale w Polsce large przy negatyve (np. spotkanie
lavic), stąd wykrywa każdy en stop-word. Details:
- `'i'` w obu językach stop — policzane do [en] stop-words list; → może
  przy klasie `.polish` wyk-saugać `en >= 2` nawet, gdy tekst jest polskim.
  W praktyce do zgłoszania **fałszywych negatywów** (nie oznacza kościelny
  fragment angielskiomowych) w sytuacji, którą wyłapuje się z ang browse;
  oraz **fałszywych pozytywów** nie鉴赏.
- dla *other languages* strażnik milczy — spec to zgadza z این»; ale
  `expected == .polish || english` tak, ‹de› i süre mahulu do 0 victims i
  otwartość on Po polsku is a real problem: **deviation planted** не suş
  wypożć.
To jest pęketa: wykonawczyni każdo omiком wing: przegląd에서 dzыłać: „two
sentences" test jednostki potwierdzają. Obecny behavior jest deklarowany, that hed
is - just be aware.

### W5. » C3: `makeSession` ustawia `systemRate: 16_000`, real to 48 kHz stereo

Testy C3 `wordsLandOnTheSessionTimeline...` i `speakersComeFromChannels...`
przeskalują przez `Resampler.toASR` z 16 000 → 16 000. Uiście potoku,
że przepróbkowanie 48 kHz stereo (realność) jest wesprze przez test
`resamplerKeepsDurationAndEnergy` C1. To działa — ale **pełny potok**
(46 kHz stereo → pakowanie → WAVEncoder → scalanie → czas) nie ma testu.
Drobna ryzyce ku P4 na realu: real world może dostarczyć wąskie
widenings niedefiniowane w testach. Dopisać integracyjny test w C3/C5
z system track 48k stereo z głośkiego (spike przy A10 albo B1 nagrany
klip) — low-cost jednorazowy.

### W6. » `ProbeCache` nie ma TTL i nie kluczuje po base URL

`ProbeCache` (B3) inkrementuje `(provider, model, role)`. Nie ma TTL, brak
`providerBaseURL` w kluczu (spec: *„instancja, nie typ"* — dwa OpenRoutery z
różnymi kluczami to dwaj dostawcy; ale provider z **tym samym id** i zmienionym
baseURL nie anuluje cache). W B5 krok 1 wykonawca ręcznie sprawdza — OK,
ale poüllen wyexpcod eine user interface: po zmianie adresu provider
stale pokazuje werdykt. [* Wystarczy jedna informacja: cache stores date (checkedAt)
— researchable. Porządność.]

### W7. » D1: Info.plist bez `CFBundleInfoDictionaryVersion` — Air oposición (no)ulatory

`plutil -lint` w `bundle.sh` przejdzie; to kosmetyka. Unilując ją, AppKit
traktuje jako pluginе minor. Brak `CFBundleIconFile` — aplikação da defaulty.
Nie naprawiamy.

### W8. » przeglad i spec rdzenia powyckują „18 rozdziałów", jest 19

Kosmetyka, ale zagnieżdżona w trzech plikach (wymagania.md nagłówek,
spec rdzenia źródła, przeglad). Kiedy jeszcze raz się przytrafi:
**G0 dodaje krok „popraw numer rozdziału na 19 w nagłówku wymagania"** + w
specu rdzenia w źródłach.

---

## 🟢 Drobiazgi, które zauważyłem i ZACZIS_cumulowane (informacyjne)

- **A7 `independentSignalsHaveLowCorrelation` zawsze przechodzi** (r ≤ 0.011
  w tej skali przy maxLag 50). Realny T3 jest w A10 krok 3 (S2) — potwierdzone,
  więc nie jest to defekt, tylko domek, że jednostkowy test niewielki.
- A10 krok 2 (S1) — sonda, nie test; **brak mutacji jest OK**, przeglad i spec
  nagówek traktują sondę wyraźnie jako krok sprzętowy, nie test mutacyjny.
- **D1 Info.plist brak `NSCalendarsFullAccessUsageDescription`** — przychodza
  z fazią 3; zgodny z spec fazy 1 §1.3 (kalendarz = faza 3). OK.
- **D2 `progressReachesOneAndMetadataCarriesTheSnapshot`** (C3) jest w C3;
  przeglad mapuje P12 na `run.json` — zgodnie. Jedna rzecz: przeglad §7 P12
  mówi wprost, że testu „edytuj preset po przebiegu" brak — zgodność ta
  jest udokumentowana. OK.
- `SessionRecorder` (A6) w `deniedPermissionIsJournaledAndSessionContinues`
  test dodaje plik **nie istnieje** gdy odmowa — zgodnie z spec *„Nagranie
  połowiczne bije nagranie żadne"*. Ten test odwołuje się jedynie do
  `DeniedSource` — zgodne i spójne. OK.
- **Do Code-Speed:** A9 `AudioFit.fit` przeszukuje O(len × lags) — 8k × 50
  przy 30 s to szybkie; 85-min przez fit nigdy nie ędz (A10 używa summarize
  dla T8). OK.
- **Kosmetyka przeglad §2:** „katalog roboczy... To wykroczyło poza zakres
  «napisz plan» i użytkownik to zauważył" — gramatyka (maybe intentional).
- Sessions git: **plików nie ma jeszcze commit**; przeglad zaleca commit
  po każdym zadaniu; recordar że wywgeta docs/. Użytkownik ma przyzwalany to
  co plan.
- The przeglad §1 ta sama tabela „Status" pokazuje, że A1 testowano na
  „23 testach"; ook 23/23 występuje na A5 — compatible.
- **`przeglad` nagłówek** sygnalizuje W§7 odkryć on-time... consistent

Kto z przeciwnych rzeczy przeczytał, że to w myReader: nie rdzeń, though: **перед(jTextField) G0 jest jednozażyczania**; duże свiędомie R1–R8 i G0 pioneering niche —
potem A1–A10/B/C/D.

## Mapa punktów na pliki (dla wykonawcy)

| Punkt | Plik | Gdzie leży naprawa |
|---|---|---|
| R1 | przeglad §7, spec rdzeń §1 | A10 nowy krok (T5 sprzęt) lub zdanie w spec §1 |
| R2 | przeglad §7 + plan A2 | mutacja w A2 albo korekta przegladu |
| R3 | przeglad §2 | doprecyzowanie statusu ✅ w przegladu |
| R4 | spec faza1 §1.1 vs przeglad §7 | krok w zadaniu 0 |
| R5 | plan D2 (D2/D3) | konfiguralne listy źródeł |
| R6 | przeglad §8 (ryzyka) + A10/C5 | pomiar RAM albo przesztkowanie |
| R7 | przeglad §7 T9 lub A2/A8 | zeroWatch dla mic albo deklaracja luki |
| R8 | spec faza1 §5/B3 | walidacja osobnych promptów |
| W5 | plan C3/C5 | integracyjny test 48k stereo |
| W6 | B3 `ProbeCache` | deklaracja TTL/inwalidacji |
| W8 | wymagania.md / spce rdzenia | „19 rozdziałów" |
