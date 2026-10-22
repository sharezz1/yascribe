# Faza 2.0.2: Nagrywanie na słuchawkach Bluetooth (specyfikacja)

Status: **szkic do decyzji użytkownika** (2026-10-22), bez kodu. Faza przypisana przez użytkownika 2026-10-22.
Dowody: `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md` (pomiar S0, trzy nagrania, kod i zgłoszenia FluidVoice, Meetily, OpenWhispr)
i pozycja „PRIORYTET WYSOKI … słuchawki Bluetooth" w `docs/superpowers/BACKLOG.md`.
Wszystkie przyczyny poniżej są **hipotezami**, dopóki nie padną w pomiarze po zmianie.

## 1. Po co

Spotkanie na słuchawkach Bluetooth to codzienny przypadek użytkownika. Dziś tor „Them" (`system`) bywa wtedy pusty, za wolny albo za szybki, a pigułka nie mówi dlaczego.
Skutek: w notatce brakuje rozmówców, bez żadnego błędu w aplikacji. To rodzaj usterki, której użytkownik nie zauważa, dopóki nie przeczyta transkryptu.

Kryterium sukcesu: nagranie na słuchawkach daje tor `system` z poprawną prędkością (zegar do pliku 1,0, tolerancja jak dla urządzeń wbudowanych, ok. ±0,1 %), albo aplikacja **wyraźnie mówi**, że tor jest martwy, zanim spotkanie się skończy.

Anty-cel: poprawka, która psuje działającą konfigurację (urządzenia wbudowane, sesja `82c4`: 47 998 Hz, zegar 1,0) albo po cichu zmienia, który mikrofon nagrywamy.

## 2. Co zmierzono (skrót S0)

| Wejście / wyjście | Tor `system` |
|---|---|
| słuchawki / słuchawki (A) | 0 klatek mimo grającego dźwięku; w BACKLOG (`ec0b`) ta sama konfiguracja dała klatki ok. 3× za wolne |
| MacBook / słuchawki (C) | działa, ale 44 100 Hz zapisane jako 48 000 (plik ok. 8,8 % za szybki) |
| słuchawki / głośniki MacBooka (B) | zdrowy, 48 000 Hz |
| wbudowane / wbudowane (`82c4`) | zdrowy |

Trzy osobne zjawiska: **A** martwy lub zwolniony tap, gdy mikrofon i wyjście są na tych samych słuchawkach (tryb rozmowy HFP);
**C** rozjazd częstotliwości przy samym wyjściu na słuchawkach (A2DP); **D** (z BACKLOG) pigułka milczy, gdy tor jest martwy (naprawione w PR #17 dla przypadku „0 klatek po 30 s").

## 3. Opcje

**Dowód z innych aplikacji (2026-10-22).** Użytkownik sprawdził na tych samych słuchawkach: **Wispr Flow i Granola nagrywają dźwięk systemowy poprawnie**, więc obejście istnieje (konfiguracja, w której sprawdzał, nie jest zapisana; zakładam A, do potwierdzenia przez użytkownika).
Odczyt zainstalowanych binarek (tylko `strings`, bez uruchamiania): **Granola** używa ScreenCaptureKit (`macos_audio_capture.node` zawiera `SCStream`, `SCStreamOutput`, `ScreenCaptureKitListener`; brak `CATapDescription`).
**Wispr Flow** prosi o `kTCCServiceAudioCapture` (uprawnienie „tylko dźwięk", jak nasz tap); jego helper Swift ma `deviceTransportType`, ale kodu samego przechwytywania w sprawdzonych plikach nie znalazłem, więc jego mechanizmu nie znam.
Wniosek: **oba mechanizmy mogą działać na tych słuchawkach**; tap nie jest z natury martwy, a różnica jest w sposobie budowy. To podnosi wagę opcji S (jedna z dwóch działających aplikacji ją stosuje) i uzasadnia spike S1 niezależnie od wyniku T.

### Opcja T: zostać przy process tapie Core Audio i naprawić go (rekomendacja)

Zmiany, od najtańszej:
1. **T1, urządzenie zbiorcze bez wyjścia jako podurządzenia** (`kAudioAggregateDeviceSubDeviceListKey` puste, bez `…MainSubDeviceKey`), jak u OpenWhispr (`resources/macos-audio-tap.swift`).
   Hipoteza: zegar urządzenia zbiorczego przestaje być zegarem wyjścia Bluetooth, więc znika rozjazd z C, a tap wysyła porcje także przy ciszy (u OpenWhispr tak jest; u nas przy ciszy 0 klatek).
   Ryzyko: odwraca decyzję z kodu fazy 1 (tap „związany z urządzeniem wyjściowym", `SystemTapSource.swift`, `…MainSubDeviceKey`) i może zmienić dryf. Wymaga pomiaru na wbudowanych urządzeniach i na słuchawkach.
2. **T2, częstotliwość z urządzenia, nie z tapa:** po utworzeniu urządzenia zbiorczego odczytać `kAudioDevicePropertyNominalSampleRate` i, gdy różni się od `tapFormat`, przeliczyć (`AVAudioConverter`) do deklarowanej w CAF.
   Naprawia C niezależnie od T1. Test: tap z formatem innym niż zapisany (mutacja bramki).
3. **T3, nasłuch zmian:** `kAudioStreamPropertyVirtualFormat` i `kAudioDevicePropertyNominalSampleRate` urządzenia zbiorczego, plus istniejące `device.changed`; przy zmianie przebudować taśmę (`rebuild()` już jest) i wpisać zdarzenie do dziennika.
   FluidVoice #592 opisuje dokładnie ten brak jako przyczynę „time-stretched" audio po przejściu A2DP→HFP.
4. **T4, alarm o martwym torze podczas spotkania:** pigułka po 30 s bez klatek już pokazuje „No system audio yet · <wyjście>" (PR #17). Dodać: gdy **mikrofon i wyjście to to samo urządzenie Bluetooth**, komunikat podpowiada przyczynę
   („Headset in call mode may block system audio. Use the Mac's microphone or speakers."). Informacja, nie błąd; cisza w poczekalni dalej jest normalna.
5. **T5, ostrzeżenie w widoku spotkania po nagraniu:** gdy `czas toru / czas sesji` odbiega od 1 o więcej niż 5 %, wiersz ostrzeżenia ze stosunkiem i urządzeniami (z dziennika). Dotyczy A i C.

### Opcja S: ScreenCaptureKit zamiast tapa

Co daje: FluidVoice i Meetily biorą tak dźwięk rozmowy (`SCStream`, `sampleRate = 48_000`, `channelCount = 2`); strumień nie zależy od wyjścia, a system sam zmienia częstotliwość. Meetily po #138 (AirPods bez rozmówców) wskazuje wydanie 0.1.1 jako poprawkę, bez szczegółów.
Czego **nie wiemy**: czy działa na tych słuchawkach (A), bo nikt nie pokazał pomiaru; Meetily #450 pokazuje, że mikrofon Bluetooth u nich dalej nie działa.
Koszt, rozpoznany w dokumentach repo:
- **Uprawnienie Screen Recording** zamiast „tylko dźwięk" (`NSAudioCaptureUsageDescription`, `kTCCServiceAudioCapture`). Specyfikacja warstwy dostawców (§ o TCC) uznaje za „realną przewagę w zaufaniu", że aplikacja **strukturalnie nie może widzieć ekranu**; SCK to odwraca.
  Zgodę zmienia wyłącznie użytkownik (reguła projektu: nie ruszamy TCC); stały podpis „MeetNotes Dev" ten problem już zna.
- Decyzja P5 z `docs/plan.md` (process tap: pomiary Narady R² = 1,000, odsłuch bit w bit, bez linkowania ScreenCaptureKit) i spec rdzenia §1 byłyby odwrócone.
- Dla fazy: nowa implementacja `AudioSource`, nowy bloker uprawnień, ponowny odbiór nagrywania.
Zaleta: `SystemTapSource` został zaprojektowany jako miejsce podmiany na SCK (spec rdzenia, sekcja o `FileSource`), więc szew istnieje.

### Wybór mikrofonu i wyjścia przed startem

Osobna sprawa (spec 1.5 decyzja 4; BACKLOG): aplikacja nagrywa **domyślne** urządzenia systemu, nie te, których używa Teams. Naprawia A „u źródła" (nie otwieramy mikrofonu słuchawek, więc nie wchodzimy w HFP),
ale jest funkcją interfejsu z własną specyfikacją. Poza zakresem 2.0.2, chyba że użytkownik zdecyduje inaczej (D3).

## 4. Rekomendacja

Opcja T, w kolejności T2 → T3 → T1 (eksperyment) → T4 → T5, każdy krok z pomiarem na słuchawkach tymi samymi trzema nagraniami (A, B, C). Opcja S jako **spike S1 równolegle**, niezależnie od wyniku T, żeby mieć pomiar zamiast przypuszczeń
(throwaway CLI przechwytujący przez SCK przy konfiguracji A, wymaga zgody użytkownika na Screen Recording dla tego jednego narzędzia; wynik: czy SCK daje klatki i poprawną prędkość w A, B, C). Uzasadnienie: T zmienia mało kodu i nie dotyka zaufania do aplikacji;
S odwraca dwie jawne decyzje projektu, ale Granola dowodzi, że SCK działa na tych słuchawkach, więc wart pomiaru. Jeśli S1 rozwiąże A, a T nie, decyzja o przejściu na S wraca do użytkownika z danymi.

## 5. Decyzje użytkownika

- **D1.** Czy rekomendacja (T plus równoległy spike S1 jako pomiar) jest przyjęta, czy chcesz S od razu?
- **D1a.** W jakiej konfiguracji sprawdzałeś Wispr Flow i Granolę (wejście i wyjście na słuchawkach, jak A)?
- **D2.** Przypadek A: czy dopuszczasz, żeby aplikacja **sama** wybrała wbudowany mikrofon, gdy domyślne wejście i wyjście to to samo urządzenie Bluetooth (z widoczną informacją w pigułce),
  czy ma tylko ostrzegać (T4) i nagrywać domyślne? Automat zmienia, czyj głos nagrywamy, dlatego pytam.
- **D3.** Czy wybór mikrofonu i wyjścia przed startem wchodzi do 2.0.2, czy osobna faza (moja propozycja: osobna)?
- **D4.** Czy T1 (zmiana budowy urządzenia zbiorczego) ma wejść do kodu produkcyjnego dopiero po pomiarze, że niczego nie psuje na urządzeniach wbudowanych? (rekomendacja: tak)

## 6. Do ustalenia przez wykonawcę

Progi T5 (5 %), dokładny tekst T4, nazwa zdarzenia dziennika przy zmianie formatu, test na bazie `FileSource` ze stałym formatem różnym od zapisanego.
Wykonawca nie zmienia ustawień systemowych ani uprawnień TCC; każdy pomiar na sprzęcie wykonuje użytkownik.

## 7. Czego nie zmierzono

Odsłuch i transkrypcja toru z C; zachowanie pigułki w A; poczekalnia Teams z domyślnymi urządzeniami MacBooka od startu; czy T1 w ogóle zmienia zegar.
