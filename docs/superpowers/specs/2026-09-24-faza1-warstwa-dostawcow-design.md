# Design: faza 1 — warstwa dostawców i transkrypcja przez API

> Data: 2026-09-24 · Status: do recenzji
>
> **Zakres:** rejestr dostawców API, cztery sloty ról, odkrywanie modeli z sondą,
> transkrypcja nagrań przez API. **Bez modeli lokalnych. Bez diaryzacji.**
>
> ⚠️ **Zmiana zakresu z 2026-09-24, po pierwszym zapisie.** Pierwotnie faza 1 miała
> transkrybować **wczytywane** pliki, a nagrywanie miało przyjść później. Użytkownik odrzucił
> import plików jako funkcję produktu: przepływ ma brzmieć **nagraj → zapisz → transkrybuj**.
> Faza 1 obejmuje więc także **rdzeń nagrywania dwukanałowego**
> (`2026-09-24-rdzen-nagrywania-design.md`), który dostarcza pliki do transkrypcji.
>
> Sam potok transkrypcji **nie zmienił się o nic poza źródłem pliku** — nadal tnie na kawałki
> po 60 s i scala po znacznikach czasu słów.
>
> **Źródła:** `docs/wymagania.md` (`W§n`) ·
> `/Users/michalprzytulski/GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md`
> (`rozdz. n`) · pomiary własne 2026-09-24 (📐)

Oznaczenia: ✅ potwierdzone pomiarem · 🔴 twarde ograniczenie · 🆕 z pomiarów ·
⚠️ ograniczenie lub brak pomiaru · 📐 zmierzone w tej sesji

---

## 1. Miejsce w kolejności prac

| Faza | Treść | Dokument |
|---|---|---|
| **1** | Rdzeń nagrywania + warstwa dostawców + transkrypcja. ASR przez **OpenRouter** | ten dokument + `2026-09-24-rdzen-nagrywania-design.md` |
| 2 | Model lokalny: Parakeet v3 przez FluidAudio. Diaryzacja | do zaprojektowania |
| 3 | Notatki, zadania, słownik z pętlą uczenia, chat nad archiwum, MCP | do zaprojektowania |

### 1.0 Trzy znaczenia słowa „plik", które trzeba rozdzielić

| | Status |
|---|---|
| **Import pliku jako funkcja produktu** — okno wyboru, „Drop a file", wklejanie odnośnika do YouTube'a | 🔴 **wypada.** Decyzja użytkownika. Wszyscy czterej konkurenci to mają; my nie |
| **Plik jako wejście transkrypcji** | **zostaje.** Nagranie zapisane przez rdzeń jest plikiem i potok dostaje go tak samo jak każdy inny |
| **Plik jako materiał testowy** | **zostaje, tylko w testach.** P4 wymaga nagrania 85-minutowego, a porównanie jakości polskiego potrzebuje korpusu z rozdz. 13, 14 i 17. Testy wskazują pliki wprost, bez interfejsu |

**Dlaczego to rozróżnienie jest ważne:** bez niego łatwo wyciągnąć wniosek, że rezygnacja
z importu unieważnia potok cięcia i scalania. Nie unieważnia — zmienia wyłącznie źródło
pliku.

### 1.1 Rozdzielenie: spotkania i dyktowanie

To dwa przepływy o sprzecznych wymaganiach, dzielące dokładnie jedną warstwę.

| | Spotkania | Dyktowanie |
|---|---|---|
| Kanały | dwa (system + mikrofon) | jeden (mikrofon) |
| Tryb | wsadowy, długi | na żywo, krótkie wypowiedzi |
| Co się liczy | dokładność, tożsamość mówcy | opóźnienie, trafność słownika |
| Diaryzacja | tak (faza 2+) | nigdy |
| Wynik | archiwum i notatka | tekst w aktywnej aplikacji |

**Wspólne: warstwa dostawców, słownik, profil języka.**

🔴 Konsekwencja dla kontraktu ASR: dwa kształty wywołania — `transcribeFile` (długi, cięty,
z postępem) i `transcribeUtterance` (jedno żądanie, niskie opóźnienie). Faza 1 implementuje
pierwszy i **dowodzi testem**, że drugi jest osiągalny tym samym kontraktem. Bez tego
założenia dyktowanie wymusi później przepisanie warstwy.

### 1.2 Nawigacja aplikacji

Ustalona 2026-09-24. Pełna struktura, z zaznaczeniem, co buduje faza 1.

| Zakładka | Treść | Faza |
|---|---|---|
| **Notatki** (główna) | nadchodzące spotkania, oś czasu nagrań z podziałem na dni, chat nad archiwum, przycisk „nagraj spotkanie" | 1 częściowo — oś czasu i nagrywanie; kalendarz i chat w fazie 3 |
| **Zadania** | agregacja **między** spotkaniami: właściciel, spotkanie źródłowe, termin | 3 |
| **Dyktowanie** | oś czasu historii dyktowania | 2+ |
| **Słownik** | własne terminy oraz słowa poprawione bezpośrednio w transkrypcji | 3 |
| **Ustawienia** | dostawcy, cztery sloty ról, język, MCP | **1** |

Dwie powierzchnie poza nawigacją:

- **Widok spotkania** — transkrypt, klikalna linia czasu ze skokiem w nagraniu, edycja
  rozmówców, notatka. Największy ekran aplikacji. Faza 1 daje jego zalążek: transkrypt
  i skok w nagraniu.
- **Pływające okno** — 🆕 W§6 mówi, że to jest miejsce na wybór języka i modelu, a nie tylko
  przycisk nagrywania.

**Rozróżnienie, którego nie wolno zgubić:** W§4 wymaga chatu **nad jednym spotkaniem** i
**nad archiwum**. To dwie różne rzeczy. Chat nad archiwum („kiedy pytałem o to i o to")
należy do strony głównej i potrzebuje slotu `embedding`. Chat nad jednym spotkaniem należy
do widoku spotkania, nie przeszukuje niczego i embeddingu nie potrzebuje.

🔴 **Zakładka zadań zależy od stabilnej tożsamości mówcy** (W§4). Wispr Flow zwrócił poprawne
streszczenie, w którym `Speaker 2` to były dwie różne osoby — z takiego materiału zadania nie
mają właściciela. Dlatego jest w fazie 3, po diaryzacji.

⚠️ **Design wizualny nie jest jeszcze ustalony.** Zrzuty konkurentów pokazują dwie różne
odpowiedzi na to samo pytanie: Narada robi ze strony głównej pulpit ze wskaźnikami (czas
spotkań, koszt przełączania kontekstu), Granola robi listę notatek z kalendarzem z boku.
To decyzja do podjęcia przed implementacją powłoki.

### 1.3 Setup: uprawnienia przy pierwszym uruchomieniu

Ustalone 2026-09-24. **Zasada: setup jest pogrupowany po funkcjach. O uprawnienie prosimy
dopiero wtedy, gdy istnieje funkcja, która go używa.**

📐 Zasada wynika z pomiaru, nie z gustu. `nm -u` na binarkach konkurentów: Dostępność
(`AXIsProcessTrusted` + `CGEventPost` + `CGEventTapCreate`) importują **dokładnie te trzy
aplikacje, które dyktują** — FluidVoice, Spokenly, MacParakeet. Narada tylko nagrywa spotkania
i nie importuje żadnej z tych funkcji.

| Uprawnienie | Klucz `Info.plist` | Po co | Faza |
|---|---|---|---|
| **Mikrofon** | `NSMicrophoneUsageDescription` | kanał „Ja" | **1** |
| **Tylko nagrywanie dźwięku systemowego** | `NSAudioCaptureUsageDescription` | kanał „Oni" — process tap | **1** |
| **Kalendarz** | `NSCalendarsFullAccessUsageDescription` | nadchodzące spotkania, warunek końca sesji | z kalendarzem (3) |
| **Dostępność** | — (zapytanie przez `AXIsProcessTrustedWithOptions`) | dyktowanie: wstawianie tekstu, globalny skrót | z dyktowaniem |
| ~~Nagrywanie ekranu~~ | — | 🔴 **nie prosimy** | — |

#### Nagrywanie ekranu: nie

Panel w Ustawieniach systemowych nazywa się *„Nagrywanie ekranu i dźwięku systemowego"*, ale
ma osobną sekcję *„Tylko nagrywanie dźwięku systemowego"*. Stąd łatwo o wrażenie, że każda
aplikacja nagrywająca spotkania chce dostępu do ekranu. Pomiar mówi co innego.

📐 Źródło: Ustawienia systemowe na maszynie użytkownika, 2026-09-24. To rozstrzyga, bo TCC
pokazuje, **o co aplikacja faktycznie poprosiła**, a nie co deklaruje.

| Aplikacja | Sekcja w Ustawieniach | Ślad w binarce |
|---|---|---|
| **Narada** | tylko dźwięk | `AudioHardwareCreateProcessTap`, bez ScreenCaptureKit (rozdz. 6) |
| **Spokenly** | tylko dźwięk | `AudioHardwareCreateProcessTap` + `kTCCServiceAudioCapture` |
| **Wispr Flow** | tylko dźwięk | `kTCCServiceAudioCapture` |
| **OpenWhispr** | **obie** | własny `macos-audio-tap` (dźwięk) + Electron `desktopCapturer` (ekran) |
| **MacParakeet** | ekran + dźwięk | ScreenCaptureKit |
| Letterly | ekran + dźwięk | ⚠️ nie zmierzone — paczki nie ma na dysku |

**Trzy z czterech zmierzonych nagrywarek spotkań obywają się bez dostępu do ekranu.**
MacParakeet jest wyjątkiem, a nie regułą.

✏️ **Korekta.** Pierwsza wersja tej tabeli przypisywała Wispr Flow „ekran + dźwięk" na
podstawie opisu mechanizmu z rozdz. 6 („Chromium `getDisplayMedia`"). Ustawienia pokazały
sekcję „tylko dźwięk" — i zgadza się to z `kTCCServiceAudioCapture` w binarce, który był
w pomiarze od początku. Opis mechanizmu przegrał z odczytem TCC. To ta sama lekcja co
w rozdz. 16: rozstrzyga to, co system zapisał, a nie to, co wynika z opisu.

Process tap nie daje dostępu do obrazu, więc nasza aplikacja **strukturalnie nie może**
widzieć ekranu. Przy aplikacji, która słyszy wszystkie Twoje spotkania, to realna przewaga
w zaufaniu. Zgodne też z W§7: v1 wyłącznie audio.

#### 🔴 Brak publicznego API do sprawdzenia uprawnienia dźwięku systemowego

Stan mikrofonu i Dostępności da się sprawdzić publicznie. Stanu **dźwięku systemowego — nie**.

📐 Wispr Flow i Spokenly obchodzą to prywatnym interfejsem TCC: w binarkach są ciągi
`TCCAccessPreflight`, `TCCAccessRequest` i `kTCCServiceAudioCapture`, ładowane przez `dlsym`.
Narada tych ciągów nie ma, więc najpewniej uruchamia tap i zostawia monit systemowi.

| Droga | Za | Przeciw |
|---|---|---|
| **Prywatne TCC** (Wispr Flow, Spokenly) | setup pokazuje prawdziwy stan | może pęknąć przy aktualizacji systemu; zamyka App Store (i tak zamknięty, spec rdzenia §8) |
| **Próba i obserwacja** (Narada) | tylko publiczne API | stan znany dopiero po pierwszej próbie nagrania |

Decyzja po sondzie — patrz O5 i test T9 w specu rdzenia nagrywania.

⚠️ **Hipoteza, którą sonda musi rozstrzygnąć przed budową setupu:** co zwraca tap, gdy
uprawnienia brak. Jeśli **ciszę zamiast błędu**, to mamy tryb awarii, w którym aplikacja
nagrywa 85 minut niczego i wygląda przy tym na zdrową.

#### Stały podpis przestaje być opcją

Spec rdzenia §8: podpis ad-hoc zmienia `cdhash` przy każdej przebudowie, więc TCC resetuje
uprawnienia. Z kreatorem na starcie oznaczałoby to przechodzenie przez setup po każdym
`swift build`. 🔴 **Stały certyfikat samopodpisany jest zadaniem na dzień pierwszy.**

### 1.4 Trzy języki

Ustalone 2026-09-24. **Interfejs aplikacji jest po angielsku.**

| Język | Ustawienie | Wartość domyślna |
|---|---|---|
| **Interfejs** | angielski, stały | — |
| **Transkrypcja** | jawny wybór w profilu ASR | 🔴 **brak** — profilu bez języka nie da się zapisać (P7) |
| **Notatka** | wybór per spotkanie | = język transkrypcji tego spotkania |

🔴 **Język interfejsu nigdy nie podpowiada języka transkrypcji.** Aplikacja po angielsku przy
polskich spotkaniach to dokładnie ten układ, w którym naiwne „domyślny język = język
aplikacji" ustawi `en`. To jest katastrofa z rozdz. 14: 62% zmyślonej angielszczyzny, która
czyta się jak notatka. Byłoby to `auto` wprowadzone tylnymi drzwiami.

**Domyślny język notatki to nie wykrywanie.** Kopiuje jawny wybór użytkownika z profilu
ASR, więc nie łamie zasady „nigdy auto".

**Wybór jest odwracalny.** Notatka jest pochodną transkryptu, a transkrypt zostaje
w oryginale. Notatkę w innym języku da się wygenerować w dowolnym momencie, także dla
starych spotkań.

⚠️ Notatka w innym języku niż spotkanie jest **tłumaczeniem**. Każda nieścisłość ASR
przechodzi wtedy przez drugi model, więc nazwiska i cytaty trzeba w prompcie chronić przed
tłumaczeniem. To zadanie specyfikacji notatek (faza 3).

---

## 2. Ustalenia zamknięte, z dowodami

| Ustalenie | Dowód |
|---|---|
| 🔴 Ollama i oMLX **nie robią ASR** | rozdz. 19; commit `65a262e`; oMLX issue #301 zamknięte jako nieplanowane |
| 📐 LM Studio **nie robi ASR** | zgłoszenie `lmstudio-ai/lmstudio-bug-tracker#1715` otwarte od 2026-03-31 |
| 📐 llama.cpp **robi ASR, ale tylko przez czat** | Qwen3-ASR, Voxtral, Ultravox przez `/chat/completions`; brak `/v1/audio/transcriptions` |
| 🔴 Katalog myli w obie strony | OpenRouter `/api/v1/models` **pomija** MAI-Transcribe-2; rejestr Ollamy **pokazuje** `whisper-tiny`, którego runtime nie uruchomi (rozdz. 19) |
| 🔴 Nigdy `auto` przy języku | Polskie spotkanie z `Language: en` → 62% zmyślonej angielszczyzny, czytającej się jak notatka (rozdz. 14) |
| 🔴 Diaryzacja przez API odpada | Limit 60 s/żądanie rozbija spójność mówców między kawałkami (rozdz. 11) |
| 🔴 Cisza zatruwa transkrypt | Kanał mikrofonu: 82% halucynacji przy milczącym użytkowniku (rozdz. 13) |
| ⚠️ Warstwa korekty nie wygrywa sama z siebie | FluidVoice „z AI": 16 wtrętów zamiast 1, pewność 87,7% zamiast 92,9%, 5,5× wolniej (rozdz. 13) |
| 📐 FluidVoice **nie dostraja** ASR | `SelectedSpeechModel = "parakeet-tdt"` → `FluidInference/parakeet-tdt-0.6b-v3-coreml`. Ich `fluid-1` to model **tekstowy** (`altic-dev`: Pico 0.8B, Mini 2B, Quad 4B, wszystkie `text-generation`), oznaczony w UI „For dictation only" |

**Wniosek z ostatniego wiersza:** jakość, którą użytkownik ceni u FluidVoice, nie pochodzi
z lepszego ASR — pochodzi z **warstwy porządkującej po ASR**. Rozdz. 13 doszedł do tego
niezależnie i nazwał ją „tanią rzeczą do zrobienia przez API". Slot „korekta" jest dokładnie
tą warstwą i dlatego faza 1 ma sens jako pierwsza.

### 2.1 Runtime'y a ASR — stan na 2026-09-24

| Runtime | ASR | Kanał | Uwaga |
|---|---|---|---|
| Ollama | ❌ | — | pełnoprawny dla 3 pozostałych ról |
| oMLX | ❌ | — | jw. |
| LM Studio | ❌ | — | jw. |
| llama.cpp | ✅ | 🔴 tylko `/chat/completions` | Qwen3-ASR 0.6B/1.7B, Voxtral, Ultravox |
| whisper.cpp | ✅ | własny `/inference` | niezgodny z OpenAI |
| LocalAI | ✅ | `/v1/audio/transcriptions` | ⚠️ zwykle przez Dockera |
| Speaches | ✅ | `/v1/audio/transcriptions` | ⚠️ Docker, CUDA na pierwszym miejscu |
| parakeet-mlx-server | ✅ | `/v1/audio/transcriptions` | Python |
| **OpenRouter** | ✅ | `/api/v1/audio/transcriptions` | **wybór fazy 1** |

---

## 3. Pojęcia

**Dostawca** — instancja, nie typ: nazwa, adres bazowy, klucz. Dwa OpenRoutery z różnymi
kluczami to dwaj dostawcy.

**Dialekt** — kształt API, kod nasz. W fazie 1 dwa: *zgodny z OpenAI* (`/v1/models`,
`/v1/chat/completions`, `/v1/audio/transcriptions`, `/v1/embeddings`) i *natywny Ollama*
(`/api/tags`, `/api/embed`).

**Rola** — `asr`, `korekta`, `embedding`, `podsumowanie`.

**Profil** — przypisanie roli: dostawca + model + parametry. 🔴 Dla ASR język jest
parametrem **obowiązkowym i jawnym**.

**Rozróżnienie, na którym stoi cały ten design:** dialekty są w kodzie, możliwości są
sondowane. „Bez wiedzy na sztywno" znaczy, że nie zapisujemy, *który model co potrafi*. Nie
znaczy, że zgadujemy, jakie endpointy ma dane API — tego nie da się wysondować i nie ma po co.

---

## 4. Odkrywanie modeli

Przycisk „odśwież" robi trzy rzeczy:

1. **Pobiera listę** z endpointu dialektu.
2. **Wstępnie filtruje** po metadanych, jeśli dostawca je daje. Zawęża, nie rozstrzyga.

   📐 Zweryfikowane 2026-09-24 na żywym `/api/v1/models` OpenRoutera: obiekt modelu ma
   `architecture.input_modalities` i `output_modalities`. W listingu jest **458 modeli**,
   z czego **47 przyjmuje audio** — wszystkie przez czat. `microsoft/mai-transcribe-2`
   **nadal nie występuje**, mimo że działa. Pomiar z rozdz. 11 potwierdzony rok później,
   na tych samych danych.
3. **Sonduje** — minimalne żądanie próbne per rola.

### 4.1 Sonda

| Rola | Żądanie próbne | Warunek zaliczenia |
|---|---|---|
| `asr` | ~1 s dołączonego do aplikacji nagrania o znanej treści | wraca tekst zawierający oczekiwane słowo |
| `korekta` | krótkie zapytanie tekstowe | wraca tekst |
| `podsumowanie` | jw. | wraca tekst |
| `embedding` | jedno słowo | wraca wektor o stałym wymiarze |

🔴 **Sonda ASR próbuje dwóch kształtów wywołania**, bo ASR nie ma jednego. To nie jest
przypadek brzegowy: 📐 po jednej stronie 47 modeli czatowych przyjmujących audio, po drugiej
jedyny model transkrypcyjny, którego w listingu **nie ma wcale**.

1. `POST /v1/audio/transcriptions` — OpenRouter, LocalAI, parakeet-mlx-server, Speaches
2. `POST /v1/chat/completions` z audio w treści wiadomości — llama.cpp, a na OpenRouterze
   także `google/gemini-*-flash`, `openai/gpt-audio-mini`, `mistralai/voxtral-small-24b`

Który kształt zadziałał, **zapisujemy razem z werdyktem** — jest potrzebny przy każdym
późniejszym wywołaniu.

⚠️ Modele idące przez czat **nie deklarują znaczników czasu słów ani diaryzacji**. Przy
cięciu długiego nagrania znaczniki słów są jedynym spoiwem (§6), więc ta ścieżka nadaje się
do dyktowania i krótkich plików, a nie do godzinnych spotkań. Interfejs ma to mówić przy
wyborze, nie po fakcie.

### 4.2 Sondowanie jest leniwe i cache'owane

OpenRouter ma setki modeli; sondowanie wszystkich razy cztery role kosztowałoby realne
pieniądze i minuty. Więc:

- sonda uruchamia się **przy wyborze modelu** i na żądanie („przetestuj")
- wynik trafia do cache jako `(dostawca, model, rola) → werdykt + kształt + data`
- lista pokazuje trzy stany: *sprawdzony*, *niesprawdzony*, *nie działa w tej roli*

### 4.3 Wpisanie modelu z ręki jest wymagane, nie opcjonalne

🔴 `microsoft/mai-transcribe-2` **nie występuje** w `/api/v1/models` OpenRoutera — ten listing
zwraca wyłącznie modele czatowe. Model istnieje i działa. Gdyby dropdown był zamknięty,
jedynego sensownego modelu ASR fazy 1 **nie dałoby się wybrać**.

Stąd zasada: **lista to wygoda, sonda to autorytet, wpisanie z ręki to wyjście awaryjne.**

---

## 5. Cztery sloty

| Rola | Parametry | Uwagi |
|---|---|---|
| **ASR** | 🔴 język, limit sekund na żądanie, kształt wywołania | Ollama, oMLX i LM Studio odpadną **przez sondę**, nie przez wpis w kodzie |
| **Korekta** | własny system prompt | ⚠️ patrz ostrzeżenie w §2 — ta warstwa potrafi pogorszyć |
| **Embedding** | wymiar wektora | konsument (RAG) dochodzi później; slot działa już teraz |
| **Podsumowanie** | 🔴 **własny** system prompt, osobny od korekty | wymaganie W§2 |

Ładne w tym jest to, że 🔴 z rozdz. 19 egzekwuje się samo. Nie piszemy w kodzie „Ollama nie
robi ASR" — sonda wyśle sekundę audio i dostanie odmowę. A gdyby Ollama kiedyś ASR dodała,
zadziała bez naszego wydania.

---

## 6. Transkrypcja pliku

### 6.1 Twarde limity dostawcy fazy 1

| Limit | Wartość | Skutek |
|---|---|---|
| Audio na żądanie | **60 s** | godzinne nagranie = ~60 żądań |
| Rozmiar przy multipart | 25 MB | ~26 min MP3 128 kbps |
| Adresy URL audio | **niedozwolone** | tylko base64 albo multipart |
| Wyjście | JSON / verbose JSON | brak SRT/VTT |
| Cena | 0,10 USD/h | 85 min ≈ 0,14 USD |

### 6.2 Potok

1. **Bramka energii** — odcina ciszę **przed** wysłaniem.
2. **Cięcie po ciszy w pobliżu granicy 60 s**, nie na sztywno. Cięcie w środku słowa psuje
   oba kawałki.
3. **Wysyłka** wybranym kształtem, z przypiętym językiem.
4. **Scalanie po znacznikach czasu słów** (`timestamp_granularities: ["word"]`).
5. **Przeliczenie znaczników na czas pliku**, nie czas kawałka — inaczej klikalna linia
   czasu nie trafi w nagranie.
6. **Zapis przebiegu** z metadanymi (§8).

### 6.3 Bramka energii, nie model

🔴 Wymaganie W§1 mówi o bramce mowy per kanał. W fazie 1 nie ma modeli lokalnych, więc
bramka jest **energetyczna**: RMS w dBFS z histerezą — narosły czas ciszy, czas
„kwalifikowany", stan uzbrojenia.

To nie jest namiastka. Dokładnie tak robi Wispr Flow (`rmsDbfs`, `silenceAccruedMs`,
`silenceQualifiedMs`, `silenceArmed`), czyli aplikacja oceniona w pomiarach jako działająca
najlepiej (rozdz. 15). Rozdz. 13 i 15 doszły do tego samego niezależnie: **bramkowanie
energią robi więcej dobrego niż filtrowanie sygnału**, bo cichy fragment w ogóle nie trafia
do modelu.

W fazie 1 ma to dodatkowo **bezpośredni skutek finansowy** — za ciszę się nie płaci.

Faza 2 podmienia bramkę na `silero-vad` (1 MB, 📐 już leży w magazynie FluidAudio) bez zmiany
kontraktu.

### 6.4 Postęp i wznawianie

- **Postęp w procentach** = kawałki skończone / wszystkie. ✅ W§1 wymaga działania na plikach
  powyżej 80 minut.
- **Kawałki mają tożsamość**, więc przerwany przebieg da się dokończyć bez powtarzania
  opłaconych żądań.
- **Awaria pojedynczego kawałka** nie przerywa przebiegu: kawałek dostaje status błędu,
  transkrypt ma w tym miejscu jawną lukę, a nie ciszę udającą treść.

### 6.5 Czego faza 1 nie da

🔴 **Diaryzacji.** Limit 60 s rozbija spójność mówców między kawałkami — „Mówca 1" z trzeciej
minuty to nie ten sam człowiek co z dziesiątej. To ta sama pułapka, którą zdiagnozowano
w spike'u OpenWhispr jako przyczynę 127 mówców przy 4 uczestnikach (rozdz. 11).

**Ale podział „ja / oni" faza 1 dostaje za darmo.** Wynika z dwóch kanałów, nie z modelu
(rozdz. 8), a rdzeń nagrywania jest w fazie 1. Kanał mikrofonu to „Ja", kanał systemowy to
„Oni" — bez jednego bajtu modelu diaryzacji.

Brakuje wyłącznie **rozdzielenia wielu rozmówców wewnątrz kanału systemowego**. To jest ta
cieńsza połowa i ona czeka na fazę 2.

---

## 7. Klucze

Do pęku kluczy. Nigdy do pliku ustawień, nigdy do logu, nigdy do raportu błędu. W interfejsie
po zapisaniu widoczne wyłącznie ostatnie cztery znaki.

---

## 8. Metadane przebiegu

Każdy przebieg zapisuje: **dostawcę, model, kształt wywołania, język, wersję słownika,
datę, liczbę kawałków, koszt**.

Powód jest zmierzony. Rozdz. 16: cztery z pięciu aplikacji nie pokazują wybranego wariantu
i przez to milcząco jadą na złym modelu. Rozdz. 14: nagłówek `Language: en` był jedynym
sygnałem katastrofy — i to po fakcie.

Przebiegi leżą obok siebie, więc dwa modele na tym samym pliku da się porównać zamiast
zgadywać.

---

## 9. Interfejs

Wzorem jest ekran FluidVoice (W§2 🆕 wskazuje go wprost): lista dostawców, dropdown modelu
per dostawca, ikona odświeżania przy dostawcach sieciowych, przycisk edycji, plakietka
zweryfikowania. Ich „Verified providers" to nasza sonda pod inną nazwą.

**Dwie świadome różnice:**

1. 🔴 **Żadnej pojedynczej liczby dokładności.** FluidVoice pokazuje „Acc 92%" niezależnie od
   wybranego języka. Karta modelu v3 na FLEURS ma rozrzut od 3,00% WER (włoski) do 24,03%
   (słoweński) — ósemka razy; polski 7,31%. Pokazujemy WER **dla wybranego języka** albo nic.
   W notatniku, w którym najgroźniejsza awaria wygląda jak wiedza, fałszywa pewność na ekranie
   wyboru jest kosztowna.
2. **Rola widoczna przy dostawcy** jako cztery znaczniki z wyniku sondy, a nie przypis
   drobnym drukiem w rodzaju „For dictation only".

🔴 Wybrany język jest widoczny **przed** startem transkrypcji, nie w nagłówku wyniku.

---

## 10. Testy odbiorcze

| # | Co sprawdza | Próg |
|---|---|---|
| **P1** | Sonda odrzuca Ollamę w roli ASR i przyjmuje ją w roli korekty | na żywym endpoincie, nie na atrapie |
| **P2** | `microsoft/mai-transcribe-2` wpisany z ręki przechodzi sondę mimo nieobecności w liście | werdykt „sprawdzony", kształt `audio/transcriptions` |
| **P3** | Sonda rozpoznaje model działający **tylko** przez czat | werdykt „sprawdzony", kształt `chat/completions` |
| **P4** | Plik 85+ min: cięcie, scalanie, ciągłe znaczniki słów w czasie pliku | brak skoków i nakładek na granicach kawałków |
| **P5** | Przerwanie w połowie serii i wznowienie | zero powtórzonych opłaconych kawałków |
| **P6** | Bramka energii odcina ciszę | fragment ciszy nie generuje żadnego żądania |
| **P7** | Profilu ASR bez jawnego języka **nie da się zapisać** | bramka, nie ostrzeżenie |
| **P8** | Klucz nie pojawia się w logu, pliku ustawień ani raporcie błędu | wyszukanie po całym drzewie danych |
| **P9** | Kontrakt obsługuje krótkie okno (`transcribeUtterance`) | jedno żądanie, bez cięcia |

🔴 Każdy test dostaje **mutację** — wstrzykujemy błąd, sprawdzamy czerwień, cofamy. Rozdz. 1:
zielony test bez mutacji nie dowodzi niczego, a w poprzednim projekcie trzykrotnie okazało
się, że testy chroniły nie to, co miały.

**P6 i P7 są bramkami produktowymi, nie technicznymi.** Halucynacja na ciszy i konfabulacja
z niewłaściwym językiem to dwa najgroźniejsze tryby awarii notatnika, bo oba **wyglądają na
wiedzę**.

---

## 11. Czego ten dokument nie rozstrzyga

| Sprawa | Gdzie należy |
|---|---|
| Modele lokalne, FluidAudio, cache ANE | faza 2 |
| Diaryzacja, próg klastrowania, tożsamość mówcy | faza 2 |
| Tap systemowy, archiwum, AEC, kotwice czasu | **faza 1**, ale osobny dokument: `2026-09-24-rdzen-nagrywania-design.md` |
| Design wizualny powłoki, układ strony głównej | przed implementacją powłoki — nierozstrzygnięte |
| Import słownika z `GCX/dictation` i pętla uczenia | osobna specyfikacja; faza 1 zapisuje tylko **wersję** słownika |
| Treść promptów korekty i podsumowania | strojenie na korpusie, nie decyzja projektowa |
| Framework UI i magazyn danych | start implementacji |
| Struktura notatki, zadania, chat, RAG, MCP | osobne podsystemy |

## 12. Otwarte pytania

| # | Pytanie | Kiedy |
|---|---|---|
| O1 | Czy pliki korpusu z rozdz. 13, 14 i 17 nadal istnieją? Bez nich P4 nie ma punktu odniesienia | przed implementacją |
| O2 | Próg energii bramki i czas kwalifikowanej ciszy | strojenie na korpusie |
| O3 | Czy `transcribeUtterance` ma trafić do fazy 1 jako działająca funkcja, czy tylko jako dowiedziony kontrakt (P9) | przed planem |
| O4 | Limit sekund na żądanie: sondowany czy konfigurowany per dostawca | przed planem |
| O5 | Stan uprawnienia dźwięku systemowego: prywatne TCC (Wispr Flow, Spokenly) czy próba i obserwacja (Narada)? §1.3 | po sondzie T9, przed budową setupu |
| O6 | Czy setup otwiera właściwy panel Ustawień głębokim linkiem, zamiast opisywać, gdzie kliknąć? Interfejs jest po angielsku, a system użytkownika po polsku — opis ścieżki rozjedzie się z tym, co widać na ekranie | przed budową setupu |
