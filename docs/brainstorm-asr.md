# Brainstorm: silnik lokalnego ASR (i diaryzacji)

> Data: 2026-09-24 · Tryb jednorazowy, bez rozmowy. Pytania do użytkownika zebrane w §8.
> Wejście: `docs/wymagania.md` + wnioski z forka OpenWhispr. **Dokument nie zawiera nowych
> pomiarów.** Tam, gdzie pomiaru brakuje, jest zaprojektowany eksperyment (§5). Żaden z nich
> nie został wykonany.

**Oznaczenia** (jak w wymagania.md): 🔴 twarde ograniczenie · ✅ potwierdzone pomiarem ·
🆕 wynika z pomiarów · ⚠️ ograniczenie albo **brak pomiaru**.

**Odwołania:** `W§n` = `docs/wymagania.md`, sekcja n · `rozdz. n` = rozdział n w
`GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md` · `K:Rn`, `K:Fn`,
`K:krok 9` = kronika podprojektu 1 (`2026-09-15-audio-archive-execution-log.md`, podlinkowana
w nagłówku wniosków).

---

## 0. Rozstrzygnięcie

**Rekomendacja: wariant A, czyli FluidAudio w procesie aplikacji Swift.** Z jednej biblioteki
bierzemy Parakeet TDT v3 do ASR, diaryzację, VAD i boosting słownika. Całość siedzi **za naszą
warstwą dostawców** i typy FluidAudio nie wychodzą poza adapter.

Wariant B (ASR na MLX w sidecarze, diaryzacja nadal przez FluidAudio) nie powstaje równolegle.
Jest przygotowanym wyjściem awaryjnym.

**Warunek:** A nie ma rozstrzygającego pomiaru tylko na jednej osi: ile cache'u ANE generuje
Parakeet v3. Rozstrzyga to eksperyment E1: godzina pracy, bez pisania kodu. Jeśli E1 wypadnie
źle, na B przechodzi **tylko ASR**. Swift, struktura projektu i diaryzacja przez FluidAudio
zostają bez zmian. Dlatego **nagrywanie i archiwum mogą ruszyć przed E1**, bo od silnika
nie zależą.

---

## 1. Co jest przesądzone, zanim zaczniemy porównywać

| Ustalenie | Źródło | Skutek dla wyboru silnika |
|---|---|---|
| Aplikacja natywna, nie Electron (755 MB paczki, 0,5 GB RAM) | rozdz. 5, nagłówek wniosków | tap systemowy piszemy sami: ScreenCaptureKit (macOS 14.2) albo process tap Core Audio (API od 14.4, Narada wymaga 15.6), rozdz. 6 |
| 🔴 Ollama i oMLX nie robią ASR | W§2, rozdz. 19 | odpadają jako kandydaci na ASR, zostają do tekstu |
| 🆕 ASR w procesie albo w dedykowanym sidecarze, nie przez wspólny serwer modeli | W§2, rozdz. 19 | dopuszczalne są dokładnie dwa kształty: w procesie albo sidecar |
| 🔴 Diaryzacja zawsze lokalnie (limit MAI-Transcribe-2 to 60 s na żądanie) | W§2, rozdz. 11 | każdy wariant potrzebuje lokalnej diaryzacji |
| Dwie drogi ASR (lokalna i API) → warstwa dostawcy przed pierwszą implementacją | rozdz. 9 | warstwa powstaje niezależnie od wyniku tej decyzji |
| ✅ Model nie jest różnicą, różnicę robi otoczenie | rozdz. 13, 16 | większość jakości zależy od naszego kodu (bramka, okna, próg), nie od silnika |
| ✅ Diaryzacja przez CoreML kompiluje się do kilobajtów cache'u ANE | rozdz. 10 | diaryzacja przez FluidAudio nie obciąża wagi w żadnym wariancie |

**Pytanie trzeba więc przeformułować.** Rdzeń aplikacji jest w Swifcie niezależnie od silnika:
tap systemowy trzeba napisać natywnie (rozdz. 6), a kalendarz idzie przez EventKit (W§5).
Pytanie z W§7 nie brzmi „Swift czy nie", tylko: **czy ASR działa w procesie (FluidAudio,
CoreML/ANE), czy w sidecarze na MLX (Metal)**, i czy FluidAudio w ogóle wchodzi do projektu.

---

## 2. Warianty

| | Wariant | ASR | Diaryzacja + VAD | Kształt procesu |
|---|---|---|---|---|
| **A** | FluidAudio w całości | Parakeet v3 przez FluidAudio (CoreML/ANE) | FluidAudio | jeden proces, Swift |
| **B** | Hybryda z hipotezy z rozdz. 9 | `parakeet-mlx-server` (FastAPI zgodny z OpenAI) albo `mlx-whisper`, na Metalu | FluidAudio | aplikacja Swift + sidecar Python |
| **C** | Własna ścieżka MLX, bez FluidAudio | jak B | sherpa-onnx (ONNX Runtime, ~57 MB, rozdz. 9, 12) | aplikacja Swift + sidecar |
| **D** | WhisperKit | WhisperKit (Swift) | FluidAudio | jeden proces |

**Poza konkursem, z powodów:**

- **ASR przez API (MAI-Transcribe-2)** to druga wymagana droga (rozdz. 9), która idzie obok
  lokalnej, a nie zamiast niej.
- **Cohere Transcribe (2,0 GB)** to wariant *modelu*, nie silnika. Leży w magazynie FluidAudio
  (W§0), więc jeśli w ogóle zadziała, to w ramach A. ⚠️ Nie sprawdzono, czy FluidAudio go
  uruchamia (E0e).
- **Fork Electrona** nie wraca (nagłówek wniosków, rozdz. 5).

---

## 3. Ocena na osiach

| Oś | A — FluidAudio | B — MLX + FluidAudio | C — MLX + sherpa-onnx | D — WhisperKit + FluidAudio |
|---|---|---|---|---|
| **Jakość ASR dla polskiego** | ✅ Parakeet v3: 7,31% WER na FLEURS (rozdz. 16). W praktyce ten sam v3 przez FluidAudio daje najlepszy tekst w pomiarach (Narada) i dobry u Spokenly i MacParakeeta (rozdz. 13, 17). FluidVoice bez AI: 1 obcojęzyczny wtręt na 26 min (rozdz. 13) | ⚠️ `parakeet-mlx` ma te same wagi, ale inną implementację dekodera, **niezmierzone**. `mlx-whisper`: jest tylko obserwacja „Whisper small dał czytelny polski" (rozdz. 4), bez liczb | ⚠️ jak B | ⚠️ jak `mlx-whisper`: brak pomiaru dla polskiego |
| **Diaryzacja** | ✅ w komplecie, 21 MB (W§0). Re-ID poprawne po 10 min przerwy (rozdz. 17). Jakość zależy od **naszego** progu, bo `config.json` modelu jest pusty (rozdz. 17), więc mamy nad nią kontrolę | ✅ jak A | 🔴 sherpa-onnx dał **46 „mówców" na 73 min jednej osoby**, dopóki nie dodano rampy progu (rozdz. 8, 12). Strojenie od zera | ✅ jak A |
| **Waga instalacji** | ✅ modele już na dysku, nic nie trzeba pobierać (W§0). Paczka rzędu 100 MB jest osiągalna, Narada ma 98 MB (rozdz. 6) | ⚠️ trzeba spakować runtime Pythona i MLX, **niezmierzone**. Dla skali: MacParakeet wozi Node.js (113 MB) i ffmpeg (63 MB) (rozdz. 6). ⚠️ Niesprawdzone, czy MLX odczyta wagi z magazynu, czy trzeba pobrać osobne (E0f) | ⚠️ jak B + ~57 MB sherpa-onnx (rozdz. 9) | ⚠️ modele Whispera do pobrania, nie ma ich w magazynie |
| **Cache ANE** | ⚠️ **dla v3 niezmierzony wprost.** FluidVoice na tym samym v3 i FluidAudio ma 16 KB, MacParakeet ma 7,49 GB z **jednego, niezidentyfikowanego** modelu (rozdz. 10). Rozstrzyga E1 | ✅ ASR nie korzysta z ANE, bo MLX liczy na Metalu (rozdz. 9). Diaryzacja zajmuje kilobajty (rozdz. 10) | ✅ brak cache'u ANE | ⚠️ spoza źródeł: WhisperKit działa na CoreML, więc ten sam znak zapytania co przy A, tyle że bez pomiaru jakości |
| **Zależność od cudzego harmonogramu wydań** | ⚠️ jeden dostawca (FluidInference) odpowiada za bibliotekę i za konwersje modeli do CoreML (rozdz. 8). Magazyn modeli współdzielą **cztery inne aplikacje** (W§0, rozdz. 16), więc ich aktualizacje mogą zmienić jego zawartość | ⚠️ FluidAudio + MLX + `parakeet-mlx` + dystrybucja Pythona | ⚠️ MLX + sherpa-onnx | ⚠️ WhisperKit + FluidAudio |
| **Ryzyko wykonawcze** | **najniższe.** Ta ścieżka działa w czterech aplikacjach na tej maszynie (rozdz. 8, 16). Znane pułapki (próg, bramka, długość okien) leżą w naszym kodzie (rozdz. 13, 17), a ten kod trzeba napisać w każdym wariancie | **średnie.** Drugi proces: cykl życia, port, awaria sidecara w trakcie przetwarzania. Natywne binarki pod dwa runtime'y to ta sama klasa problemów co w rozdz. 4 | **wysokie.** Ryzyka B + diaryzacja do zestrojenia od zera (rozdz. 8, 12) | **średnie.** Jakość dla polskiego niezmierzona |
| **Próg systemowy macOS** | ⚠️ minimum FluidAudio niesprawdzone (E0a). Próg aplikacji i tak wyznacza tap (14.2 albo 14.4+, rozdz. 6), więc silnik jest neutralny, dopóki jego minimum nie przekracza tego progu | ⚠️ niesprawdzone (E0a) | ⚠️ niesprawdzone | ⚠️ niesprawdzone |
| **Odwracalność** (koszt zmiany silnika po fakcie) | wymiana ASR = nowy adapter + sidecar, diaryzacja zostaje (§7, S1). Stare spotkania da się przetranskrybować z archiwum (rozdz. 5, 17) | powrót do A jest tani, bo FluidAudio i tak jest zlinkowane | **najdroższa:** powrót oznacza wymianę diaryzacji i ponowne strojenie progu (rozdz. 17) | jak A |
| **Szybkość** (oś pomocnicza) | ✅ 26 min w **6,5 s** (FluidVoice bez AI, rozdz. 13) | ⚠️ niezmierzona | ⚠️ niezmierzona | ⚠️ niezmierzona |

**Bilans:** A ma pomiar na każdej osi poza cache'em ANE. B wygrywa **tylko** na cache'u ANE,
czyli na osi, na której wynik A nie jest jeszcze znany. C i D nie wygrywają na żadnej osi.

---

## 4. Rekomendacja: dlaczego A

1. **To jedyny wariant z pomiarem jakości polskiego w praktyce.** Na tym samym v3 przez
   FluidAudio Narada ma najlepszy tekst (rozdz. 17), a FluidVoice ma 1 wtręt na 26 min
   (rozdz. 13). Pozostałe warianty zaczynają od zera pomiarów.
2. **FluidAudio i tak wchodzi do projektu.** Diaryzacja przez nie jest w A, B i D, bo kosztuje
   kilobajty cache'u ANE (rozdz. 10), a re-identyfikacja działa (rozdz. 17). Jedyny wariant,
   który je wymienia (C), dziedziczy problem 46 „mówców" (rozdz. 8, 12). Otwarte zostaje więc
   tylko to, **czym robić ASR**.
3. **B dodaje drugi proces i drugi runtime, żeby zaoszczędzić jeden koszt, którego w A nikt
   nie zmierzył.** Dane o cache'u ANE są sprzeczne: FluidVoice ma 16 KB, MacParakeet 7,49 GB
   (rozdz. 10). Rozstrzygnąć to powinien pomiar (E1), a nie przeczucie.
4. **Lekkość bez pobierania.** Modele leżą na dysku (W§0), a waga zależy od polityki modeli,
   nie od technologii (rozdz. 6, 10).
5. **Szybkość daje odwracalność.** 26 min w 6,5 s (rozdz. 13) oznacza, że postęp w procentach
   przy plikach powyżej 80 min (W§1) jest trywialny, a ponowny przebieg całego archiwum po
   zmianie silnika jest tani.
6. **Boosting słownika to funkcja FluidAudio** (W§3), a pole `aliases` pasuje do naszego
   `replacements.tsv`. W B i C trzeba by go zastąpić korektą po ASR.
7. **Ryzyko A leży w naszym kodzie**, a ten kod (bramka, okna, próg, łączenie kanałów) jest
   potrzebny w każdym wariancie (rozdz. 13: „model nie jest różnicą").

### Co zmieniłoby rekomendację

| Sygnał | Skąd | Decyzja |
|---|---|---|
| v3 przez FluidAudio generuje cache ANE ponad budżet i nie da się go ograniczyć | E1, potem powtórzenie w etapie 3 planu | **ASR przechodzi na B**, diaryzacja i VAD zostają w A. Struktura projektu bez zmian |
| Licencja FluidAudio albo wag v3 nie pozwala na zamierzone użycie | E0b | rewizja: D, a jeśli jest ten sam problem, C |
| Minimum macOS FluidAudio jest wyższe niż próg wybranego tapu | E0a | jeśli różnica jest akceptowalna, przyjmujemy wyższy próg; jeśli nie, B |
| A daje na korpusie wyraźnie gorzej niż FluidVoice albo Narada na tym samym v3 | etap 3 planu | **to nie jest powód do zmiany silnika.** To błąd naszego otoczenia (rozdz. 13), do naprawienia w bramce i oknach |

---

## 5. Brakujące pomiary: eksperymenty (zaprojektowane, **nie wykonane**)

### E0: sprawdzenie dokumentacji i paczek (≤ 30 min, bez instalacji, bez kodu)

| # | Co sprawdzić | Jak | Wynik → decyzja |
|---|---|---|---|
| a | minimum macOS FluidAudio | `platforms` w `Package.swift` FluidAudio; `LSMinimumSystemVersion` w `Info.plist` FluidVoice i Spokenly | ≤ próg tapu → oś neutralna. Wyżej → wiersz tabeli w §4 |
| b | licencja biblioteki i wag (v3, diaryzacja) | plik LICENSE repo, karty modeli na HF | niezgodna → stop A |
| c | tempo łamiących zmian | liczba wydań w ciągu 12 miesięcy i wpisy „breaking" w changelogu | > 1 na kwartał → twardsze przypięcie wersji. Decyzja się nie zmienia |
| d | czy wynik ASR ma znaczniki czasu słów lub tokenów | dokumentacja i API FluidAudio | brak → łączenie z diaryzacją na poziomie segmentów (plan, etap 4). Decyzja się nie zmienia |
| e | czy FluidAudio uruchamia `cohere-transcribe` z magazynu i czy pozwala wybrać jednostki obliczeniowe (CPU/GPU zamiast ANE) | dokumentacja i API | wybór jednostek to plan awaryjny dla E1 bez zmiany silnika |
| f | format katalogu `FluidAudio/Models/parakeet-tdt-0.6b-v3` (wersji innej niż `-coreml`) | lista plików | czy B mogłoby użyć wag z magazynu, czy wymaga pobrania |
| g | czy aplikacja poza sandboxem może czytać wspólny magazyn, i co by się stało w sandboxie | ⚠️ spoza źródeł: pliki cudzych aplikacji w `Application Support` są dla aplikacji w sandboxie niedostępne bez uprawnień | wpływa na dystrybucję (pytanie P3) |

### E1: rachunek ANE dla Parakeeta v3 i diaryzacji (≈ 1 h, bez kodu, na zainstalowanych aplikacjach)

**Pytanie:** ile cache'u ANE generują Parakeet v3 i diaryzacja przez FluidAudio, i który
model wygenerował 7,49 GB u MacParakeeta?

**Dlaczego dane z rozdz. 10 nie wystarczają:** 16 KB u FluidVoice i 7,49 GB u MacParakeeta
pochodzą z tej samej biblioteki. Pomiar objął tylko `~/Library/Caches/<bundle>`, a nie
kontenery sandboxa, a model odpowiedzialny za 7,49 GB nie został zidentyfikowany.

**Procedura:**

1. **Inwentaryzacja:** rozmiar każdego katalogu `com.apple.e5rt.e5bundlecache` w
   `~/Library/Caches/*` **oraz** w `~/Library/Containers/*/Data/Library/Caches/*`.
2. **Atrybucja 7,49 GB:** porównać datę modyfikacji tego bundla z datami ładowania modeli
   w logach i ustawieniach MacParakeeta. Na tej podstawie ustalić, który wariant był wtedy
   wybrany (lekcja z rozdz. 16: sprawdzać wybrany wariant, a nie domniemany).
3. **Próba kontrolowana:** w FluidVoice (FluidAudio + v3, rozdz. 16) potwierdzić wybrany
   wariant v3. Jego cache ANE **przenieść do kopii zapasowej** (nie kasować). Przetranskrybować
   nagranie 85-minutowe (W§1) bez diaryzacji, zapisać `du` cache'u i czas. Powtórzyć
   z diaryzacją. Opcjonalnie powtórzyć to samo w Spokenly.
4. Powtórzyć przebieg po restarcie, żeby sprawdzić, czy cache jest trwały i czy rośnie przy
   kolejnym ładowaniu. Na koniec przywrócić kopię zapasową.

**Reguła rozstrzygnięcia** (próg 1 GB to **nasz budżet, nie pomiar**, do zatwierdzenia w P2):

| Wynik dla v3 + diaryzacji | Decyzja |
|---|---|
| ≤ 300 MB | A bez zastrzeżeń |
| 300 MB – 1 GB | A. Rozmiar cache'u pokazywany na ekranie modeli (W§2 🆕), budżet pilnowany w każdym etapie |
| > 1 GB i przypisane do v3 | etap 3 zaczyna od próby z innymi jednostkami obliczeniowymi (jeśli E0e na to pozwala). Jeśli nie da się zejść poniżej 1 GB, **ASR przechodzi na B**, a diaryzacja zostaje w A |
| > 1 GB, ale przypisane do innego modelu (np. Cohere) | A. Ten model odpada z v1 |

⚠️ E1 mierzy **konfigurację FluidVoice**. W etapie 3 planu ten sam pomiar wykonujemy na
naszej aplikacji (tam kryterium akceptacji 7).

### E2: parytet MLX (warunkowy, tylko jeśli E1 wskaże B)

- **Co:** `parakeet-mlx` na tych samych plikach co w rozdz. 13 (spotkanie WFM, 26 min)
  i rozdz. 17 (debata, ~15 min).
- **Punkt odniesienia:** FluidVoice bez AI, czyli ~2450 słów, 1 wtręt i 6,5 s (rozdz. 13).
- **Mierzymy:** liczbę słów, obcojęzyczne wtręty, czas, rozmiar zainstalowanego sidecara.
- **Próg przyjęcia B** (nasze progi): słowa w granicach ±5% punktu odniesienia, wtręty ≤ 3
  na 26 min, czas ≤ 60 s na 26 min.
- **Poniżej progu:** zostajemy przy A i akceptujemy cache (pytanie P2).
- **Koszt:** pół dnia. Wymaga instalacji `parakeet-mlx`, ale tylko w tym scenariuszu.

---

## 6. Co ta decyzja zamyka, a co zostawia otwarte

**Zamyka:**

| Sprawa | Rozstrzygnięcie |
|---|---|
| Język | Swift, jeden proces. W v1 paczka nie zawiera runtime'u Pythona ani Node'a (waga, rozdz. 6) |
| Struktura | moduły z warstwą dostawców. FluidAudio jest importowane **wyłącznie w adapterach** (rozdz. 9) |
| Diaryzacja i VAD | FluidAudio, **niezależnie od wyniku E1** |
| Źródło modeli | wspólny magazyn FluidAudio (W§0), tylko do odczytu, z weryfikacją wariantu (rozdz. 16) |
| Słownik | nasz format kanoniczny. Natywny boosting FluidAudio (W§3) to jeden z kilku kompilatorów |
| Kandydaci odrzuceni | Ollama i oMLX (rozdz. 19), C (diaryzacja, rozdz. 8, 12), D (brak pomiaru, bez przewagi). D może wrócić tylko przez E0b |

**Zostawia otwarte (nic z tej listy nie blokuje startu):**

| Sprawa | Kiedy się rozstrzyga |
|---|---|
| Czy ASR zostaje w A, czy przechodzi na B | E1, przed etapem 3 planu |
| Tap: ScreenCaptureKit czy process tap, a z nim próg macOS | `plan.md` §7, pytania P5–P6 |
| Drugi lokalny model (Cohere Transcribe, W§0) | po E0e i E1. W v1 go nie ma |
| Model do dyktowania na żywo: v3 w krótkich oknach czy model strumieniowy (FluidAudio zna `parakeet-realtime-eou-120m`, rozdz. 8; ⚠️ jego język jest niesprawdzony) | plan, etap 9 |
| Domyślna **wartość** progu klastrowania | pomiar w etapie 4 planu (rozdz. 17) |
| Dostawca AI do korekty i podsumowań | tania i odwracalna decyzja (rozdz. 12, pkt 4) |

---

## 7. Plan wyjścia awaryjnego

Koszty to **szacunek w osobodniach, nie pomiar**. Są prawdziwe tylko wtedy, gdy od pierwszego
dnia spełnione są warunki podane pod tabelą.

| Scenariusz | Wyzwalacz | Co trzeba przepisać | Co zostaje | Koszt |
|---|---|---|---|---|
| **S1: ASR z FluidAudio zawodzi** | E1 ponad budżet, regresja wydania albo jakość, której nie da się naprawić otoczeniem | adapter transkrypcji dla sidecara MLX (1–2 dni, bo klient HTTP już istnieje w adapterze API: `/audio/transcriptions` przez OpenRouter (rozdz. 11), a `parakeet-mlx-server` jest zgodny z OpenAI (W§2); ⚠️ format żądania do potwierdzenia). Cykl życia sidecara: start, zdrowie, restart, port (2–3 dni). Pakowanie Pythona i MLX do podpisanej paczki (2–4 dni, ⚠️ największa niewiadoma, klasa problemów z rozdz. 4). Parytet E2 i ponowny przebieg korpusu (1 dzień) | nagrywanie, archiwum, bramka (VAD FluidAudio), diaryzacja, łączenie, UI, notatki. Słownik przechodzi na kompilator „korekta po ASR", który istnieje już dla dostawców bez boostingu | **~6–10 dni** |
| **S2: diaryzacja z FluidAudio zawodzi** | regresja wydania albo próg, którego nie da się zestroić na korpusie | adapter sherpa-onnx (rozdz. 9) 2–3 dni. Strojenie progu z rampą zależną od długości na debacie i nagraniu 73 min (rozdz. 8, 12) 3–7 dni. Paczka rośnie o ~57 MB | wszystko poza adapterem diaryzacji | **~5–10 dni** |
| **S3: FluidAudio porzucone albo licencja** | E0b albo koniec utrzymania | S1 + S2 + bramka (VAD) 2–3 dni | nagrywanie, archiwum, łączenie, UI, notatki, słownik | **~13–23 dni** |
| **S4: magazyn zmieniony przez inną aplikację** | suma kontrolna wariantu się nie zgadza (rozdz. 16) | własna kopia modeli w katalogu aplikacji: jednorazowe pobranie 461 + 21 MB (W§0) | wszystko | **~1–2 dni** |

Przypięta wersja FluidAudio działa dalej niezależnie od tego, co robi upstream. S3 wymusza
więc dopiero zmiana w systemie albo w licencji, a nie samo porzucenie projektu.

**Warunki, które trzymają koszty w tych widełkach** (plan traktuje je jako wymagania od
pierwszego dnia):

1. Typy FluidAudio nie wychodzą poza adapter (rozdz. 9). Sprawdzane mechanicznie: import
   tylko w module adaptera.
2. Słownik jest w naszym formacie i kompilowany osobno dla każdego silnika: boosting (W§3),
   `phraseList` (rozdz. 11), korekta po ASR.
3. Każdy przebieg transkrypcji zapisuje silnik, wariant modelu z sumą kontrolną, język
   i wersję słownika (W§2 🆕, rozdz. 16). Przebiegi starego i nowego silnika leżą obok siebie.
4. Archiwum jest źródłem prawdy, a transkrypt półproduktem (rozdz. 5, 17). Zmiana silnika nie
   niszczy danych, tylko wymaga ponownego przebiegu.
5. Znaczniki czasu są w **czasie sesji** (kotwica hosta, W§1 🔴), a nie w czasie silnika.
   Przeliczenie robi adapter.

---

## 8. Pytania wymagające decyzji

| # | Pytanie | Rekomendacja | Uzasadnienie |
|---|---|---|---|
| **P1** | Czy akceptujesz A z bramką E1 przed etapem ASR, zamiast od razu wybierać B? | **Tak** | A ma pomiary na wszystkich osiach poza jedną. B wygrywa tylko na tej niezmierzonej (§3). E1 kosztuje godzinę i nie blokuje etapów 1–2 |
| **P2** | Budżet cache'u ANE dla ASR i diaryzacji razem | **1 GB** | Wymaganie „bez wielogigabajtowego narzutu" (rozdz. 9, 5). 1 GB to ~10× paczka Narady (rozdz. 6) i ~1/7 rachunku MacParakeeta (rozdz. 10). Liczba jest arbitralna, ważne, żeby była ustalona przed E1 |
| **P3** | Czy aplikacja ma działać wyłącznie na Twoim komputerze, czy będzie dystrybuowana? | **v1: tylko Twój komputer**, poza App Store | Wspólny magazyn modeli (W§0) istnieje tylko tam, gdzie są inne aplikacje FluidAudio. Dystrybucja uruchamia S4 od razu, pytanie o licencję (E0b) i o sandbox (E0g) |
| **P4** | Cohere Transcribe w v1? | **Nie** | Jakość dla polskiego niezmierzona, a obsługa w FluidAudio niesprawdzona (E0e). To najpewniejszy kandydat na „jeden duży model", który generuje gigabajty cache'u (rozdz. 10). To hipoteza, rozstrzyga E1 |
