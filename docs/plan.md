# Plan wdrożenia v1: notatki ze spotkań i dyktowanie (macOS, natywnie)

> Data: 2026-09-24 · Tryb jednorazowy. Pytania do użytkownika zebrane w §7.
> Opiera się na `docs/brainstorm-asr.md`: **wariant A (FluidAudio w procesie) z bramką E1**.
> Plan nie zawiera kodu ani szkieletu projektu. Opisuje granice, przepływ danych i sposób
> sprawdzenia, że etap jest naprawdę zrobiony.

**Oznaczenia** (jak w wymagania.md): 🔴 twarde ograniczenie · ✅ potwierdzone pomiarem ·
🆕 wynika z pomiarów · ⚠️ ograniczenie albo **brak pomiaru**.

**Odwołania:** `W§n` = `docs/wymagania.md`, sekcja n · `rozdz. n` = rozdział n wniosków
(`GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md`) · `K:Rn`, `K:Fn`,
`K:krok 9` = kronika podprojektu 1 (`2026-09-15-audio-archive-execution-log.md`) ·
`B§n` = `docs/brainstorm-asr.md`. Progi opisane jako „**nasz budżet**" to decyzje, nie pomiary.

---

## 1. Zakres v1

### 1.1 W v1

| Funkcja | Wymaganie | Uwagi |
|---|---|---|
| Nagrywanie spotkań: dźwięk systemowy + mikrofon, bez bota | W§1 ✅, rozdz. 6 | tap natywny (P5) |
| Archiwum dwukanałowe: odsłuch = tap systemowy, mikrofon osobno, kotwica czasu na ścieżkę | W§1 🔴, rozdz. 18 | przeniesione z podprojektu 1 (K:krok 9) |
| Mechaniczny koniec sesji: koniec zdarzenia w kalendarzu, cisza > N min, przycisk | W§1 🔴, rozdz. 17 | trzeci warunek (zamknięcie okna rozmowy) odłożony, patrz 1.2 |
| Kalendarz Apple (EventKit): nadchodzące spotkania, oś czasu z podziałem na dni | W§5 ✅ | to samo zdarzenie daje warunek końca |
| ASR lokalny (Parakeet v3 przez FluidAudio) **i** przez API (MAI-Transcribe-2) | W§2, rozdz. 9, 11 | druga droga jest też dowodem, że abstrakcja działa (etap 5) |
| Profil „model + język": bez `auto`, widoczny przed startem, ekran modeli | W§2 🔴🆕, rozdz. 14, 16 | |
| Bramka mowy per kanał przed ASR | W§1 🔴, rozdz. 13, 15, 17 | |
| Diaryzacja lokalna kanału systemowego, próg nastawialny | W§2 🔴, W§5 🔴, rozdz. 17 | kanał mikrofonu = „Ja", bez modelu (W§5 🆕) |
| Edycja rozmówców: scal, nazwij, przypisz fragment innej osobie | W§5 ✅ | rozdzielania scalonych klastrów nie ma: nie da się tego zrobić po fakcie (rozdz. 17) |
| Klikalna linia czasu → skok w nagraniu; postęp w %, także dla plików > 80 min | W§1 ✅ | |
| Notatka ze strukturą (temat, ustalenia, zadania z właścicielem, pytania otwarte), osobne prompty do korekty i do podsumowania | W§4 ✅🔴, W§2 ✅ | |
| Eksport do markdown | W§6 ✅ | |
| Słownik: import `GCX/dictation`, boosting, dopisanie aliasu kliknięciem w słowo | W§3 🔴🆕 | pętla uczenia to realna nowość (W§3) |
| Pływające okno z nagrywaniem i wyborem profilu | W§6 🆕 | |
| Dyktowanie (osobny tryb mikrofonowy) | W§1 ✅ | ostatni etap. Może przejść do v1.1 bez kosztu architektonicznego (P7) |

### 1.2 Świadomie odłożone

| Co | Dlaczego odłożone | Odwracalne? | Co przygotować teraz, żeby odłożenie było tanie |
|---|---|---|---|
| **Odsłuch zmiksowany** (obie strony w jednym pliku) | wymaga wyrównania, a oryginały muszą zostać (W§7, rozdz. 18 pkt 4) | ✅ **w pełni.** Miks da się wygenerować z archiwum w dowolnym momencie, także dla starych spotkań | kotwice czasu per ścieżka (i tak 🔴) |
| **Nagrywanie ekranu** | wideo to inny rząd wielkości: przechwytywanie, magazyn i odtwarzanie (W§7) | ⚠️ **częściowo.** Dla przyszłych spotkań tak. Dla spotkań nagranych bez ekranu obrazu nie da się odtworzyć | manifest sesji przyjmuje dowolną liczbę ścieżek |
| Chat nad spotkaniem i RAG nad archiwum | zależy od stabilnego transkryptu z tożsamością mówców (W§4) | ✅ bo liczy się z zapisanych danych | transkrypty w czasie sesji, przebiegi wersjonowane |
| MCP dla Claude | warstwa odczytu nad magazynem (W§6) | ✅ | jw. |
| Zakładka zadań (zbiorczo, między spotkaniami) | v1 ma zadania z właścicielem w notatce (W§4). Zakładka to agregacja | ✅ | zadania zapisane jako dane, nie tylko jako tekst markdown |
| Automatyczne nazwiska z wywołań prowadzącego | 🆕 w zasięgu (W§5, rozdz. 17), ale wymaga stabilnej diaryzacji i transkryptu | ✅ jako przetwarzanie końcowe zapisanych danych | segmenty mówców przechowywane z czasem sesji |
| Warunek końca „zamknięcie okna rozmowy" | wykrywanie okien innych aplikacji nie było mierzone. Kalendarz i cisza spełniają 🔴 | ✅ | warunki końca jako lista, nie jeden `if` |
| Automatyczne wykrywanie startu spotkania | autodetekcja kosztowała minuty treści: 1:22 vs 2:43 vs 3:54 (rozdz. 13) | ✅ | start ręczny albo z kalendarza |
| Transkrypt na żywo w trakcie spotkania | diaryzacja potrzebuje całego kanału (rozdz. 11). Przebieg wsadowy jest szybki (26 min w 6,5 s, rozdz. 13) | ✅ | kontrakt ASR obsługuje też krótkie okna (dyktowanie) |
| Drugi lokalny model (Cohere Transcribe) | B§8 P4: jakość dla polskiego i obsługa niezmierzone | ✅ | profil jako byt, nie stała |
| Własny WebRTC AEC3 | v1: AEC platformowy (rozdz. 7, 12) | ✅ **pod warunkiem**, że archiwizujemy surowy mikrofon, bo wtedy AEC da się powtórzyć offline z kanałem systemowym jako odniesieniem (rozdz. 7) | `mic_raw` w archiwum (P11) |
| Fine-tuning | dopiero gdy aliasy nie wystarczą (W§3) | ✅ | wersja słownika w metadanych przebiegu |
| Sidecar MLX | tylko w scenariuszu S1 (B§7) | ✅ | kontrakt dostawcy (§2.3) |

---

## 2. Architektura

### 2.1 Zasady (każda wynika z pomiaru albo z kroniki)

1. **Archiwum jest źródłem prawdy, transkrypt półproduktem.** Każdy błąd rozpoznania da się
   naprawić ponownym przebiegiem, pod warunkiem że nagranie przetrwało (rozdz. 5, 17).
2. **Jeden zegar.** Czas sesji = zegar hosta. Każda ścieżka niesie własną kotwicę, a wszystkie
   znaczniki (słowa, mówcy, zdarzenia urządzeń) są w czasie sesji (W§1 🔴, rozdz. 18, ryzyko M4).
3. **Warstwa dostawców powstaje przed pierwszą implementacją.** Typy silnika nie wychodzą poza
   adapter (rozdz. 9).
4. **Kanał jest bytem pierwszej klasy.** „Ja / oni" wynika z kanału, a diaryzacja działa tylko
   w kanale systemowym (W§5 🆕, rozdz. 8).
5. **ASR nie jest cięty przez diaryzację.** Oba procesy biegną niezależnie i łączą się po czasie
   (rozdz. 13: tryb z diaryzacją podniósł wtręty z 1 do 16).
6. **Okna ASR są długie**, wyznaczone przez bramkę mowy z histerezą, a nie co kilka sekund
   (rozdz. 13, 15).
7. **Nie kasujemy surowego nagrania, dopóki plik zakodowany nie jest zweryfikowany, a wskaźnik
   do niego zapisany** (K:R25, K:F2).
8. **Każdy przebieg jest wersjonowany:** dostawca, wariant modelu z sumą kontrolną, język,
   wersja słownika, parametry bramki i progu (W§2 🆕, rozdz. 16).
9. **Nie ma żadnego `auto`,** ani dla języka, ani dla modelu (rozdz. 14).
10. **Możliwość dostawcy potwierdza prawdziwe wywołanie, a nie obecność na liście**
    (rozdz. 11, 19).

### 2.2 Moduły: granice odpowiedzialności

| Moduł | Odpowiada za | Wejście → wyjście | **Nie wie o** |
|---|---|---|---|
| **Capture** | tap systemowy; mikrofon surowy + po AEC (jak Narada, rozdz. 18); trzy obserwatory urządzeń (W§1 🆕); kotwica hosta per ścieżka | urządzenia → strumienie PCM + zdarzenia urządzeń (czas sesji) | sesjach, plikach, ASR |
| **Archive** | zapis ścieżek; kodowanie; manifest sesji; **rejestr nośników**, czyli jedno miejsce znające każdy plik (K:F1); retencja osobno dla każdego nośnika (K:R14); czyszczenie wskaźników przy kasowaniu (K:R15); sprzątanie sierot (K, zad. 5) | strumienie → pliki + manifest | transkrypcji, kalendarzu |
| **Session** | stan sesji; start i stop; warunki końca (kalendarz, cisza); **błąd archiwum nie przerywa stopu** (K:F3) | polecenia + zdarzenia kalendarza + poziom ciszy → sesja zamknięta | kodekach, silnikach |
| **Calendar** | EventKit: zdarzenia, uczestnicy, początek i koniec (W§5) | kalendarz systemowy → zdarzenia | nagrywaniu |
| **Import** | wczytanie nagrania z pliku jako sesji (1 albo 2 ścieżki) | pliki → sesja | skąd pochodzi plik. Służy do deterministycznych testów na korpusie i jako funkcja dla użytkownika |
| **Providers** (warstwa dostawców) | kontrakty: Transkrypcja, Diaryzacja, Bramka mowy, AI tekstowe; rejestr dostawców; opis ich możliwości; profile „model + język" | patrz §2.3 | UI, sesjach |
| ↳ adapter FluidAudio | ASR v3, diaryzacja, VAD, boosting. **Jedyne miejsce, które importuje FluidAudio** | | |
| ↳ adapter API | MAI-Transcribe-2 przez OpenRouter (rozdz. 11) | | |
| ↳ adapter AI | OpenRouter, Ollama, oMLX: **tylko tekst** (rozdz. 19) | | |
| **ModelStore** | odczyt wspólnego magazynu (W§0) **tylko do odczytu**; weryfikacja wariantu (suma kontrolna); rozmiar cache'u ANE dla UI | magazyn → opis dostępnych wariantów | przetwarzaniu |
| **Pipeline** | orkiestracja: bramka per kanał → ASR na oknach mowy → diaryzacja całego kanału systemowego → łączenie po czasie → przebieg N; postęp w %, anulowanie, wznowienie | sesja + profil + słownik → przebieg transkrypcji | szczegółach silników |
| **Speakers** | tożsamość: klaster → osoba (ID stabilne w obrębie spotkania); „Ja" z kanału mikrofonu; scalanie, nazwy, przypisanie fragmentu | segmenty + edycje → rejestr mówców | ASR |
| **Vocabulary** | słownik kanoniczny (terminy + aliasy); import `GCX/dictation` (166 terminów, 223 pary, W§0); kompilatory per dostawca; pętla „klik → poprawka → alias" | edycje → skompilowany słownik dla danego dostawcy | tym, który silnik jest aktywny |
| **Notes** | korekta i podsumowanie (osobne prompty, W§2); struktura z W§4; ID mówców do poziomu zadań; eksport do markdown | przebieg + rejestr mówców → notatka | audio |
| **Store** | spotkania, przebiegi, transkrypty, mówcy, notatki | | |
| **UI** | pływające okno (profil + nagrywanie); lista i oś dni; widok spotkania (linia czasu, odtwarzacz, mówcy, edycja słów); ekran modeli (wzór: Spokenly, rozdz. 16) | | silnikach, bo widzi tylko opis możliwości |
| **Dictation** | tryb mikrofonowy: skrót → bramka → ASR (krótkie okno) → wstawienie tekstu | mikrofon → tekst | spotkaniach |

### 2.3 Warstwa dostawców: kontrakt (opis, nie kod)

**Transkrypcja**
- **Wejście:** odwołanie do audio (jeden kanał, zakres w czasie sesji); profil „model + język",
  nierozdzielny i bez `auto` (W§2 🔴); słownik skompilowany dla tego dostawcy; tryb (plik albo
  krótka wypowiedź).
- **Wyjście:** słowa (tekst, początek, koniec **w czasie sesji**, pewność) oraz metadane
  przebiegu (dostawca, wariant, suma kontrolna, język, wersja słownika, lokalnie czy zdalnie).
- **Obowiązki adaptera:** cięcie na limity dostawcy i scalanie po znacznikach słów (rozdz. 11);
  przeliczenie czasu; postęp; anulowanie.
- **Zakazy:** dostawca nie wybiera języka i nie robi dla nas diaryzacji, nawet jeśli umie
  (W§2 🔴, rozdz. 11).

**Diaryzacja**
- **Wejście:** **cały** kanał systemowy, nigdy kawałki, bo kawałki łamią tożsamość (rozdz. 11);
  okna mowy z bramki; próg jako parametr aplikacji (rozdz. 17).
- **Wyjście:** segmenty (początek, koniec, klaster) w czasie sesji + metadane (model, próg).

**Bramka mowy**
- **Wejście:** kanał + kanał odniesienia (ten drugi).
- **Wyjście:** okna mowy (histereza, minimalna długość; rozdz. 15) oraz **odrzucone okna
  z przyczyną** (cisza albo przesłuch) do diagnostyki. Cisza → nie wysyłaj; przesłuch → odrzuć
  okno skorelowane z drugim kanałem (rozdz. 17).

**AI tekstowe**
- **Wejście:** transkrypt z ID mówców + prompt (korekta albo podsumowanie).
- **Wyjście:** tekst ze strukturą.
- Dostawca ma flagę lokalny/zdalny.

**Sprawdzenie papierowe kontraktu** (etap 0): każda właściwość trzech realnych dostawców musi
się dać wyrazić bez typu specyficznego dla dostawcy.

| Właściwość | FluidAudio (A) | MAI-Transcribe-2 / OpenRouter | sidecar MLX (B) |
|---|---|---|---|
| Gdzie idzie audio | w procesie | **opuszcza komputer**, trzeba to pokazać w UI (por. Spokenly, rozdz. 16) | lokalnie, inny proces |
| Maks. długość żądania | ⚠️ E0 | **60 s** (rozdz. 11) | ⚠️ |
| Znaczniki czasu słów | ⚠️ E0d | tak, `timestamp_granularities: word` (rozdz. 11) | ⚠️ |
| Słownik | boosting JSON (W§3) | `phraseList` (rozdz. 11) | brak → korekta po ASR |
| Język | związany z modelem; v3 zna 25 języków (rozdz. 16) | `language: pl` jawnie (rozdz. 11) | ⚠️ |
| Diaryzacja | osobny kontrakt | umie, **nie używamy** (W§2 🔴) | brak |
| Koszt | 0 | ~0,10 USD/h (rozdz. 11) | 0 |

### 2.4 Przepływ danych

```
Calendar ──(start/koniec)──► Session ◄──(poziom ciszy)── Capture
                               │                            │ PCM: system (tap), mic_raw, mic_aec
                               │ stop                       │ + kotwice hosta + zdarzenia urządzeń
                               ▼                            ▼
                            Archive ──► pliki + manifest sesji ──► Store (rejestr nośników)
                               │  (surowe PCM kasowane dopiero po weryfikacji pliku i wskaźnika)
                               ▼
Import ─────────────────────► Pipeline (wsadowo, po końcu sesji; postęp %)
                               ├─ Bramka(mic, odniesienie = system) ─► okna ─► Transkrypcja ─► słowa „Ja"
                               ├─ Bramka(system) ────────────────────► okna ─► Transkrypcja ─► słowa
                               └─ Diaryzacja(cały kanał systemowy) ─────────────────────────► segmenty
                                          ▼
                               łączenie po czasie sesji ─► przebieg N (wersjonowany)
                                          ▼
                               Speakers (klaster → osoba) ─► Notes (AI: korekta, podsumowanie) ─► markdown
Vocabulary ──(słownik skompilowany dla dostawcy)──► Transkrypcja
ModelStore ──(zweryfikowany wariant)─────────────► profil ─► Transkrypcja
Dictation: mic ─► Bramka ─► Transkrypcja (krótkie okno) ─► tekst
```

**Źródło audio dla ASR:** pierwszy przebieg idzie z PCM, zanim zostanie skasowane (zasada 7),
kolejne przebiegi z archiwum. ⚠️ Nie zmierzono, czy ASR na pliku stratnym daje ten sam wynik.
Rozstrzyga E3 (etap 1).

### 2.5 Manifest sesji: co musi się w nim znaleźć

Dla każdej ścieżki: rola (`system`, `mic_raw`, `mic_aec`), plik, kodek, częstotliwość i liczba
kanałów, **kotwica hosta pierwszej ramki**, UID urządzenia, stan AEC zgodny z faktyczną
zawartością pliku (K:krok 9, K zad. 6). Do tego dziennik zdarzeń urządzeń w czasie sesji
(rozdz. 18), identyfikator zdarzenia kalendarza i przyczyna końca sesji (kalendarz, cisza,
przycisk).

---

## 3. Etapy

### 3.0 Zasady weryfikacji (dotyczą każdego etapu)

- **Akceptacja to pomiar na prawdziwym audio z korpusu, a nie zielona suita.** Zielony test
  dowodzi tylko swojej ścieżki: testy pominięte, test obok naprawionego błędu, test omijający
  leniwe ładowanie (rozdz. 1).
- **Test, który broni kryterium, musi przejść mutację:** wstrzyknąć błąd, zobaczyć czerwień,
  przywrócić (rozdz. 1).
- **Rozstrzyga pełny przebieg, a nie szybki test** (rozdz. 1).
- **Przed etapem:** przegląd par zadań, które dzielą plik albo interfejs. **Po etapie:**
  przegląd całości, a nie tylko pojedynczych zadań (rozdz. 2, K: przegląd przed startem).
- **Budżety ciągłe, mierzone na końcu każdego etapu:**
  - paczka bez modeli ≤ 100 MB (Narada: 98 MB, rozdz. 6);
  - RAM na spoczynku ≤ 100 MB (**nasz budżet**; Electron ~0,5 GB, rozdz. 5);
  - cache ANE ≤ budżet z B§8 P2.

### 3.1 Korpus referencyjny

| Nagranie | Źródło | Do czego służy |
|---|---|---|
| Spotkanie WFM, 26 min, PL | rozdz. 13 | tekst, wtręty, słowa na segment, wyniki 5 aplikacji jako punkt odniesienia |
| Spotkanie PL, 10:48 | rozdz. 14 | język (62% zmyślonej angielszczyzny przy `en`) |
| Debata krakowska, ~15 min, ~11 osób, użytkownik milczy | rozdz. 17 | diaryzacja, zanieczyszczenie kanału „Ja", przypisanie obietnic |
| Nagrania ~85 min | W§1 | postęp w %, czas, pamięć |
| Nagranie 73 min, jedna osoba | rozdz. 8, 12 | nadmierne klastrowanie (46 „mówców") |
| Nagrania 1–4 z kroku 9 | K:krok 9 | AEC (korelacja 0,12), przeciek między kanałami (−180 dB) |
| **Nowe:** rozmowa w Teams | W§7 | czy tap łapie Teams |

⚠️ Nie wiadomo, czy wszystkie pliki nadal istnieją (P8).

---

### Etap 0: Bramka decyzyjna i fundament pomiarowy

**Zakres:**
- E0 i E1 z B§5 (E2 tylko wtedy, gdy E1 wskaże B);
- korpus zebrany z sumami kontrolnymi;
- procedury metryk;
- kontrakty dostawców opisane na papierze (§2.3).

**Zależy od:** nic. **Blokuje:** etap 3. Etapy 1–2 **nie czekają** na E1.

| # | Kryterium akceptacji | Jak zmierzyć |
|---|---|---|
| 0.1 | E1 wykonany, decyzja A albo B podjęta **według reguły z B§5**, a nie po fakcie | wynik i decyzja zapisane w repo przed startem etapu 3 |
| 0.2 | Każda metryka jest procedurą, która z pliku daje liczbę: wtręty obce, słowa na segment, wypowiedzi w kanale „Ja", R² odsłuchu, korelacja kanałów, klastry i pary re-ID | procedura policzona na **istniejących** transkryptach odtwarza liczby z rozdz. 13 (np. 57 wtrętów OpenWhispr, 1 u Narady) i z rozdz. 17 (39 i 53 wypowiedzi w kanale „Ja"). Jeśli nie odtwarza, metryka jest zła |
| 0.3 | Kontrakt wyraża trzech dostawców bez wycieku | tabela z §2.3 wypełniona. Żadna komórka nie wymaga typu konkretnego dostawcy |

### Etap 1: Nagrywanie i archiwum dwukanałowe

**Zakres:**
- Capture: tap (P5), mikrofon surowy + po AEC platformowym (rozdz. 7, 12), trzy obserwatory
  urządzeń, kotwice;
- Archive: kodowanie, manifest, rejestr nośników, retencja, sprzątanie sierot;
- Import;
- minimalne UI z przyciskiem nagrywania;
- E3.

**Zależy od:** nic (etap 0 może biec równolegle).

| # | Kryterium akceptacji | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 1.1 | 🔴 Plik odsłuchowy = tap systemowy, bez domieszki mikrofonu | regresja `odsłuch ≈ a·system + b·mic` (metoda z rozdz. 18) na pliku, który **faktycznie odtwarza odtwarzacz**: a ≥ 0,999, \|b\| ≤ 0,01, R² ≥ 0,99, także gdy użytkownik mówi | Narada: 1.000 / −0.001 / 1.000 i 1.000 / 0.010 / 0.993 (rozdz. 18) |
| 1.2 | 🔴 Rozjazd ścieżek jest znany z kotwic, a nie zakładany | podcast przez głośniki: przesunięcie wyliczone z kotwic vs zmierzone korelacją krzyżową `mic_raw`↔`system`. Różnica ≤ 10 ms (**nasz budżet**). Opóźnienie startu mikrofonu zapisane w logu | próg słyszalności ~40 ms (W§1). Narada: 165 ms (rozdz. 18). Spokenly: ~2 s (rozdz. 17) |
| 1.3 | AEC działa naprawdę, a nie tylko według etykiety w kodzie | korelacja `mic_aec`↔`system` przy podcaście przez głośniki ≤ 0,15 | 0,12 (K:krok 9, rozdz. 7) |
| 1.4 | Kanały nie przeciekają | sam głos, bez dźwięku systemowego → kanał systemowy to cisza cyfrowa | −180 dB (K:krok 9) |
| 1.5 | Przepięcie słuchawek nie urywa nagrania | 10 min nagrania, w trakcie przepięcie słuchawek i zmiana domyślnego wejścia. Żadna ścieżka nie ma przerwy > 1 s, zdarzenie jest w manifeście | W§1 🆕, rozdz. 18 |
| 1.6 | 🔴 Teams przez zwykły tap | prawdziwa rozmowa w Teams → kanał systemowy niesie głos rozmówców (mediana poziomu ≫ cisza cyfrowa) | W§7 |
| 1.7 | Archiwum jest odporne na przerwanie i spójne | `kill -9` w 30. minucie → po restarcie surowe PCM odzyskane i zarchiwizowane. Potem „usuń wszystko" → `find` nie znajduje żadnego pliku audio. Zero wskaźników do nieistniejących plików i zero plików bez wskaźnika | K:R25, K:F1, K:F2, K:R15 |
| 1.8 | 85 min nagrania: długości plików zgadzają się z kotwicami | różnica długości ścieżek = zmierzone opóźnienie startu ± 10 ms | Narada: 901,269 s vs 901,056 s (rozdz. 18) |
| 1.9 | **E3:** kodek archiwum nie psuje ponownego przebiegu | 26-min WFM: transkrypcja z PCM vs z pliku zakodowanego, przez **istniejącą** aplikację (import pliku we FluidVoice, jak w rozdz. 13). Różnica słów ≤ 1% → kodek zatwierdzony. Większa → wyższy bitrate | W§7: Opus 32 kbps ~14 MB/h/kanał, AAC 128 kbps 79 MB/85 min |

### Etap 2: Sesja i kalendarz

**Zakres:**
- EventKit, nadchodzące spotkania, oś dni;
- start ręczny albo ze zdarzenia;
- warunki końca: koniec zdarzenia + margines, cisza > N min (P10), przycisk;
- izolacja stopu od błędów archiwum;
- pływające okno w wersji minimalnej.

**Zależy od:** etap 1.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 2.1 | 🔴 Sesja kończy się sama | scenariusz z rozdz. 17: 15 min treści, potem hałas w pokoju. Sesja powiązana ze zdarzeniem kończy się ≤ margines po jego końcu. Ogon w archiwum ≤ margines | MacParakeet: 70 min śmieci (rozdz. 17) |
| 2.2 | Cisza kończy sesję bez kalendarza | 15 min treści + cisza → koniec po N min ± 5 s, przyczyna w manifeście | W§1 🔴 |
| 2.3 | Początek nie ginie | czas od kliknięcia do pierwszej ramki w **obu** ścieżkach, z kotwic ≤ 1 s (**nasz budżet**) | autodetekcja: rozrzut 1:22–3:54 (rozdz. 13) |
| 2.4 | Błąd archiwum nie gubi spotkania | wstrzyknięty wyjątek w kodowaniu → sesja zamknięta, PCM zachowane, przetwarzanie rusza. Test przechodzi mutację | K:F3 |

### Etap 3: Warstwa dostawców, ASR lokalny, bramka, profil

**Zakres:**
- kontrakty z §2.3 wdrożone;
- adapter FluidAudio (ASR + VAD) albo, po E1, sidecar B;
- ModelStore;
- profile bez `auto`;
- bramka per kanał z odrzucaniem przesłuchu;
- Pipeline wsadowy z postępem;
- przebiegi wersjonowane;
- minimalny ekran modeli.

**Zależy od:** etap 0 (E1), etap 1.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 3.1 | 🔴 Milczący mikrofon nie produkuje tekstu | debata odtwarzana przez głośniki i przechwytywana na żywo, użytkownik milczy (metoda z rozdz. 17). Wypowiedzi w kanale „Ja" ≤ 2 | MacParakeet: 53, OpenWhispr: 39 (rozdz. 17). Kanał mikrofonu OpenWhispr: 82% halucynacji (rozdz. 13) |
| 3.2 | Brak obcojęzycznych wtrętów | 26-min WFM (import): ≤ 2 | Narada 1, FluidVoice bez AI 1, OpenWhispr 57 (rozdz. 13) |
| 3.3 | Kompletność | ten sam plik co FluidVoice w rozdz. 13: liczba słów ≥ 95% wyniku FluidVoice bez AI | ~2450 (rozdz. 13) |
| 3.4 | Czytelność | mediana słów na segment ≥ 20 (**nasz budżet**) | MacParakeet 48, Narada 6 (rozdz. 13) |
| 3.5 | 🔴 Język jawny i związany z modelem | spotkanie 10:48 z profilem PL: 0 akapitów czysto angielskich. Profilu bez języka nie da się utworzyć ani w UI, ani w danych (test przechodzi mutację). Język i model widoczne **przed** startem | 22 z 35 akapitów po angielsku przy `en` (rozdz. 14) |
| 3.6 | Powtarzalność | ten sam plik i profil dwa razy → identyczny tekst | ten sam plik dał dwa różne wyniki (rozdz. 14) |
| 3.7 | Szybkość, postęp, cache | 85 min ≤ 60 s (**nasz budżet**). Postęp w % monotoniczny od 0 do 100. Cache ANE po przebiegu ≤ budżet P2 (powtórzenie E1 na **naszej** aplikacji) | FluidVoice: 26 min w 6,5 s (rozdz. 13). Cache: rozdz. 10 |
| 3.8 | Zły wariant nie przechodzi po cichu | podmiana pliku modelu w kopii testowej magazynu → aplikacja odmawia i pokazuje przyczynę. Ekran modeli pokazuje nazwę, rozmiar i znacznik „Multilingual" | 4 z 5 aplikacji nie pokazują wariantu (rozdz. 16) |
| 3.9 | Granica abstrakcji trzyma | lista importów: FluidAudio występuje **wyłącznie** w module adaptera | rozdz. 9 |

### Etap 4: Diaryzacja, łączenie, mówcy

**Zakres:**
- adapter diaryzacji FluidAudio na całym kanale systemowym;
- próg w UI, default „raczej za dużo klastrów";
- łączenie po czasie;
- rejestr mówców z edycją.

**Zależy od:** etap 3.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 4.1 | 🔴 Próg daje raczej za dużo klastrów niż za mało | debata: 9–16 klastrów na ~11 osób. Scalenia różnych osób ≤ 1 | 1 / 2 / 10 klastrów na tej samej bibliotece (rozdz. 17) |
| 4.2 | Re-identyfikacja | pary wejść z rozdz. 17 (Hoffman, Gosek-Popiołek, Piątkowska, Gibała, każda para ~10 min od siebie) → każda para w jednym klastrze | MacParakeet trafił 4 z 4 pary (rozdz. 17) |
| 4.3 | Długie nagranie się nie rozpada | 73 min jednej osoby → ≤ 3 klastry | sherpa-onnx: 46 (rozdz. 8) |
| 4.4 | Diaryzacja nie psuje ASR | tekst transkryptu **bajt w bajt identyczny** z diaryzacją i bez niej | FluidVoice z diaryzacją: 1 → 16 wtrętów (rozdz. 13) |
| 4.5 | Zmiana progu nie wymaga ponownego ASR | nowy przebieg diaryzacji na tym samym przebiegu ASR; wynik zapisany jako nowa wersja | zasada 8 |
| 4.6 | 🔴 Edycja propaguje się do końca | scalenie dwóch klastrów w UI → transkrypt i (w etapie 7) notatka pokazują jedną osobę | W§4, W§5 |
| 4.7 | Diaryzacja nie waży | przyrost cache'u ANE od diaryzacji ≤ 50 MB (**nasz budżet**) | kilobajty (rozdz. 10) |

### Etap 5: ASR przez API (dowód, że abstrakcja działa)

**Zakres:**
- adapter MAI-Transcribe-2: cięcie ≤ 60 s na granicach ciszy z bramki, scalanie po znacznikach
  słów, jawne `language: pl`, `phraseList` ze słownika, **bez** diaryzacji API;
- oznaczenie w UI, że audio opuszcza komputer.

**Zależy od:** etap 3. Kolejność etapów 4 i 5 jest wymienna.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 5.1 | Dodanie drugiego dostawcy nie rusza reszty | `git diff --stat` etapu: zmiany tylko w module adaptera i przy jego rejestracji | rozdz. 9 |
| 5.2 | Cięcie nie gubi i nie dubluje słów | 26-min WFM: w oknie ±2 s wokół każdej granicy cięcia liczba słów zgadza się z przebiegiem lokalnym ± 1 | limit 60 s (rozdz. 11) |
| 5.3 | Jakość, język, 🔴 brak diaryzacji po stronie API | wtręty obce ≤ 2, język `pl` w metadanych. W dzienniku żądań ani jedno nie zawiera opcji diaryzacji | rozdz. 11, 14; W§2 |
| 5.4 | Koszt zgodny z deklaracją | koszt przebiegu z rozliczenia ≈ 0,10 USD/h | rozdz. 11 |
| 5.5 | „Test" sprawdza możliwość wywołaniem | przycisk testu na ekranie modeli wysyła prawdziwe krótkie audio. Klucz bez dostępu → czytelny błąd, a nie „dostępny" | katalog myli w obie strony (rozdz. 11, 19) |

### Etap 6: Widok spotkania

**Zakres:**
- linia czasu i odtwarzacz;
- klik w słowo → skok;
- edycja słowa;
- pełny ekran modeli;
- pływające okno z profilem.

**Zależy od:** etapy 3–4.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 6.1 | Klik trafia w miejsce | 20 losowych słów, w tym ≥ 5 z kanału „Ja", który ma inną kotwicę. Błąd pozycji odtwarzania ≤ 300 ms (**nasz budżet**) | ryzyko M4 (rozdz. 17, 18) |
| 6.2 | Postęp na długim pliku | 85 min: widoczny postęp w %, bez zamrożenia UI | W§1 ⚠️ |
| 6.3 | Profil przed startem | wybór języka i modelu w pływającym oknie. Start bez wybranego profilu jest niemożliwy | W§6 🆕, rozdz. 14 pkt 4 |

### Etap 7: Notatki i eksport

**Zakres:**
- korekta i podsumowanie (osobne prompty);
- struktura z W§4;
- ID mówców w wejściu i w schemacie wyjścia;
- surowy ASR zachowany obok korekty;
- eksport do markdown;
- dostawca lokalny albo zdalny.

**Zależy od:** etap 4.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 7.1 | 🔴 Kto co obiecał | debata: obietnica strefy gospodarczej 200 ha i obietnica zadaniowania urzędników przypisane **dwóm różnym** osobom. Każde zadanie ma właściciela, który istnieje w rejestrze mówców | Wispr Flow przypisał je jednemu `Speaker 2` (rozdz. 17) |
| 7.2 | Korekta nie konfabuluje | wtręty obce po korekcie ≤ przed. Liczba słów ±10%. Każde zdanie po korekcie ma zakotwiczenie czasowe w transkrypcie źródłowym | płynna konfabulacja „wygląda na wiedzę" (rozdz. 14) |
| 7.3 | Linia czasu działa po korekcie | kryterium 6.1 powtórzone na tekście po korekcie | zasada 2 |
| 7.4 | Dostawcy tekstu są wymienni | ta sama notatka przez Ollama/oMLX i przez OpenRouter; zmiana tylko w konfiguracji | rozdz. 19 |

### Etap 8: Słownik i pętla uczenia

**Zakres:**
- import 166 terminów i 223 par jako aliasów;
- kompilatory: boosting FluidAudio (W§3), `phraseList` (rozdz. 11), korekta po ASR;
- „klik → poprawka → zapamiętaj".

**Zależy od:** etapy 3, 5, 6.

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 8.1 | Boosting pomaga i nie szkodzi | 26-min WFM: trafienia terminów domenowych (np. „INU-90", nazwiska, rozdz. 13) po ≥ przed. Nowych wtrętów obcych: 0 | W§3 |
| 8.2 | Test broni aliasu | mutacja: usunięcie aliasu przywraca błąd w tym samym pliku | rozdz. 1 |
| 8.3 | Pętla uczenia się domyka | alias dodany kliknięciem działa w następnym przebiegu tego samego pliku, a wersja słownika jest w metadanych przebiegu | W§3 🆕 |

### Etap 9: Dyktowanie

**Zakres:**
- skrót klawiszowy → nagranie → bramka → ASR (profil, krótkie okno) → wstawienie tekstu;
- słownik.

⚠️ Mechanizm wstawiania tekstu do innych aplikacji nie był mierzony.

**Zależy od:** etap 3 (może ruszyć tuż po nim, P7).

| # | Kryterium | Jak zmierzyć | Punkt odniesienia |
|---|---|---|---|
| 9.1 | Polski | „raz dwa trzy" → polski tekst | model angielski dawał „Ras dwaire Pindish" (rozdz. 4) |
| 9.2 | Cisza nie pisze | wciśnięty skrót bez mowy → 0 znaków | rozdz. 13 |
| 9.3 | Opóźnienie | 20 tych samych fraz w naszej aplikacji i we FluidVoice (ten sam v3, rozdz. 16). Mediana opóźnienia od puszczenia klawisza do tekstu ≤ 1,2× FluidVoice (**nasz budżet**) | FluidVoice |

### Etap 10: Domknięcie v1

Przegląd całości gałęzi, bo najpoważniejsze defekty wychodzą dopiero z zestawienia (rozdz. 2,
K:F1–F4). Końcowy pomiar budżetów (§3.0). Pełny przebieg korpusu przez wszystkie kryteria
etapów 1–9 na tej samej wersji.

---

## 4. Ryzyka

| # | Ryzyko | Źródło | Zabezpieczenie | Sprawdzane w |
|---|---|---|---|---|
| 1 | Płynna konfabulacja przy złym języku | rozdz. 14 | profil „model + język" bez `auto` w modelu danych; język widoczny przed startem | 3.5, 3.6, 6.3 |
| 2 | Halucynacje na ciszy w kanale mikrofonu | rozdz. 13, 17 | bramka per kanał, cisza nie trafia do modelu | 3.1, 9.2 |
| 3 | Przesłuch głośników do mikrofonu | rozdz. 7, 15, 17 | AEC platformowy + odrzucanie okien skorelowanych z kanałem systemowym | 1.3, 3.1 |
| 4 | Miks nieodwracalnie niszczy odsłuch | rozdz. 18 | miks nie jest zapisywany; odsłuch = plik tapu | 1.1 |
| 5 | Rozjazd startu ścieżek (165 ms, ~2 s) | rozdz. 17, 18 (M4) | kotwica hosta per ścieżka, wszystko w czasie sesji | 1.2, 1.8, 6.1 |
| 6 | Przepięcie urządzenia urywa nagranie | W§1, rozdz. 18 | trzy obserwatory, zdarzenie w manifeście | 1.5 |
| 7 | Sesja bez końca | rozdz. 17 | warunki mechaniczne końca | 2.1, 2.2 |
| 8 | Utracony początek spotkania | rozdz. 13 | w v1 start ręczny albo z kalendarza, bez autodetekcji | 2.3 |
| 9 | Za wysoki próg scala osoby | rozdz. 17 | próg nastawialny, default nadmiarowy, scalanie w UI | 4.1, 4.6 |
| 10 | Nadmierne klastrowanie długich nagrań | rozdz. 8, 12 | test na 73 min, próg dostrajany na długim nagraniu | 4.3 |
| 11 | Diaryzacja psuje ASR przez segmentację | rozdz. 13 | ASR i diaryzacja niezależne, łączone po czasie | 4.4 |
| 12 | Diaryzacja na kawałkach traci tożsamość | rozdz. 11 | kontrakt: diaryzacja zawsze lokalnie, na całym kanale | 5.3, §2.3 |
| 13 | Streszczenie gubi tożsamość mówcy | rozdz. 17, W§4 | ID mówców w wejściu i w schemacie wyjścia | 7.1 |
| 14 | Korekta AI dopisuje treść | rozdz. 14 | surowy ASR zachowany; zakotwiczenie czasowe; metryki przed i po | 7.2 |
| 15 | Aplikacja po cichu jedzie na złym wariancie modelu | rozdz. 4, 16 | ekran modeli, suma kontrolna, test prawdziwym wywołaniem | 3.8, 5.5 |
| 16 | Katalog deklaruje możliwość, której runtime nie ma (albo odwrotnie) | rozdz. 11, 19 | możliwość potwierdzana wywołaniem | 5.5 |
| 17 | Cache ANE w gigabajtach | rozdz. 10 | E1 przed etapem 3; budżet ciągły; rozmiar pokazywany na ekranie modeli | 0.1, 3.7 |
| 18 | Wspólny magazyn zmieniony przez inną aplikację | W§0, rozdz. 16 | tylko odczyt, suma kontrolna, scenariusz S4 (B§7) | 3.8 |
| 19 | Łamiące wydanie FluidAudio | W§7 | przypięta wersja; FluidAudio tylko w adapterze; S1–S3 (B§7) | 3.9 |
| 20 | Limit 60 s w API | rozdz. 11 | cięcie w adapterze na granicach ciszy, scalanie po słowach | 5.2 |
| 21 | Surowe nagranie skasowane przed zakodowaniem albo plik bez wskaźnika | K:R25, K:F2 | zasada 7 jako niezmiennik | 1.7 |
| 22 | „Usuń wszystko" nie zna archiwum; retencja sprzężona; wiszące wskaźniki | K:F1, K:R14, K:R15 | rejestr nośników, retencja per nośnik, czyszczenie wskaźników | 1.7 |
| 23 | Błąd archiwum przerywa stop i gubi transkrypt | K:F3 | izolacja w module Session | 2.4 |
| 24 | AEC platformowy przycina mówiącego albo startuje ponad sekundę | rozdz. 7, 17 | archiwizujemy też `mic_raw` (jak Narada, rozdz. 18), więc AEC można powtórzyć; opóźnienie startu mierzone kotwicą | 1.2, 1.3 |
| 25 | Teams nie trafia do tapu | W§7 | test na prawdziwej rozmowie | 1.6 |
| 26 | ⚠️ ASR z archiwum stratnego gorszy niż z PCM | **brak źródła, niezmierzone** | E3; pierwszy przebieg idzie z PCM | 1.9 |
| 27 | Zielone testy, które niczego nie dowodzą | rozdz. 1 | mutacja + pomiar na korpusie | każdy etap |
| 28 | Defekty w planie, a nie w wykonaniu | rozdz. 2 | przegląd przed etapem, przegląd całości po etapie | każdy etap, etap 10 |
| 29 | Dwa runtime'y i natywne binarki (tylko w wariancie B) | rozdz. 4 | B wyłącznie jako wyjście awaryjne, z parytetem E2 | B§5 |

---

## 5. Mapa: wymaganie 🔴 → gdzie w planie

| Wymaganie 🔴 | Źródło | Gdzie zaadresowane |
|---|---|---|
| Cohere Transcribe jest lokalnie, nie tylko przez API | W§0 | ModelStore i profile (§2.2). W v1 odłożony (§1.2, B§8 P4). Sprawdzenie E0e |
| Plik do odsłuchu = tap systemowy bit w bit, mikrofon osobno, nigdy miks | W§1 | zasada 1, moduł Archive, kryterium 1.1. Odsłuch zmiksowany odłożony (§1.2) |
| Znacznik czasu hosta osobno dla każdej ścieżki | W§1 | zasada 2, Capture, §2.5, kryteria 1.2, 1.8, 6.1 |
| Koniec sesji z warunkiem mechanicznym | W§1 | moduł Session, kryteria 2.1, 2.2 |
| Bramka mowy per kanał przed ASR | W§1 | kontrakt „Bramka mowy" (§2.3), kryteria 3.1, 9.2 |
| Diaryzacja zawsze lokalnie | W§2 | zakaz w kontrakcie (§2.3), etap 4, kryterium 5.3 (API bez diaryzacji) |
| Język jawny, związany z modelem, nigdy auto | W§2 | zasada 9, profile, kryteria 3.5, 3.6, 6.3 |
| Ollama i oMLX nie robią ASR | W§2 | adapter AI obsługuje tylko tekst (§2.2); odrzucone w B§1 |
| Word boosting istnieje i działa | W§3 | moduł Vocabulary, etap 8 |
| Stabilna tożsamość mówcy aż do poziomu zadań | W§4 | moduł Speakers, kryteria 4.6, 7.1 |
| Próg klastrowania nastawialny, default „raczej za dużo" | W§5 | etap 4, kryteria 4.1–4.3 |
| Teams: własny ASR, a nie natywne napisy | W§7 | tap bez osobnej ścieżki dla Teams, kryterium 1.6 |

---

## 6. Czego plan świadomie NIE rozstrzyga

| Sprawa | Dlaczego nie teraz | Kiedy i czym |
|---|---|---|
| ScreenCaptureKit czy process tap | pytanie P5, wpływa na próg macOS | przed etapem 1 |
| Kodek i bitrate archiwum | brak pomiaru wpływu na ASR | E3, kryterium 1.9 |
| Wartości N (cisza) i marginesu po końcu zdarzenia | zależą od nawyków użytkownika | P10, strojone w etapie 2 |
| Domyślna **wartość** progu klastrowania | musi wyjść z pomiaru na korpusie (rozdz. 17) | etap 4 |
| Technologia magazynu danych i framework UI | brak źródeł. Wymogi: rejestr nośników, przebiegi wersjonowane | start etapu 1 |
| Mechanizm wstawiania tekstu przy dyktowaniu | niezmierzony | etap 9 |
| Dostawca i model AI do notatek | tania i odwracalna decyzja (rozdz. 12, pkt 4) | etap 7 |
| Spotkania na miejscu (kilka osób przy jednym mikrofonie) | W§5 zakłada, że mikrofon = „Ja" | kontrakt diaryzacji przyjmuje dowolny kanał, więc to rozszerzenie po v1 |
| Spotkania mieszane PL/EN | profil ma jeden język. MAI umie przełączać język w trakcie wypowiedzi (rozdz. 11), ale to łamie zasadę „nigdy auto" | po v1, osobna decyzja |
| Dystrybucja (podpis, sandbox, App Store) | zależy od P3 z B§8 | po v1 |

---

## 7. Pytania wymagające decyzji

Pytania P1–P4 (silnik, budżet ANE, dystrybucja, Cohere) są w `brainstorm-asr.md` §8.

| # | Pytanie | Rekomendacja | Uzasadnienie |
|---|---|---|---|
| **P5** | Tap: ScreenCaptureKit (macOS 14.2) czy process tap Core Audio (API od 14.4)? | **Process tap** | To droga Narady: najlepsze nagranie w pomiarach (rozdz. 17), odsłuch zgodny z tapem bit w bit (rozdz. 18), paczka 98 MB bez linkowania ScreenCaptureKit (rozdz. 6) |
| **P6** | Minimalny macOS | **Wersja, na której przejdzie etap 1**, na start Twoja maszyna. Obniżać dopiero po teście | Narada wymaga 15.6 mimo API od 14.4, z nieznanego powodu (rozdz. 6). Deklarowanie niższego progu bez testu to zgadywanie |
| **P7** | Dyktowanie w v1 czy w v1.1? | **v1**, ostatni etap, dopuszczalne przesunięcie tuż za etap 3 | Korzysta z tych samych dostawców, bramki i słownika. Krótkie okno sprawdza drugi tryb kontraktu |
| **P8** | Czy pliki korpusu (rozdz. 13, 14, 17, nagranie 73 min, krok 9) nadal istnieją? | **Zebrać je w etapie 0.** Brakujące nagrać ponownie metodą z rozdz. 17 | Bez nich kryteria etapów 3–7 tracą punkt odniesienia |
| **P9** | Retencja archiwum audio | **Domyślnie bez automatycznego kasowania**, zużycie miejsca widoczne w UI, retencja per nośnik dostępna | Archiwum jest źródłem prawdy (rozdz. 5, 17). Przy Opusie 32 kbps to ~14 MB/h na kanał (W§7). W forku było 14 dni (K:R16) |
| **P10** | Po ilu minutach ciszy kończyć sesję i jaki margines po końcu zdarzenia | **10 min ciszy, 5 min marginesu**, obie wartości nastawialne | Kalendarz jest warunkiem głównym. Cisza to bezpiecznik przeciw 70-minutowemu ogonowi (rozdz. 17). Krótszy próg ryzykuje ucięcie długiej pauzy |
| **P11** | Archiwizować `mic_raw` obok `mic_aec`? | **Tak** | Tak robi Narada (rozdz. 18). Dzięki temu decyzja o AEC jest odwracalna (rozdz. 7), kosztem ~14 MB/h (W§7) |
| **P12** | Transkrypt na żywo w trakcie spotkania w v1? | **Nie** | Diaryzacja potrzebuje całego kanału (rozdz. 11), a przebieg wsadowy trwa sekundy (rozdz. 13) |
