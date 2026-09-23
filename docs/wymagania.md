# Wymagania — aplikacja do notatek ze spotkań i dyktowania

Scalenie dwóch źródeł:

- **wymagania biznesowe** (rozmowa 2026-09-23) — co ma robić
- **pomiary techniczne** (sesja GCX, 2026-09-23) — co się da i czego nie wolno
  → `/Users/michalprzytulski/GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md`
  (18 rozdziałów, pomiary na 6 aplikacjach — **nie powtarzaj tych badań**)

Oznaczenia: ✅ potwierdzone pomiarem · ⚠️ ograniczenie · 🔴 zmienia wymaganie · 🆕 dochodzi z pomiarów

---

## 0. Co już mamy — nie budujemy od zera

| Zasób | Gdzie | Uwagi |
|---|---|---|
| Model ASR wielojęzyczny | `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3` | 461 MB, **już pobrany**, polski 7,31% WER na FLEURS |
| Modele diaryzacji | ten sam magazyn, `speaker-diarization/` | 21 MB (segmentacja + embedding + PLDA + FBank) |
| Cohere Transcribe lokalnie | ten sam magazyn, `cohere-transcribe/` | 2,0 GB — 🔴 **jest lokalnie, nie tylko przez API** |
| Słownik domenowy PL+EN | `GCX/dictation/` | 166 terminów + **223 pary „źle → dobrze"** |
| Wzorzec formatu boostingu | `~/Library/Application Support/FluidVoice/parakeet_custom_vocabulary.json` | patrz §3 |
| Wzorzec architektury nagrywania | Narada, zmierzona (rozdz. 18) | patrz §1 |

Magazyn `FluidAudio/Models/` jest **wspólny** dla MacParakeet, Narady, FluidVoice i Spokenly.
Nasza aplikacja może z niego korzystać bez ponownego pobierania.

---

## 1. Nagrywanie i transkrypcja

- **Nagrywanie spotkań: audio systemowe + mikrofon, bez bota** ✅
  Potwierdzone pomiarem, że to działa — i **jak** ma działać (poniżej).
- 🔴 **Plik do odsłuchu = tap systemowy bit w bit. Mikrofon w osobnym pliku. Nigdy miks.**
  Zmierzone: Narada `odsłuch = 1.000·system + (−0.001)·mikrofon`, R² = **1.000**.
  MacParakeet `0.060·system + 0.505·mikrofon` przy rozjeździe 240 ms → „echo jak w łazience".
  **Z miksu nie da się już wyjąć czystego strumienia** — to wada nieodwracalna.
- 🔴 **Znacznik czasu hosta zapisywany osobno dla każdej ścieżki.**
  Mikrofon rusza **165 ms** po tapie (koszt startu `AVAudioEngine`, zmierzone w logu Narady),
  u Spokenly rozjazd sięgnął **2 s**. Powyżej ~40 ms jest słyszalny.
- 🆕 ⚠️ **Tap wiąże się z konkretnym urządzeniem wyjściowym** (`outputUID=BuiltInSpeakerDevice`).
  Trzeba obserwować zmianę domyślnego wejścia, wyjścia i listy urządzeń — inaczej przepięcie
  słuchawek w trakcie spotkania urywa nagranie. Narada instaluje trzy obserwatory.
- 🆕 🔴 **Koniec sesji musi mieć warunek mechaniczny**, nie tylko przycisk.
  MacParakeet dokleił **70 minut** przypadkowego dźwięku do 15 minut spotkania.
  Warunki: koniec wydarzenia w kalendarzu, zamknięcie okna rozmowy, cisza dłuższa niż N minut.
- 🆕 🔴 **Bramka mowy per kanał przed ASR.** Dwa osobne tryby awarii, oba zmierzone:
  cichy mikrofon → **82% halucynacji**; przesłuch z głośników → urywki cudzych zdań
  wstawiane w środek zdań rozmówcy (52 z 53 wtrąceń ≤3 słowa).
- **Dyktowanie: osobny tryb na żywo** ✅
- **Klikalna linia czasu → skok w nagraniu** ✅ (archiwum i tak musi istnieć, patrz §0)
- **Postęp transkrypcji w procentach** ✅ — ⚠️ musi działać na plikach >80 min; testowe
  nagrania miały 85 minut.

## 2. Konfiguracja modeli

Dwa **niezależne** wybory silnika: ASR i AI. Tu wymagania trzymają się w całości, z poprawkami:

- **ASR lokalnie:** Parakeet TDT v3 (461 MB, już na dysku) albo Cohere Transcribe (2,0 GB).
- **ASR przez API:** ⚠️ **MAI-Transcribe-2 ma limit 60 s na żądanie.**
  To wyklucza diaryzację po stronie API. `microsoft/mai-transcribe-2` na OpenRouterze,
  ~0,10 USD/h, polski wspierany.
- 🔴 **Diaryzacja zawsze lokalnie** — konsekwencja powyższego limitu.
- 🆕 🔴 **Język wybierany jawnie i związany z modelem. Nigdy auto-detekcja.**
  Zmierzone: polskie spotkanie z `Language: en` dało **62% zmyślonej angielszczyzny**,
  czytającej się jak prawdziwa notatka. Ten sam plik w dwóch przebiegach dał dwa różne wyniki.
  To najgroźniejszy tryb awarii notatnika, bo **wygląda na wiedzę**.
- 🆕 **Wybrany wariant modelu widoczny w UI** — nazwa, rozmiar, znacznik „Multilingual",
  przycisk testu. Wzór: ekran modeli Spokenly. Cztery z pięciu testowanych aplikacji tego
  nie pokazują i przez to milcząco jadą na złym modelu.
- ⚠️ **Ollama / oMLX jako silnik ASR — do zweryfikowania przed wpisaniem w zakres.**
  Ollama serwuje modele językowe; obsługi ASR nie sprawdzaliśmy. Do AI (korekta,
  podsumowanie) jest bez zastrzeżeń.
- 🆕 ⚠️ **Rozmiar instalacji to polityka modeli, nie technologia.** „8 GB" przypisywane
  Naradzie to `com.apple.e5rt.e5bundlecache` — cache kompilacji Apple Neural Engine,
  generowany lokalnie przy pierwszym uruchomieniu. Sama Narada waży 98 MB.
- **System prompt / AI instruction, osobno dla korekty i podsumowania** ✅

## 3. Słownictwo i personalizacja

🔴 **Korekta założenia z wymagań.** Zapisano tam, że *„żadna z testowanych appek tego nie
dawała"*. Word boosting **jest** na tym stosie i działa:

```json
// ~/Library/Application Support/FluidVoice/parakeet_custom_vocabulary.json
{ "alpha": 2.8, "minCtcScore": -2.2, "minSimilarity": 0.72,
  "minCombinedConfidence": 0.64, "minTermLength": 3,
  "terms": [ { "text": "FluidVoice", "aliases": ["fluid voice","fluid boys"], "weight": 10.0 } ] }
```

Binarki: FluidVoice ma `customVocabulary` i `vocabularyBoostingEnabled`, Spokenly
`vocabularyBoosting` i `biasing`. To funkcja FluidAudio, nie autorski hack.

Dwa wnioski:

1. **Pole `aliases` to dokładnie nasz format** `replacements.tsv` (223 pary „co usłyszał →
   co miało być"). Słownik z `GCX/dictation/` przenosi się prawie jeden do jednego.
2. **Brakującym elementem nie jest boosting, tylko pętla uczenia się** — klik na słowo →
   poprawka → dopisanie aliasu do słownika. To jest realna nowość w naszej aplikacji.

- **Dodawanie własnych słów** ✅ — mechanizm istnieje, nie wymaga trenowania
- **Klik na słowo → poprawka → zapamiętanie** 🆕 to jest ta część do napisania
- **Pamięć korekt:** rosnąca lista aliasów + przykłady „źle → dobrze" w promptcie modelu
  korygującego. Fine-tuning dopiero gdy to nie wystarczy.

## 4. Notatki, chat i zadania

- **Automatyczne notatki ze strukturą** (temat, ustalenia, zadania z właścicielem, pytania
  otwarte) ✅
- 🆕 🔴 **Notatka musi nieść stabilną tożsamość mówcy aż do poziomu zadań.**
  Wispr Flow zwrócił merytorycznie poprawne streszczenie, w którym `Speaker 2` to były
  **dwie różne osoby**, a nazwiska zniknęły. Przy trzech osobach do przełknięcia; przy
  dziesięciu streszczenie przestaje odpowiadać na jedyne sensowne pytanie — kto co obiecał.
  **Bez tego zakładka zadań nie ma z czego powstać.**
- **Chat nad jednym spotkaniem i nad archiwum (RAG)** ✅
- **Zakładka zadań** ✅ — zależna od punktu wyżej

## 5. Organizacja spotkań

- **Kalendarz Apple przez EventKit** ✅ — 🆕 **i to samo zdarzenie daje mechaniczny warunek
  końca sesji** z §1. Jedna integracja załatwia dwie rzeczy.
- **Nadchodzące spotkania, oś czasu z podziałem na dni** ✅
- **Edycja rozmówców** ✅ — wymaga diaryzacji, a tam:
  - 🆕 🔴 **Próg klastrowania nastawialny, default „raczej za dużo klastrów niż za mało".**
    Ta sama biblioteka i model dały na debacie 10 osób: **1** mówcę (OpenWhispr), **2**
    (Narada), **10** (MacParakeet). Próg siedzi w kodzie aplikacji — `config.json` modelu
    jest pusty. Scalonych osób **nie rozdzielisz po fakcie**; rozdzielone łączysz kliknięciem.
  - 🆕 **Automatyczne nazwiska są w zasięgu:** gdy prowadzący wywołuje kogoś po nazwisku,
    da się związać nazwisko z następnym klastrem. Narada bezbłędnie rozpoznała tego samego
    mówcę po 10 minutach przerwy — re-identyfikacja nie jest problemem, próg jest.
  - 🆕 **Dwa kanały dają podział „ja / oni" za darmo**, bez modelu. Diaryzacja potrzebna
    tylko wewnątrz kanału systemowego.

## 6. UI i integracje

- **Pływające okno** ✅ — 🆕 **to jest miejsce na wybór języka i modelu** (§2), a nie tylko
  przycisk nagrywania
- **MCP dla Claude** ✅ · **pliki markdown z podsumowaniem** ✅

---

## 7. Otwarte pytania — z tym, co wiemy

**Nagrywanie ekranu w v1?**
Wkład liczbowy: 85 minut audio to **79 MB** w AAC 128 kbps, a przy Opusie 32 kbps mono
~14 MB/h na kanał. Wideo to inny rząd wielkości — przechwytywanie, magazyn i odtwarzanie.
Rekomendacja: **v1 audio-only**, ekran dopiero gdy reszta stoi.

**Transkrypcja Teams: własny ASR czy natywne napisy?**
🔴 **Własny ASR.** Dowód: Teams instaluje wirtualne urządzenie wyjściowe
`MSLoopbackDriverDevice_UID`, widoczne w logu Narady jako zwykłe urządzenie obok głośników
i HDMI. **Tap systemowy złapie je tak samo jak każde inne** — nie trzeba osobnej ścieżki dla
Teams, a aplikacja działa na dowolnym audio systemowym. Napisy Teams wiążą z jednym dostawcą
i nie dają nagrania do ponownego przebiegu.

**Nowe, do rozstrzygnięcia:**

- **Ollama/oMLX jako ASR** — czy w ogóle to potrafią (§2)
- **Czy budować na FluidAudio (Swift), czy własna ścieżka** — FluidAudio daje gotowy
  Parakeet v3, diaryzację, VAD i boosting słownika, wszystko w CoreML i już na dysku.
  Koszt: wiązanie ze Swiftem i z cudzym harmonogramem wydań.
- **Czy odsłuch ma mieć wersję zmiksowaną** (obie strony w jednym pliku) — jeśli tak, to
  **po wyrównaniu**, a oryginały zostają.
