# Recenzja speca 2.0 „Lokalne modele" (2026-10-20)

> **Dla autora speca:** `docs/superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md`,
> wersja `sha256 568354e7…c974a` (plik jeszcze niecommitowany — `git status` = `??`).
> Recenzja tylko do odczytu; w repo powstał wyłącznie ten plik.
>
> Werdykt: **do przeróbki** — 3 blokery (R1–R3), 6 rzeczy do rozstrzygnięcia przed planem
> (R4–R9), 5 drobnych (R10–R14). Architektura „lokalna ścieżka obok API" się broni;
> blokery dotyczą wykonania, nie kierunku.
>
> Oznaczenia: 🔴 blokuje plan · 🟡 do rozstrzygnięcia przed planem · 🟢 drobne/korekta faktu.

## Co jest dobre (nie ruszać)

- **Szew w kodzie zbadany poprawnie.** `TranscriptionRunner` naprawdę przyjmuje
  `any TranscriptionClient` (`TranscriptionRunner.swift:62`), a `Provider.api` wybiera klienta
  (`ElevenLabsClient.swift:5-10`). Lokalny ASR wchodzi bez zmiany pakowania okien, bramki energii,
  filtra przesłuchu, scalania i wznawiania — to prawda, nie życzenie.
- **2.0b naprawdę nie potrzebuje nowego transportu.** `Corrector` i `NoteGenerator` biorą
  konkretnie `OpenAICompatibleClient` (`Corrector.swift:83`, `NoteGenerator.swift:12`), a Ollama,
  `llama-server` i oMLX mówią `/v1/*`; `ProviderPreset.ollama` istnieje (`ProviderSetup.swift:28`),
  a dostawca bez klucza na `localhost/127.0.0.1/::1` już dziś przechodzi
  (`AppModel.swift:311`). Decyzja „lokalny model = zwykły Provider" jest tania i odwracalna.
- **Anty-cele są właściwe** i zgodne z lekcją W§2: brak cichego fallbacku do API, brak pobierania
  bez zgody, brak zmyślonych treści, brak cichego obcięcia. To jest lista z prawdziwych awarii
  tego projektu, nie z checklisty.
- **Kolejność ze STOP-em po S0** (go/no-go przed kodem produktu) jest dobra, a S2 przed
  ustaleniem domyślnych limitów — jedyna sensowna kolejność.
- **S0 jest tani i rozstrzygalny.** Dwa pytania z §4.3 da się zamknąć bez spika: FluidAudio jest
  **Apache-2.0** (`LICENSE` upstream), a `Package.swift` upstream deklaruje `.macOS(.v14)`
  (projekt ma `.macOS("15.0")` — bez konfliktu). API zwraca `ASRResult` z „token timings",
  jest `modelsExist(at:)`, `downloadAndLoad(to:version:progressHandler:)` i `AsrManager.cleanup()`.

---

## 🔴 Blokery

### R1. Dostawca lokalnego ASR nie przejdzie bramki „bez klucza" — 2.0a nie ruszy

**Gdzie:** spec §4.2 (baseURL `local://fluidaudio`, „bez klucza i bez adresu") vs
`AppModel.swift:311`.

**Dowód:** bramka klucza dopuszcza brak klucza tylko dla dostawcy OpenAI-compatible, którego host
jest na twardej liście `["localhost", "127.0.0.1", "::1"]`:

```swift
guard key != nil || (p.api == .openAICompatible && ["localhost", "127.0.0.1", "::1"].contains(p.baseURL.host() ?? "")) else {
    return .failure(ClientProblem(message: "No API key for \(p.name). …"))
}
```

Host `local://fluidaudio` to `fluidaudio`, więc `providerWithKey` zwróci błąd, a tym samym
`transcriptionClient(for:)` (`AppModel.swift:327`) zwróci `nil` i `transcribe(sessionURL:preset:)`
wyjdzie na strażniku z linii 560 z „No API key…". Przebieg nie powstanie — a to jest właśnie
kryterium sukcesu z §1.

**Naprawa:** dopisać w §4.2 jawnie zmianę w `AppModel.providerWithKey`: brak klucza dozwolony też
dla `p.api == .fluidAudio` (albo przez `Provider.needsKey == false`), przy czym warunek lokalności
ma być **jednym** predykatem — tym samym, który definiuje §11.5 (loopback + `*.localhost`),
a nie drugą listą hostów obok istniejącej. Do §10 dopisać mutację: „usunąć gałąź `.fluidAudio`
→ preset z lokalnym ASR nie startuje".

### R2. „Wydłużone limity czasu" nie zadziałają — transport ma własne 120 s na żądanie

**Gdzie:** spec §5.2 („Limity czasu: dla dostawców lokalnych wydłużone domyślne (`NoteGenerator.timeout`
180 s i `Corrector.batchTimeout` 120 s są za krótkie…)").

**Dowód:** `OpenAICompatibleClient.request(…, timeout: Double = 120)` (`OpenAICompatibleClient.swift:52-58`)
ustawia `URLRequest.timeoutInterval` na 120 s, a `chat` (`:121-125`) korzysta z domyślnej wartości.
`withDeadline` to **osobny** limit całości (`Deadline.swift:10-13`) — komentarz w tym pliku sam
tłumaczy, że `timeoutInterval` mierzy bezczynność łącza. Przy odpowiedzi niestreamowanej serwer nie
wysyła ani bajtu aż do końca generacji, więc lokalny 8B na 60-minutowym transkrypcie (prompt
kilkanaście–kilkadziesiąt tysięcy tokenów) stuknie 120 s bezczynności **przed** limitem 180/600 s.
Podniesienie `NoteGenerator.timeout` do 600 s nic nie zmieni, a S2 zmierzy sufit transportu i na jego
podstawie wybierze złe domyślne.

**Naprawa:** dać `chat` parametr limitu (np. `chat(model:system:user:timeout:)` albo `chatTimeout`
na kliencie) i w §5.2 napisać, że dla dostawców lokalnych podnosimy **oba** limity: miękki
(`withDeadline`) i transportowy, z transportowym wyżej. Do S2 dopisać pomiar „czas do pierwszego
bajtu" obok czasu całości — inaczej nie odróżnisz „model wolny" od „transport uciął".

### R3. S1 nie ma materiału ani referencji — „WER vs mai-transcribe-2" nie jest WER

**Gdzie:** spec §7 wiersz S1; §11.7 („brak twardego progu — raport pokazuje WER…").

**Dowód 1 (materiał):** w repo jest 15 sesji w `.devdata/sessions`, łącznie **~18,5 min** dźwięku
systemowego; najdłuższa sesja **9,4 min** (566 s), reszta od 0 do 128 s. S2 chce transkryptu
„~60 min" — takiego nagrania na tej maszynie nie ma. To ten sam brak, który trzyma T11
(„czeka na nagranie użytkownika", ROADMAP §Faza 1.5b).

**Dowód 2 (referencja):** WER wymaga tekstu referencyjnego. Porównanie z `mai-transcribe-2` daje
**zgodność dwóch ASR-ów**, nie WER — a właśnie tak najkrótszy wykonawca przeczyta „WER/jakość
Parakeet vs mai-transcribe-2". Liczba wyjdzie, tylko nie będzie znaczyła tego, co mówi nagłówek.

**Dowód 3 (utracone progi):** `docs/plan.md` §3 (Etap 3) ma dla tej samej zdolności gotowe,
mierzalne kryteria i punkty odniesienia: 3.3 kompletność ≥ 95% liczby słów FluidVoice (~2450),
3.4 mediana słów/segment ≥ 20, 3.7 85 min ≤ 60 s, 3.1 milczący mikrofon ≤ 2 wypowiedzi w „Ja",
3.2 ≤ 2 obcojęzyczne wtręty, 3.8 podmiana pliku modelu → aplikacja odmawia. Spec ich nie dziedziczy
ani nie uchyla wprost — a to jedyne liczby, jakie projekt ma dla lokalnego ASR.

**Naprawa:** (a) nazwać korpus w S1: które sesje, ile minut, kto robi referencję (przepisanie
fragmentu ręcznie albo FLEURS 7,31% jako odniesienie zewnętrzne, wyraźnie oznaczone);
(b) jeśli referencji nie będzie — napisać „zgodność z mai" i nie nazywać tego WER;
(c) dopisać jedno zdanie: które kryteria z `plan.md` §3 obowiązują dalej, a które spec uchyla.
To decyzja użytkownika (materiał jest jego, nagrania są służbowe), więc do STOP-u, nie do zgadywania.

---

## 🟡 Do rozstrzygnięcia przed planem

### R4. Nowy `ProviderKind` to nie jedna wartość w enumie — trzy miejsca, których spec nie nazywa

**Dowód:**
1. `AppModel.loadModels` (`:398-403`) ma gałąź „ElevenLabs → stała lista, bez sieci". Lokalny ASR
   potrzebuje tej samej gałęzi (lista `parakeet-tdt-0.6b-v3`), inaczej wybór modelu w presecie
   będzie pusty albo poleci przez `client(for:)` i skończy się „… does only speech-to-text."
2. `ProviderPreset.matching` (`ProviderSetup.swift:55-58`) rozpoznaje dostawcę po rodzaju API
   (ElevenLabs) albo po adresie. `local://fluidaudio` nie pasuje do żadnego presetu, więc
   `ProviderListRow.rows` (`:82-92`) pokaże zapisanego dostawcę **drugi raz** jako `.custom`
   z adresem „fluidaudio".
3. `ProbeRunner.textClient` (`Probe.swift:58`) to `as? OpenAICompatibleClient` — dla lokalnego ASR
   `nil`, czyli sonda korekty/notatki powie „does only speech-to-text". To zachowanie **pożądane**,
   ale trzeba je nazwać, żeby nikt tego nie „naprawiał".

**Naprawa:** w §4.2 dopisać listę miejsc do zmiany (jak wyżej) i wymóg, że `ready`/`matching`
dostają wpis dla `fluidAudio` rozpoznawany po `kind`, nie po adresie.

### R5. `LanguageHandling = filtered` kontra sonda, która `.filtered` nigdy nie zwraca

**Dowód:** `ProbeRunner.probe` dla ASR ustawia `r.languageHandling = await classifyLanguage(...)`
(`Probe.swift:79`), a `classifyLanguage` zwraca wyłącznie `.enforced`, `.automatic` albo `.unknown`
(`:111-135`). Klient lokalny ignoruje parametr `language` (w FluidAudio to tylko **wskazówka
skryptowa** — odsiewa nie-łacińskie tokeny, dla pary PL/EN nie robi nic), więc sonda zwróci
`.automatic`, a `PresetsView.swift:364` pokaże „This model detects language itself — your language
setting can't be enforced". Spec w tym samym akapicie obiecuje `.filtered` (§4.2).

Sam strażnik działa niezależnie: `Merger` woła `LanguageGuard.mismatch` zawsze, gdy `language != nil`
(`Merger.swift:69-72`), więc to sprzeczność na poziomie badge'a i zapisu w `ProbeResult`, nie dziura
w bezpieczeństwie.

**Naprawa:** wybrać jedno: (a) dla `provider.kind == .fluidAudio` sonda ustawia `.filtered` bez
klasyfikacji (gałąź w `ProbeRunner.probe`), albo (b) zostawić `.automatic` i poprawić §4.2 oraz
tekst ostrzeżenia. Przy okazji napisać w §4.2, że hint FluidAudio jest skryptowy — inaczej zdanie
„dekoder przycina wynik" sugeruje więcej, niż dostajesz.

### R6. Budżet kontekstu: `maxBatchChars = 6_000` nie wynika z budżetu, a Ollama obcina po cichu

**Dowód:** `Corrector` ma `maxBatchChars: Int = 6_000` (`Corrector.swift:89`), a §5.2 wskazuje
`CorrectionBatches` jako zabezpieczenie anty-celu „ciche obcięcie". 6000 znaków polskiego to
~2–3 tys. tokenów plus system i numeracja — przy domyślnym `num_ctx` Ollamy (~4k) to proszenie się
o obcięcie wejścia, po którym `CorrectionBatches.parse` dostanie inną liczbę linii i **cała partia
przepadnie** (`:128-132`). Dodatkowo: `/api/show` zwraca metadane modelu (maks. kontekst), a nie
efektywne `num_ctx` — wykrycie z §5.2 może więc dać budżet **w złym kierunku** (128k zamiast 4k),
czyli dokładnie ten anty-cel. Oba wykrywane endpointy (`/api/show`, `/props`) leżą **poza** `/v1`,
a `Provider.baseURL` trzyma `…/v1` — plan musi to uwzględnić.

**Naprawa:** jeden mechanizm budżetu dla korekty i notatki: `maxBatchChars` wyprowadzany z tego
samego limitu co podział notatki (np. `znaki ≈ tokeny_budżetu × 2`), a dla Ollamy budżet = wartość
`num_ctx` ustawiona przez użytkownika; wykrywanie może **obniżyć**, nigdy podnieść domyślnego.
Do S2: jeden przebieg z wejściem dłuższym niż `num_ctx`, żeby rozstrzygnąć, czy Ollama obcina
po cichu (dziś to założenie, nie fakt).

### R7. Map-reduce: „zwykły prompt szablonu na skrótach" łamie kontrakt promptu notatki

**Dowód:** prompt systemowy mówi „You write meeting notes from the transcript… 'Me' is the user's
microphone", a blok użytkownika to linie `[m:ss] Me|Them: tekst` (`NotePrompt.swift:20-60`).
§11.4 definiuje etap „map" tylko jako „zwięzły skrót każdej części" — bez wymogu mówcy, czasów,
nazw i liczb. Reduce dostanie więc tekst, którego prompt nie opisuje, a W§4 wymaga tożsamości
mówcy aż do zadań. Nie jest też powiedziane, gdzie lądują „My notes" i kontekst użytkownika
(w każdej części map = duplikacja i ryzyko zmyślenia, czy tylko w reduce = zgubione?).

**Naprawa:** zdefiniować format wyjścia map: linie `[m:ss] Me|Them: …` z zachowanymi nazwami,
liczbami, decyzjami i zadaniami, bez interpretacji; reduce używa tego samego renderera, a prompt
dostaje zdanie „to jest skondensowany transkrypt" (albo wariant promptu). „My notes" i kontekst
tylko w reduce. Ostrzeżenie o podziale już jest w §11.1 — zostawić.

### R8. Cykl życia modelu ASR nie ma właściciela w kontrakcie

**Dowód:** `TranscriptionClient` ma tylko `transcribe` (`OpenAICompatibleClient.swift:32-35`),
`TranscriptionRunner.client` jest `let` (`TranscriptionRunner.swift:62`), a `AppModel.transcribe`
tworzy klienta **przed** startem zadania (`:560-564`). „Model ładowany na początku przebiegu
i zwalniany po jego zakończeniu" (§4.2) wymaga właściciela i jawnego `unload()`; klient jako
`struct` nie zwolni nic przy wyjściu z zakresu. FluidAudio ma `AsrManager.cleanup()` — jest czym.

**Naprawa:** napisać w §4.2, że klient lokalny to `actor`/`class` trzymający `AsrManager`
z `load()`/`unload()`, a `AppModel.run` woła `unload` w `defer` (albo — alternatywa — model żyje
przez cały czas aplikacji; wtedy trzeba to powiedzieć, bo na 16 GB to inny profil pamięci).

### R9. S2: jedna z trzech serwerowni nie jest zainstalowana, druga ma zepsute CLI

**Dowód:** `which ollama` puste, `/Applications` bez Ollamy — jest tylko `~/.ollama/models`
(4,8 GB, jeden model `genesys-ministral3`). `/opt/homebrew/bin/omlx` (0.3.4) nie startuje
(„bad interpreter: … python3.11"); prawdziwy serwer to `oMLX.app` w wersji **0.7.0** — czyli §7
ma rację co do wersji, ale nie co do drogi uruchomienia. `llama-server 0.7.0` (build 11669) działa,
domyślny port 8080 się zgadza; oMLX ma port 8000 z `config.json` — potwierdzone.

**Naprawa:** dopisać do S2 warunki wstępne: „install Ollama" jako jawna akcja użytkownika (nie
po cichu w trakcie pomiaru) i „oMLX uruchamiany z aplikacji, nie z brew CLI". Inaczej S2 po cichu
stanie się porównaniem dwóch serwerów, a raport będzie twierdził, że trzech.

---

## 🟢 Drobne i korekty faktów

### R10. „Parakeet nie jest na dysku" — nieprawda; §10 zaplanuje „naprawę" dokumentów, które są poprawne

`~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml` = **461 MB**,
komplet (Encoder/JointDecision/Decoder/Preprocessor + `config.json` + oba vocab), mtime
2026-10-19 14:10. `wymagania.md` §0/§2 i ROADMAP („już pobrany/na dysku") mówią prawdę, a §3
decyzja 5 i §10 każą je „poprawiać". Co więcej, `AsrModels.download` zwraca od razu, gdy
`modelsExist` (upstream `AsrModels.swift:689`), więc karta „Download" będzie tu no-opem.
**Naprawa:** skreślić decyzję 5 i wpis w §10; zamiast tego zdecydować **szew testowy** dla gałęzi
„brak modelu" (wstrzykiwany katalog magazynu albo odsunięcie 461 MB za zgodą użytkownika) — bez
tego odbiór pobierania, postępu i błędu sumy nigdy się nie wykona na tej maszynie.

### R11. `Corrector.accepts` nie istnieje

Bramka to `CorrectionRules.accepts(original:corrected:)` (`Corrector.swift:36-42`), wołana w
`Corrector.correct` (`:134`). §2 (anty-cel) cytuje nieistniejący symbol — poprawić nazwę, bo inaczej
plan będzie szukał metody, której nie ma.

### R12. Suma kontrolna modelu: obietnica bez narzędzia

§4.2: „weryfikacja sumy kontrolnej, jeśli źródło ją podaje", a §11.6: „opakowujemy jego API, nie
piszemy własnego". Tymczasem upstream `ModelHub` sprawdza **obecność** plików
(`ModelCache.verifyModelsPresent`), nie ich hash — suma nie „przyjdzie" z API. `plan.md` 3.8
wymagał natomiast, żeby podmieniony plik modelu został wykryty. **Naprawa:** albo własny manifest
(rozmiary/hashe z HF dla przypiętej rewizji), albo wprost: „ufamy magazynowi; wykrywamy tylko
uszkodzenie przy ładowaniu" i skreślenie zdania o sumie.

### R13. Snapshot przebiegu nie pinuje modelu lokalnego

`RunSnapshot`/`RunInput` niosą `providerID` + nazwę modelu (`Transcript.swift:57-89`,
`TranscriptionRunner.swift:12-18`). `plan.md:113` przewidywał w migawce także **sumę kontrolną**.
Jeśli współdzielony magazyn zmieni model w trakcie/przy wznowieniu, okna z dwóch modeli wylądują
w jednym transkrypcie. **Naprawa:** opcjonalne pole `modelFingerprint` (rozmiar+ mtime albo hash
`config.json`) — zgodne z zasadą E6 (nowe pola tylko opcjonalne).

### R14. Sprzeczna kolejność

§7 i §12: S0 → 2.0a → S2 → 2.0b; §11.2: „2.0b nie zależy od S0 i może iść pierwsze". Wybrać jedną
i usunąć drugą — inaczej plan dostanie dwa różne harmonogramy.

---

## Czego nie sprawdziłem

- **Czy FluidAudio buduje się samymi CLT** i czy `scripts/bundle.sh` (kopiuje wyłącznie binarkę,
  bez `Frameworks/`) poradzi sobie z `binaryTarget` `NemoTextProcessing.xcframework` — to jest
  treść S0. Kryterium go/no-go powinno być wykonywalne: „`bundle.sh` składa `.app`, `otool -L`
  nie pokazuje zależności z `.build`, aplikacja się uruchamia", nie tylko „`swift build` przeszło".
- **Jakość PL, halucynacje na ciszy, RTF** — to S1 (wymaga materiału z R3).
- **Czy Ollama obcina wejście po cichu** i jakie `num_ctx` naprawdę działa — S2 (R6).
- **Czy `scripts/test.sh` przeżyje nową zależność** (plugin makr, liczenie `@Test`) — S0.

## Sprawdzone u źródła (skrót dowodów)

| Twierdzenie speca | Wynik |
|---|---|
| `TranscriptionRunner` przyjmuje `any TranscriptionClient` | ✅ `TranscriptionRunner.swift:62` |
| `Provider.api` wybiera klienta | ✅ `ElevenLabsClient.swift:5-10` |
| `Corrector`/`NoteGenerator` biorą `OpenAICompatibleClient` | ✅ `Corrector.swift:83`, `NoteGenerator.swift:12` |
| `ProviderPreset.ollama` istnieje | ✅ `ProviderSetup.swift:28` |
| Domyślne limity 180 s / 120 s | ✅ `NoteGenerator.swift:17`, `Corrector.swift:89` |
| Okna ≤ 59 s | ✅ `TranscriptionRunner.swift:68` |
| `LanguageHandling.filtered` istnieje i wskazuje fazę 2 | ✅ `Probe.swift:11` |
| `Provider.baseURL` wymagane, `kind` opcjonalne | ✅ `Provider.swift:7,12` |
| FluidAudio: licencja / próg macOS / czasy słów | ✅ Apache-2.0; `.macOS(.v14)`; `ASRResult` z token timings |
| Parakeet v3 nietknięty na dysku | ❌ jest, 461 MB (R10) |
| Ollama gotowa do S2 | ❌ brak binarki (R9) |
| oMLX 0.7.0 | ✅ app 0.7.0; brew CLI 0.3.4 zepsute (R9) |
| Korpus „spotkań" do S1 | ⚠️ 15 sesji / ~18,5 min / max 9,4 min (R3) |

---

## Skrót do wklejenia (autorowi / na czat, ≤1500 znaków)

Recenzja speca 2.0 (F20): do przeróbki. 3 blokery:

1. **R1 — keyless.** `AppModel.swift:311` wpuszcza bez klucza tylko OpenAI-compatible na
   `localhost/127.0.0.1/::1`; host `local://fluidaudio` to „fluidaudio" → `transcriptionClient(for:)`
   = nil → przebieg nie startuje. Dopisz zmianę bramki + mutację.
2. **R2 — limity czasu.** `OpenAICompatibleClient.request` ma timeout 120 s, a `chat` korzysta
   z domyślnego, więc podniesienie `NoteGenerator.timeout` do 600 s nic nie da; S2 zmierzy sufit
   transportu. Daj `chat(..., timeout:)` i podnoś oba limity.
3. **R3 — S1 bez materiału i referencji.** `.devdata` ma 15 sesji / ~18,5 min (max 9,4 min),
   a „WER vs mai-transcribe-2" to zgodność, nie WER. Nazwij korpus i referencję; powiedz, które
   kryteria `plan.md` §3 (3.3/3.4/3.7/3.8) obowiązują.

Ważne: R4 nowy `ProviderKind` = też `loadModels`/`matching`/`ready`; R5 sonda nigdy nie da
`.filtered` (tylko `.automatic`) — wybierz jedno; R6 `maxBatchChars 6000` i Ollama `num_ctx`
(`/api/show` to nie runtime); R7 map-reduce gubi mówcę, czasy i „My notes"; R8 load/unload modelu
bez właściciela w protokole; R9 Ollama niezainstalowana, oMLX tylko z appki.

Fakty: Parakeet **jest** na dysku (461 MB) → skreśl decyzję 5/§10; `Corrector.accepts` →
`CorrectionRules.accepts`; suma kontrolna: `ModelHub` nie weryfikuje hashy.

Pełne uzasadnienie: `docs/superpowers/reports/F20-recenzja-design.md`.

