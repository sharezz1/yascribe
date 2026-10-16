# Design: rdzeń nagrywania dwukanałowego

> ⚠️ **Adnotacja z 2026-09-24, dwie zmiany kolejności tego samego dnia.**
>
> Najpierw ten podsystem przesunięto na fazę 3, za warstwę dostawców. Potem użytkownik
> odrzucił import plików jako funkcję produktu — przepływ ma brzmieć **nagraj → zapisz →
> transkrybuj**. Bez importu faza 1 nie miałaby skąd wziąć audio, więc rdzeń nagrywania
> **wraca do fazy 1** i idzie razem z warstwą dostawców
> (`2026-09-24-faza1-warstwa-dostawcow-design.md`).
>
> **Design nie zmienił się ani razu przy obu przestawieniach.** Był projektowany tak, żeby
> nie wiedzieć nic o ASR, i ta granica zniosła dwie zmiany planu bez poprawki w treści.

> Data: 2026-09-24 · Status: zatwierdzony, wykonanie w fazie 1
>
> **Zakres dokumentu:** wyłącznie rdzeń nagrywania. Transkrypcja, diaryzacja, notatki,
> słownik, UI, kalendarz i RAG mają własne specyfikacje.
>
> **Źródła:** `docs/wymagania.md` (dalej `W§n`) ·
> `/Users/michalprzytulski/GCX/docs/superpowers/logs/2026-09-23-openwhispr-lessons-learned.md`
> (dalej `rozdz. n`) · pomiary własne z sesji 2026-09-24 (oznaczone 📐)
>
> **Dokumenty równoległe:** `docs/brainstorm-asr.md` i `docs/plan.md` — niezależna analiza
> agenta Hermes z 2026-09-24. Wnioski zbieżne; różnice i domknięcia w §10.

Oznaczenia: ✅ potwierdzone pomiarem · 🔴 twarde ograniczenie · 🆕 z pomiarów ·
⚠️ ograniczenie lub brak pomiaru · 📐 zmierzone w tej sesji

---

## 1. Po co to powstaje

Aplikacja natywna macOS do notatek ze spotkań i dyktowania. Rdzeń nagrywania jest pierwszy,
bo jest jednocześnie najdroższy, najbardziej ryzykowny i fundamentalny.

**Teza, która go uzasadnia** (rozdz. 5): transkrypt jest półproduktem. Jeśli nagranie
przetrwa, błąd rozpoznania przestaje być stratą spotkania. Dlatego archiwum ma wartość
niezależną od jakości ASR — i dlatego powstaje przed nim.

**Kryterium sukcesu:** rdzeń przechodzi testy T1–T9 (§9) na własnym sprzęcie, a jego
nagrania są mierzalnie lepsze od czterech z pięciu zmierzonych aplikacji konkurencyjnych.

**Odbiorca:** na dziś jedna osoba, jedna maszyna (M4, 16 GB, macOS 27.0). Docelowo
możliwa dystrybucja przez Homebrew. App Store świadomie poza zakresem — uzasadnienie w §8.

---

## 2. Decyzje zamknięte przed tym dokumentem

| Decyzja | Rozstrzygnięcie | Dowód |
|---|---|---|
| Platforma | Swift, jeden proces, natywnie | Electron: 755 MB paczki, 0,5 GB RAM (rozdz. 5) |
| Mechanizm tapu | **Process tap Core Audio** | Narada: R² = 1.000, paczka 98 MB, bez ScreenCaptureKit (rozdz. 6, 18) |
| Architektura zapisu | Dwaj niezależni pisarze, zero miksu w czasie rzeczywistym | 🔴 rozdz. 18: z miksu nie da się wyjąć czystego strumienia |
| Trwałość | Dziennik dopisywany na bieżąco (wariant B) | „OpenWhispr nie zostawia pliku" — najcięższy zarzut z rozdz. 17 |
| AEC | Platformowy `setVoiceProcessingEnabled`, na kopii; surowy mikrofon zawsze zachowany | rozdz. 7; odwracalność wymaga oryginału |
| Start / koniec sesji | Ręczny start, mechaniczny koniec | 🔴 rozdz. 17 (ogon 70 min); autodetekcja kosztowała 2,5 min treści (rozdz. 13) |
| Sandbox | **Nie** w v1 | 📐 sandbox odcina wspólny magazyn modeli — §8 |
| Xcode | **Nie jest potrzebny** | 📐 SwiftUI + `CATapDescription` budują się na Command Line Tools |

✏️ **Korekta 2026-09-29 (wiersz „AEC").** Sonda S5 (`reports/S5-ducking-konsultacja.md`): żywe przetwarzanie głosu przez całe nagranie ścisza inne aplikacje, a na macOS nie da się tego wyłączyć (poziom `Min` + advanced też ściszają). Domyślnie nagrywamy więc **bez VP**: `system` + `mic_raw`. `mic_aec` jest opcją (`--aec`), a jej znanym ograniczeniem jest stałe ściszanie. Docelowo AEC offline z `mic_raw` + `system`, planowane po planie 05. Surowy mikrofon zostaje zawsze.

### 2.1 Pomiary wykonane w tej sesji

Domykają część eksperymentów zaprojektowanych przez Hermesa jako E0 (patrz §10).

| # | Ustalenie | Metoda |
|---|---|---|
| 📐1 | FluidAudio: Apache-2.0, `platforms: [.macOS(.v14)]` | `Package.swift` z klona `v0.17.1` |
| 📐2 | `DiarizerConfig.clusteringThreshold` jest publiczne | źródła `Sources/FluidAudio/` |
| 📐3 | `VadManager` + model `silero-vad` (1 MB) **już leżą** w magazynie | `du` magazynu + źródła |
| 📐4 | `public struct CustomVocabularyTerm { public let aliases: [String]? }` | `CustomVocabularyContext.swift` — 1:1 z `replacements.tsv` (245 linii) |
| 📐5 | `MLComputeUnits` jest nastawialne — ANE da się ominąć | `MLModelConfigurationUtils.swift` |
| 📐6 | Domyślny katalog modeli = istniejący magazyn, zero pobierania | `defaultModelsDirectory()` |
| 📐7 | Tempo wydań: `v0.15.2` → `v0.17.1` w 3 tygodnie, 2 głównych autorów | GitHub API |
| 📐8 | Cache ANE MacParakeeta: **7,0 GB → 32 KB**. Cache jest odzyskiwany przez system | `du ~/Library/Caches/*/com.apple.e5rt.e5bundlecache` |
| 📐9 | Żadna z 5 aplikacji nie jest w App Store; tylko Narada ma sandbox | `_MASReceipt`, `codesign -d --entitlements` |
| 📐10 | SwiftUI + Core Audio budują się bez Xcode (25 s) | próbka SwiftPM w katalogu tymczasowym ⚠️ Poprawka: prawdziwe dla SwiftUI bez makr. W SDK macOS 27 @State, @Entry, @Animatable i #Preview są makrami z pluginu SwiftUIMacros, którego nie ma w Command Line Tools. Bez Xcode stan lokalny widoku idzie przez ObservableObject/@StateObject. |

⚠️ **Czego nie zmierzyłem:** ile cache'u ANE generuje Parakeet v3 uruchomiony przez
**naszą** aplikację. 📐8 pokazuje, że rachunek jest zwracalny, nie że jest mały. To pytanie
należy do specyfikacji transkrypcji, nie do tej — rdzeń nagrywania nie ładuje modeli.

---

## 3. Granica modułu

Rdzeń produkuje **sesję**: katalog ze ścieżkami audio i dziennikiem zdarzeń.

**Wie o:** urządzeniach audio, czasie hosta, zapisie plików, warunkach zakończenia.

**Nie wie o:** ASR, diaryzacji, notatkach, kalendarzu, UI, słowniku.

**Wejście:** `start()`, `stop()`, lista warunków końca.
**Wyjście:** katalog sesji, który da się odtworzyć i wyrównać bez pytania aplikacji o cokolwiek.

Ta granica jest tym, co pozwoli archiwum przeżyć wymianę silnika ASR — a ta wymiana jest
w planie jako scenariusz awaryjny, więc nie jest hipotetyczna.

---

## 4. Moduły i kontrakty

### `AudioSource` (protokół)

Dostarcza bufory PCM oraz **czas hosta pierwszej próbki**. Implementacje:

- `SystemTapSource` — process tap Core Audio, związany z urządzeniem wyjściowym
- `MicrophoneSource` — `AVAudioEngine`, opcjonalnie z przetwarzaniem głosu
- `FileSource` — odtwarza plik WAV deterministycznie

`FileSource` nie jest ozdobnikiem. Bez niego nie ma powtarzalnych testów, bo mikrofonu
i głośników nie da się zaskryptować. Jest też miejscem podmiany na ScreenCaptureKit,
gdyby próg macOS okazał się za wysoki.

### `TrackWriter`

Bierze bufory z **jednego** źródła i pisze do **jednego** pliku. Nie ma dostępu do innych
ścieżek.

🔴 Miksowanie jest tu **strukturalnie niemożliwe**, a nie zakazane komentarzem. To najtańsze
zabezpieczenie wady nieodwracalnej z rozdz. 18 — MacParakeet i Spokenly popełniły ją
w kodzie, który wyglądał poprawnie.

### `SessionJournal`

Dziennik `jsonl`, dopisywany i synchronizowany z dyskiem przy każdym zdarzeniu.

Zdarzenia: `session.started`, `track.opened` (id, czas hosta, częstotliwość, kanały,
`deviceUID`, format), `track.firstSample`, `track.clock` (indeks ramki, czas hosta — kotwica dla T8), `device.changed`, `track.gap` (początek, długość),
`track.permissionDenied` (które uprawnienie, jak wykryte — patrz T9), `track.failed` (powód: błąd źródła, a także `allZeros60s` — T9), `track.closed` (liczba
ramek), `session.ended` (powód).

### `DeviceWatcher`

Trzy obserwatory Core Audio: domyślne wejście, domyślne wyjście, lista urządzeń. Tyle samo,
ile instaluje Narada (rozdz. 18). 🆕 ⚠️ Bez nich przepięcie słuchawek w trakcie spotkania
urywa nagranie.

### `EndCondition` (protokół)

Nie pojedynczy `if`, tylko lista. W v1: `button`, `silence(minutes:)`, `hardLimit(hours:)`.
Pierwszy warunek, który zadziała, wygrywa; jego tożsamość trafia do `session.ended.reason`.

Kalendarz dojdzie później jako kolejna implementacja — bez dotykania rdzenia. To jest
konkretny powód, dla którego warunki są listą.

Faza 1 bez kalendarza: koniec sesji to najlepsza próba — cisza na wszystkich torach albo 4 h. Muzyka albo rozmowa w pokoju po spotkaniu utrzymają nagranie. W§1 jest w pełni spełnione dopiero z kalendarzem (faza 3); zamknięcie okna rozmowy — backlog fazy 3.

### `SessionRecorder`

Spina powyższe. Jedyny moduł widzący całość.

Każdy tor nadzorowany osobno: brak porcji przez 30 s (licząc od `track.opened`) → track.failed (stalled30s), sesja trwa z pozostałymi. Tor, który już ma track.failed z innego powodu, nie dostaje stalled30s. Gdy tor po stalled30s znów dostarcza porcje → `track.recovered`, a podsumowanie zdejmuje `failure`.

---

## 5. Format sesji na dysku

```
2026-09-24T14-03-11Z-a7f3/
  system.caf      PCM 48 kHz stereo — tap bit w bit, to JEST plik do odsłuchu
  mic_raw.caf     PCM 16 kHz mono — mikrofon surowy, zero przetwarzania
  mic_aec.caf     PCM 16 kHz mono — mikrofon po platformowym AEC
  journal.jsonl   dziennik zdarzeń, dopisywany, fsync
  session.json    podsumowanie — pochodna dziennika, pisana na końcu
```

**Trzy pliki audio, nie cztery.** Narada zapisuje osobny plik „do odsłuchu"; skoro jest on
bit w bit tapem systemowym (R² = 1.000, rozdz. 18), to plikiem do odsłuchu **jest** tap.

**Dziennik jest źródłem prawdy, `session.json` tylko wygodą.** Brak podsumowania odtwarzamy
z dziennika. To jest cała trwałość w jednym zdaniu.

**Kontener CAF, nie `.m4a`.** MP4 wymaga atomu `moov` zapisywanego przy zamknięciu — ubicie
procesu daje plik nie do odczytania. CAF przeżywa obcięcie.

**PCM w v1, kompresja po sesji.** Brak kodera na gorącej ścieżce, brak strat, a test T1
(R² = 1.000) ma sens wyłącznie na nieskompresowanym.

Koszt miejsca dla sesji 85-minutowej:

| Ścieżka | Format | Rozmiar |
|---|---|---|
| `system.caf` | 48 kHz stereo 16-bit | ~979 MB |
| `mic_raw.caf` | 16 kHz mono 16-bit | ~163 MB |
| `mic_aec.caf` | 16 kHz mono 16-bit | ~163 MB |
| **razem** | | **~1,3 GB** |

Kompresja do Opusa jest osobnym, wznawialnym krokiem po sesji. Oryginały kasuje wyłącznie
jawna polityka retencji — domyślnie nie kasuje ich nic.

✏️ **Uzgodnienie 2026-10-16 (decyzja użytkownika, macos.md §11.5 „Recordings”):** polityka retencji
istnieje i ma domyślny termin — „Keep audio” 7 / 14 / **30 (domyślnie)** / 90 dni / Forever. Po terminie
kasowane są **tylko** `*.caf` sesji (transkrypt, notatki, My notes, dziennik i meta zostają), a sesja
dostaje znacznik `audio-deleted.json` (`afterDays`, `deletedAt`). Audio sesji bez ukończonej transkrypcji
(najnowszy przebieg bez transkryptu albo z lukami), nagrywanej lub przetwarzanej nie jest kasowane. Wiek
liczony od `wallClock` zdarzenia `session.started`. Kod: `MeetNotesNotes/Recordings.swift` (`AudioRetention`).

⚠️ Mikrofon w 16 kHz mono to decyzja świadoma: tyle chce ASR, a kanał mikrofonu nie służy
do odsłuchu. Jeśli kiedyś ma służyć, trzeba to zmienić przed nagraniem, nie po.

---

## 6. Kotwica czasu

Wszystko w `mach_absolute_time`, przeliczane względem jednego odniesienia z chwili startu
sesji. Każda ścieżka zapisuje czas hosta **swojej pierwszej próbki**.

🔴 Rozjazd to **różnica tych dwóch liczb** — nigdy założenie, że obie ruszyły przy naciśnięciu
przycisku. Zmierzone wartości: 165 ms u Narady, do ~2 s u Spokenly (rozdz. 17, 18). Powyżej
~40 ms jest słyszalny.

**Oś czasu sesji taktuje ścieżka systemowa**, jak u Narady. Powód jest konkretny: platformowy
AEC opóźnia start mikrofonu. Gdyby to mikrofon taktował oś, włączenie AEC przesuwałoby całą
sesję.

---

## 7. Awarie i zdarzenia

| Zdarzenie | Zachowanie |
|---|---|
| **Przepięcie urządzenia w trakcie** | Ten sam plik, luka wypełniona ciszą, dziennik zapisuje dokładny czas i długość luki. Ciągłość osi zostaje, luka jest jawna |
| **Brak zgody na mikrofon** | Sesja leci z samym systemem, dziennik to odnotowuje. Nagranie połowiczne bije nagranie żadne |
| **Brak miejsca na dysku** | Czyste zatrzymanie z zapisanym powodem, bez uszkadzania plików |
| **Ubicie procesu** | Dziennik odtwarza sesję; pliki CAF są odtwarzalne mimo obcięcia |

---

## 8. Toolchain, dysk, dystrybucja

### Bez Xcode

📐10: `import SwiftUI` + `CATapDescription` budują się na samych Command Line Tools
(SDK 27.0, Swift 6.4) w 25 sekund. Oszczędza kilkanaście GB.

🔴 **Podpis ad-hoc zmienia `cdhash` przy każdej przebudowie, więc TCC resetuje uprawnienia**
(mikrofon, dźwięk systemowy). Obejście: stały certyfikat samopodpisany w pęku kluczy.

Pierwotnie zapisane tu jako „do rozstrzygnięcia w planie". Po dodaniu setupu przy pierwszym
uruchomieniu (spec fazy 1, §1.3) to już nie niedogodność: bez stałego podpisu kreator
uruchamiałby się po każdym `swift build`. **Zadanie na dzień pierwszy.**

⚠️ Poprawka: prawdziwe dla SwiftUI bez makr. W SDK macOS 27 @State, @Entry, @Animatable i #Preview są makrami z pluginu SwiftUIMacros, którego nie ma w Command Line Tools. Bez Xcode stan lokalny widoku idzie przez ObservableObject/@StateObject.

### Kontenery: nie

`container` Apple'a, Colima i OrbStack uruchamiają maszyny wirtualne z **Linuksem** —
aplikacja macOS tam nie pójdzie. VM z macOS też nie pomoże: przedmiotem testu jest
przechwytywanie dźwięku **tej** maszyny (tap, TCC, przepinanie urządzeń). Izolacja od maszyny
usuwa przedmiot testu, a obraz systemu waży więcej niż całe archiwum.

Kontener ma sens dla narzędzi pomiarowych w Pythonie (dopasowania R², korelacje AEC, analiza
korpusu) — tam izolacja niczego nie psuje.

### Higiena dysku

| Co | Gdzie | Sprzątanie |
|---|---|---|
| Zależności SwiftPM | `./.build/` | `rm -rf .build` |
| Xcode | nie instalujemy | — |
| Modele | istniejący magazyn, tylko do odczytu | nic nie przybywa |
| Dane aplikacji w trakcie prac | katalog w repo przez zmienną środowiskową | `rm -rf` |
| Cache ANE | `~/Library/Caches/<bundle-id>/` | odzyskiwany przez system (📐8) |
| Archiwum audio | katalog projektu w trakcie prac | skrypt odinstalowujący wypisuje każdą ścieżkę |

### Dystrybucja: bez sandboxa

📐9: żadna z pięciu zmierzonych aplikacji nie jest w App Store. Tylko Narada ma sandbox —
i mimo to ściąga własne modele (jej kontener ma 36 KB).

🔴 **Sandbox odcina dostęp do cudzego `Application Support`**, czyli do wspólnego magazynu
modeli. Sandbox = własna kopia = 482 MB pobierania. Bez sandboxa czytamy to, co leży.

Homebrew cask nie wymaga sandboxa, tylko notaryzacji. Droga do App Store zostaje zamknięta,
ale nie wszedł tam nikt z tej piątki. Decyzja jest odwracalna: źródło modeli siedzi za
interfejsem, więc koszt zmiany to pobranie, nie przebudowa.

---

## 9. Testy odbiorcze

Pomiary z badań stają się testami. 🔴 Każdy dostaje **test mutacyjny** — wstrzykujemy błąd,
sprawdzamy czerwień, cofamy. Rozdz. 1 wniosków: zielony test bez mutacji nie dowodzi niczego,
a w poprzednim projekcie trzy razy okazało się, że testy chroniły nie to, co miały.

| # | Co sprawdza | Próg | Mutacja |
|---|---|---|---|
| **T1** | Odsłuch jest tapem. Odtwarzamy znany plik przez wyjście, nagrywamy, dopasowujemy `system ≈ a·oryginał` | R² ≥ 0,999 | domieszać 1% mikrofonu → czerwień |
| **T2** | Rozjazd startu jest **zmierzony i zapisany**, nie mały | obecność w manifeście | sztuczne 500 ms → manifest ma pokazać ~500 ms |
| **T3** | AEC działa. Głośniki grają, użytkownik milczy | korelacja `mic_aec` × `system` ≤ 0,12 | wyłączyć AEC → czerwień |
| **T4** | Zero miksu w odsłuchu. W słuchawkach (bez echa akustycznego), użytkownik mówi, nic nie gra: dopasowanie `system ≈ a·mic_raw` | a ≈ 0 | domieszać mikrofon do ścieżki systemowej → czerwień |
| **T5** | Koniec z ciszy. Konfiguracja testowa N = 1 min | `reason == silence` w ciągu 90 s | usunąć warunek → czerwień |
| **T6** | Przepięcie urządzenia w trakcie | sesja trwa, `device.changed` i `track.gap` w dzienniku | — |
| **T7** | `kill -9` w połowie sesji | dziennik odtwarza `session.json`, pliki grają | zapisać rozmiar bloku data 0 zamiast -1 → czerwień |
| **T8** | Sesja 85+ min | czas hosta dowolnej ramki, odtworzony z kotwic `track.clock`, różni się od prawdziwego o ≤ 50 ms; rzeczywista częstotliwość każdej ścieżki jest zapisana w podsumowaniu | liczyć czas z nominalnej częstotliwości → czerwień |
| **T9** | Odmowa uprawnienia dźwięku systemowego daje **jawny błąd**, nie cichy plik | sesja nie startuje albo dziennik ma `track.permissionDenied`; zero ścieżek pełnych zer udających nagranie | wyłączyć sprawdzenie → czerwień |

✏️ **Korekta.** Pierwsza wersja dopasowywała mic_raw ≈ a·system i żądała a ≈ 0 — ale surowy mikrofon przy głośnikach musi zawierać echo systemu. Intencja testu: mikrofon nie trafia do pliku odsłuchu.

✏️ **Korekta 2026-09-29 (T3).** Po sondzie S5 (`reports/S5-ducking-konsultacja.md`) `mic_aec` powstaje tylko z `--aec`, więc T3 dotyczy wyłącznie tego trybu. Nagranie domyślne nie ma `mic_aec` i T3 go nie obejmuje. Echo w domyślnym `mic_raw` usunie AEC offline (`mic_raw` + `system`), planowany po planie 05.

✏️ **Korekta.** Usunięcie fsync nie da się wykazać testem: po kill -9 dane z pamięci podręcznej systemu i tak trafiają na dysk, fsync chroni tylko przed utratą zasilania. Mutacją T7 jest więc nagłówek CAF.

⚠️ **T9 wyrasta z hipotezy, nie z pomiaru.** Nie ma publicznego API do sprawdzenia stanu tego
uprawnienia (spec fazy 1, §1.3). Jeśli tap przy odmowie oddaje **ciszę zamiast błędu**,
aplikacja nagra 85 minut niczego i będzie przy tym wyglądać na zdrową. Rdzeń ma chronić
archiwum właśnie przed takim scenariuszem, więc zanim powstanie setup, trzeba to sprawdzić
sondą. Jeśli tap zwraca błąd, T9 staje się zwykłym testem obsługi błędu.

Zakres: strażnik zer obejmuje ścieżkę system. Odmowę mikrofonu wykrywa publiczne API (AVCaptureDevice.authorizationStatus) w prepare(); gdyby mikrofon przy odmowie oddawał zera zamiast błędu, nic tego nie wykryje — świadoma luka fazy 1, do rozszerzenia strażnika, jeśli S1 albo D3 pokażą taki przypadek.

⚠️ **T3 i T4 wymagają przepróbkowania.** `system.caf` jest w 48 kHz stereo, kanały mikrofonu
w 16 kHz mono — korelacji nie liczy się na surowych plikach. Test przepróbkowuje obie ścieżki
do 16 kHz mono i wyrównuje je kotwicą czasu z §6 przed dopasowaniem. Pominięcie wyrównania
daje fałszywie niską korelację, czyli **test przechodzący z błędnego powodu** — dokładnie ta
klasa awarii, przed którą ostrzega rozdz. 1.

**T8 rozdziela dwie różne rzeczy.** Rozjazd *wewnątrz* ścieżki to błąd przeliczania zegara
i musi być bliski zeru. Rozjazd *między* ścieżkami to realna różnica zegarów dwóch urządzeń
— Narada zmierzyła 901,269 s wobec 901,056 s, czyli 213 ms na 901 s. Tego nie wolno
„naprawiać", tylko zapisać, bo wyrównanie to zadanie odtwarzania, nie nagrywania.

✏️ **Korekta z pisania planu.** Pierwsza wersja T8 porównywała czas hosta z długością liczoną
z nominalnej częstotliwości i żądała ≤ 50 ms na ścieżkę. To nie przejdzie na żadnej długiej
sesji: zegar urządzenia dryfuje względem zegara hosta o setki ppm (Narada: 213 ms na 901 s),
czyli o ~0,5 s na 85 minut — i to nie jest błąd, tylko fizyka. Rdzeń zapisuje więc kotwice
`(ramka, czas hosta)` co 10 s i po każdej luce, a T8 sprawdza odtworzenie czasu z kotwic.

T1, T3 i T4 to dokładnie te trzy liczby, które odróżniły Naradę od MacParakeeta i Spokenly
(rozdz. 18). Jeśli przechodzą, rdzeń jest mierzalnie lepszy od czterech z pięciu zmierzonych
aplikacji.

⚠️ **T8 wymaga materiału.** Pliki korpusu z rozdz. 13, 14 i 17 trzeba odnaleźć albo nagrać
ponownie. To zadanie planu, nie designu.

---

## 10. Relacja do analizy Hermesa

`docs/brainstorm-asr.md` i `docs/plan.md` to niezależna analiza z tego samego dnia. Wnioski
zbieżne w każdym punkcie, który dotyczy tego podsystemu: process tap (P5), próg macOS
z testu (P6), `mic_raw` obok `mic_aec` (P11), start ręczny, warunki końca jako lista.

**Co ta specyfikacja domyka z eksperymentów E0 Hermesa** (zaprojektowanych, niewykonanych):

| Hermes | Status |
|---|---|
| E0a — minimum macOS FluidAudio | ✅ 📐1: `.macOS(.v14)` |
| E0b — licencja biblioteki | ✅ 📐1: Apache-2.0 (⚠️ licencja **wag** v3 nadal niesprawdzona) |
| E0c — tempo łamiących zmian | ✅ 📐7: ~1 wydanie tygodniowo → twarde przypięcie wersji |
| E0e — wybór jednostek obliczeniowych | ✅ 📐5: `MLComputeUnits` nastawialne |
| E0f — format katalogu modeli | ✅ 📐6: domyślna ścieżka = istniejący magazyn |
| E0g — sandbox a wspólny magazyn | ✅ 📐9 + §8: potwierdzone, decyzja podjęta |
| E0d — znaczniki czasu słów | ⚠️ otwarte — należy do specyfikacji transkrypcji |
| E1 — cache ANE dla v3 | ⚠️ częściowo: 📐8 pokazuje zwracalność, nie wielkość |

**Różnica w ocenie:** Hermes traktuje rachunek ANE jako bramkę decyzyjną przed etapem ASR.
📐8 osłabia ten argument — cache jest zarządzany przez system i odzyskiwany, więc jest
kosztem wydajności przy zimnym starcie, nie kosztem instalacji. Nie zmienia to rekomendacji
(oba dokumenty wybierają FluidAudio), zmienia wagę ryzyka.

---

## 11. Czego ten dokument nie rozstrzyga

| Sprawa | Gdzie należy |
|---|---|
| Silnik ASR, cache ANE, boosting słownika | specyfikacja transkrypcji |
| Próg klastrowania, tożsamość mówcy | specyfikacja diaryzacji |
| Kodek i bitrate kompresji po sesji | plan, po pomiarze wpływu na ASR |
| Wartość N dla warunku ciszy | plan; wartość startowa 10 min, nastawialna |
| Minimalna wersja macOS | plan: ta, na której przejdzie zestaw T1–T9. Narada wymaga 15.6 mimo API od 14.4 — z nieznanego powodu (rozdz. 6) |
| Stały certyfikat a reset TCC | ~~plan~~ → **rozstrzygnięte:** zadanie na dzień pierwszy (§8) |
| Sprawdzanie stanu uprawnienia dźwięku systemowego | spec fazy 1, §1.3 i O5; sonda przed T9 |
| Framework UI i magazyn danych | poza rdzeniem nagrywania |
| Retencja archiwum | domyślnie brak kasowania; polityka to osobna decyzja |
| Czy surowy mikrofon (HAL) i mikrofon z AEC (AVAudioEngine + przetwarzanie głosu) dają się nagrywać jednocześnie | sonda S2 w planie A (A10). Jeśli nie — decyzja użytkownika, który strumień porzucić |
