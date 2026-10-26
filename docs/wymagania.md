# Wymagania — aplikacja do notatek ze spotkań i dyktowania

Scalenie dwóch źródeł:

- **wymagania biznesowe** (rozmowa 2026-09-23) — co ma robić
- **pomiary techniczne** (sesja GCX, 2026-09-23) — co się da i czego nie wolno
  → `/Users/michalprzytulski/GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md`
  (19 rozdziałów, pomiary na 6 aplikacjach — **nie powtarzaj tych badań**)

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

🆕 ⚠️ **Układ magazynu FluidAudio a ten pin (zmierzone w F20 S0, 2026-10-20;
[raport](superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md) §5, §7.2)** — dopisek do powyższego, nie jego poprawka:
- Aplikacja (FluidAudio przypięte do 0.17.7, Parakeet v3, enkoder `int8`) szuka folderu **`parakeet-tdt-0.6b-v3`**
  z plikiem `JointDecisionv3.mlmodelc`. Na tej maszynie leży **`parakeet-tdt-0.6b-v3-coreml`** (starsza generacja biblioteki,
  `JointDecision.mlmodelc`): wagi są bajt w bajt te same (SHA-256 czterech plików `weight.bin`), ale dla aplikacji model
  **nie istnieje** (status „Not downloaded"). Pierwsze „Download" pobiera **drugą kopię, 483 257 242 B (483 MB = 461 MiB)**,
  obok `-coreml`; ta ostatnia zostaje nietknięta i nieużywana.
- Pobranie robi tylko użytkownik, przyciskiem na karcie modelu (rozmiar i źródło widoczne przed startem); „Remove…" kasuje
  wyłącznie `parakeet-tdt-0.6b-v3`, nigdy `-coreml`, v2 ani `parakeet-eou-streaming` (te leżą w tym samym magazynie, spec 2.0 §3 pkt 5).
- Integralność = lista plików i rozmiary z manifestu (ze świeżego pobrania tym samym pinem) oraz odcisk modelu w migawce
  przebiegu. Znany sufit: podmiana pliku wag o identycznym rozmiarze nie jest wykrywana; rewizja modelu na Hugging Face
  nie jest przypięta (`main`) — zmiana upstream kończy się komunikatem „differs from the version this build expects".
- Jakość PL względem `mai-transcribe-2` (S1) — **zmierzona 2026-10-20** ([raport S1](superpowers/spikes/2026-10-20-f20-s1-jakosc-asr.md), commit `6fc76d7`):
  zgodność z `mai-transcribe-2` na 15 sesjach ~83 % słów (rozbieżność 0,174; mały korpus, nie WER), kompletność 102,7 % słów FluidVoice, mediana 32 słów na wypowiedź,
  powtarzalność tekstu i czasów słów. Pomiar bez progu go/no-go; nie zmierzono: kryterium 3.1 (milczący mikrofon na żywo) i pary PL+EN (T11) — czekają na nagranie użytkownika.

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
  Warunki: zamknięcie okna rozmowy (zwolnienie mikrofonu przez aplikację rozmów), cisza dłuższa niż N minut.
  ⚠️ **Koniec wydarzenia w kalendarzu NIE jest warunkiem** (decyzja użytkownika 2026-10-16: godzinne
  spotkanie, które skończyło się po 15 min, ma się skończyć po 15 min) — patrz
  [spec 1.6 §4.6](superpowers/specs/2026-10-16-faza16-kalendarz-design.md).
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
- 🆕 🔴 **Język wybierany jawnie i związany z modelem. Domyślnie nigdy auto-detekcja.**
  Zmierzone: polskie spotkanie z `Language: en` dało **62% zmyślonej angielszczyzny**,
  czytającej się jak prawdziwa notatka. Ten sam plik w dwóch przebiegach dał dwa różne wyniki.
  To najgroźniejszy tryb awarii notatnika, bo **wygląda na wiedzę**.
  - 🆕 **Zmiana 2026-10-13 (decyzja użytkownika):** preset może mieć język **„Auto"** jako
    opcję awaryjną — nigdy domyślną, z widocznym ostrzeżeniem „niższa jakość, ryzyko zmyśleń".
    Powód: spotkania mieszane PL/EN (realny przypadek użytkownika). Dowód ryzyka zostaje:
    Granola „Multi-language" na tym samym spotkaniu zniekształciła polski
    (`docs/design/inspiracje/granola.md`). Do rozważenia przy fazie 1.5: preset z **parą
    języków** (np. PL + EN) jako bezpieczniejszy wariant od pełnego auto — wymaga pomiaru
    na korpusie, czy MAI to obsługuje. Kod: `LanguageCode` dziś odrzuca `auto` — zmiana
    w planie fazy 1.5, razem ze strażnikiem języka (przy auto nie ma czego pilnować).
- 🆕 **Wybrany wariant modelu widoczny w UI** — nazwa, rozmiar, znacznik „Multilingual",
  przycisk testu. Wzór: ekran modeli Spokenly. Cztery z pięciu testowanych aplikacji tego
  nie pokazują i przez to milcząco jadą na złym modelu.
- 🔴 **Ollama i oMLX nie robią ASR — sprawdzone 2026-09-23.** Do AI (korekta,
  podsumowanie) zostają bez zastrzeżeń, ale **nie mogą być silnikiem transkrypcji**:
  - **Ollama**: udokumentowane możliwości to streaming, thinking, structured outputs, vision,
    embeddings, tool calling i web search — **audio nie ma na liście**. W rejestrze leżą
    modele w rodzaju `dimavz/whisper-tiny`, ale przykłady użycia na ich stronie to zwykły
    czat tekstowy. Wszystkie działające zestawy „Whisper + Ollama" to **dwa osobne procesy**:
    Whisper transkrybuje, Ollama dostaje gotowy tekst.
  - **oMLX**: żądanie dodania `/v1/audio/transcriptions` (issue #301) zostało
    **zamknięte jako nieplanowane**.
  - ⚠️ **Obecność modelu w rejestrze nie znaczy, że runtime umie go uruchomić w jego
    modalności.** To ta sama pułapka co katalog modeli OpenRoutera, który pomijał
    MAI-Transcribe-2 mimo że model tam jest — tylko w drugą stronę.
- 🆕 **Lokalne role tekstowe (korekta, podsumowanie, tytuł) przez Ollamę, llama.cpp (`llama-server`) albo oMLX** (faza 2.0b,
  [spec 2.0 §5, §14](superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md)): zwykły dostawca OpenAI-compatible na loopbacku
  (`localhost`, `127.0.0.1`, `::1`, `*.localhost`; adres LAN albo tunel **nie** jest „lokalny"). Preset może mieszać role:
  ASR lokalnie i notatka w API albo odwrotnie. Wynik pomiaru S2 (Apple M4, 16 GB; Ollama 0.40.6, `llama-server` 0.7.0, oMLX 0.7.0;
  [raport](superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md)) — **pomiar, nie rekomendacja** (n=1–2 na komórkę, maszyna obciążona,
  czasy pesymistyczne 1,5–3×); aplikacja **nie rekomenduje żadnego modelu**:
  - **Wejście dłuższe niż kontekst:** Ollama (model `genesys-ministral3`) i llama.cpp odpowiadają HTTP 400 („exceeds the available context size").
    ⚠️ **Korekta 2026-10-20 (odbiór T14, [raport](superpowers/reports/F20-2.0b-odbior.md) §2.3):** dla Ollamy to **nie jest prawdą ogólną** — S2 zmierzył 400 tylko na
    `genesys-ministral3`; `bonsai-2` (Ollama 0.40.6) **obcina wejście po cichu**: HTTP 200, `finish_reason: "stop"`, zachowane 4 pierwsze tokeny i koniec promptu
    (zmierzone 3×: 9987 → 2050 i 4219 → 2050 tokenów, z `max_tokens` i bez), w logu serwera `truncating input prompt`. Na oMLX niewykrywalne (brak
    wykrywania kontekstu). Aplikacja dochodzi do tego stanu, gdy pole „Context window" jest wyższe niż kontekst serwera, a model nie jest załadowany
    (wykrycie `/api/ps` go nie obniży). Obrona: dla dostawców lokalnych sprawdzenie `usage.prompt_tokens` względem długości promptu (zmierzone normalnie 2,8–3,3 znaku
    na token, przy obcięciu 6,6–14,8) — **wdrożona (T14b, `348f728`)**; decyzja użytkownika w [przeglądzie całości](superpowers/reports/F20-przeglad-calosci.md) §5.
  - **Ciche obcięcie jest po stronie wyjścia:** HTTP 200 z `finish_reason: "length"`. Aplikacja traktuje to jako błąd w każdym wywołaniu
    czatu (także dla API); wyjątek: transkrypcja przez `chatAudio` nadal ignoruje to pole ([BACKLOG](superpowers/BACKLOG.md)).
  - **Domyślny kontekst Ollamy w aplikacji = 4096 tokenów** (`/api/ps`). `/v1` ignoruje `options.num_ctx`; działają `OLLAMA_CONTEXT_LENGTH`
    (restart serwera) i `PARAMETER num_ctx` w Modelfile. llama.cpp: kontekst zależy od pamięci (45 824 przy 4 slotach na tej maszynie).
    Pole „Context window (tokens)" u dostawcy lokalnego (puste = 4096); wykrycie (`/props` dla llama.cpp, `/api/ps` dla załadowanego
    modelu w Ollamie) tylko **obniża** budżet; `/api/show` zwraca maksimum modelu, więc nie służy do wykrywania. Przy 4096 notatka powyżej
    ok. 3,5 min mowy idzie przez map-reduce (tylko dla dostawców lokalnych), a 60 min może się nie zmieścić (jawny błąd, nie ucięta notatka).
  - **„Thinking":** Ollama zwraca rozumowanie w polu `reasoning`, llama.cpp w `reasoning_content` — aplikacja czyta tylko `content`.
    Dla dostawców lokalnych wysyła `reasoning_effort: "none"` (z jednym ponowieniem bez pola, gdy serwer je odrzuci); `ThinkingStripper`
    (`<think>…</think>`, `[THINK]…[/THINK]`) zostaje jako obrona. Zachowanie pola na modelu bez „thinking" jest niezmierzone.
    `bonsai-2` (Q2_0) z myśleniem był bezużyteczny (465 s i ucięcie przy notatce z 10 min); bez myślenia dał poprawny format notatki.
  - **Korekta lokalnym modelem — bez rekomendacji:** `bonsai-2` (Q2_0, Ollama, temperatura 1 z Modelfile, materiał syntetyczny) zmienił datę
    („pierwszego grudnia" → „pierwszy stycznia"), a bramka `CorrectionRules.accepts` (pasmo długości) tego nie łapie; w edytorze presetu
    jest podpis ostrzegawczy. Aplikacja wysyła dla lokalnej korekty `temperature` 0,2 — jej wpływu na to nie zmierzono.
  - **oMLX — niezmierzony:** jedyny kompletny model MLX na dysku nie zmieścił się w pamięci (HTTP 507). Port 8000 potwierdzony; serwer
    użytkownika może wymagać klucza (401), więc klucz w presecie jest opcjonalny. Baseline (ta sama notatka i korekta przez API) też niezmierzony.
- 🔴 **Awaria lokalnej roli nigdy nie przełącza po cichu na API** (anty-cel fazy 2.0): przebieg kończy się widocznym błędem albo jawną luką,
  a ponowienie innym presetem wybiera użytkownik. Dla lokalnego ASR bramkuje to test `missingModelRefusesRunAndNeverFallsBack`
  (brak modelu = brak przebiegu i brak ruchu do API).
- 🆕 **Lokalny ASR musi być w procesie albo w dedykowanym sidecarze**, nie przez wspólny
  serwer modeli. Kandydaci: **FluidAudio** (Swift, w procesie, Parakeet v3 już na dysku),
  `parakeet-mlx-server` (OpenAI-kompatybilny FastAPI), `mlx-whisper`, WhisperKit.
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

- **Kalendarz Apple przez EventKit** ✅ — wykrycie startu, tytuł notatki z wydarzenia, ręczne
  powiązanie wydarzenia z notatką (faza 1.6, [spec](superpowers/specs/2026-10-16-faza16-kalendarz-design.md)).
  ⚠️ Wcześniejsze „to samo zdarzenie daje mechaniczny warunek końca sesji" **uchylone**
  2026-10-16: koniec wykrywa aplikacja (zwolnienie mikrofonu, cisza), nie godzina z kalendarza.
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

- **Czy budować na FluidAudio (Swift), czy własna ścieżka** — FluidAudio daje gotowy
  Parakeet v3, diaryzację, VAD i boosting słownika, wszystko w CoreML i już na dysku.
  Koszt: wiązanie ze Swiftem i z cudzym harmonogramem wydań.
- **Czy odsłuch ma mieć wersję zmiksowaną** (obie strony w jednym pliku) — jeśli tak, to
  **po wyrównaniu**, a oryginały zostają.

## 🆕 Z porównania z Granolą i Wispr Flow (2026-10-13, odbiór D3)

- **Szablony podsumowania** wybierane po spotkaniu (1:1, rekrutacja, cotygodniowe, discovery…), z regeneracją notatki innym szablonem i własnymi szablonami. Szablon to druga oś obok presetu: preset = język + modele, szablon = rodzaj spotkania → prompt i struktura notatki. Dziś prompt podsumowania siedzi w presecie — do przemyślenia w fazie 1.5.
- **Własne notatki w trakcie spotkania** („My thoughts"), wplatane w wygenerowaną notatkę.
- **Transkrypt na żywo w trakcie spotkania** (Granola, Wispr Flow). Faza 1 transkrybuje po zakończeniu: długie okna dają modelowi więcej kontekstu, a bramka ciszy oszczędza koszt. Na żywo = wysyłanie okien w trakcie nagrania (koszt podobny, krótszy kontekst okna). Kandydat na fazę 1.5/2 — decyzja przy planowaniu; transkrypt po spotkaniu może pozostać „ostateczną" wersją (jak baner Wispra: „po spotkaniu poprawię transkrypt").

