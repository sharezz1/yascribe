# D3 — odbiór ręczny aplikacji

Data: 2026-10-13 (S17). Środowisko: macOS 27, build debug z `scripts/run.sh`, podpis `MeetNotes Dev`
(certyfikat samopodpisany), dane w `.devdata`. Model: **użytkownik wykonuje, orkiestrator prowadzi
i weryfikuje** (tryb jak S13/S9). Weryfikacja: drzewo dostępności okna (AX), pliki sesji
(`session.json`, `journal.jsonl`, `preset.json`, `runs/*/run.json`, `chunks/`), pomiary audio
(`mn-rms.py`, `whisper-cli`), `codesign`, `pgrep`, `defaults read`.

Narzędzie pomocnicze napisane w tej sesji: `~/.hermes/meetnotes-orchestrator/tools/mn-runinfo.py`
(tory, offset, luki, przebiegi: `chunkCount`/`requestCount`/migawka, transkrypt).

## Kroki 1–6 (wykonane przez użytkownika przed przejęciem prowadzenia)

✅ — szczegóły uwag: `reports/S17-uwagi-uzytkownika.md`. Sesja dowodowa
`.devdata/sessions/2026-10-13T07-39-44Z-ee07` (przebieg 3 okna, 0 nieudanych, 15 wypowiedzi),
komity użytkownika `67de1f2`, `4a3085f`, `1c38338`.

## Krok 7 — Cmd-, i klawiatura

- ✅ **Cmd-, przełącza na Settings** — trzema drogami: z Meetings, z Presets (z otwartym edytorem)
  i pozycją menu `MeetNotes → Settings…`. Dowód: AX przed/po — tytuł okna „Meetings" → „Settings",
  w treści kontrolki Settings (`Refresh Models`, `Add Provider…`, wybór dostawcy, embedding).
  *Uwaga diagnostyczna*: pierwsza próba z Presets została zgłoszona jako „nie działa"; po
  rozdzieleniu dróg (menu vs skrót) i powtórzeniu okazała się fałszywym alarmem — **nie zapisano
  jako defektu**.
- ✅ **Tab/Shift-Tab** — „Nawigacja klawiaturą" włączona (`defaults read -g AppleKeyboardUIMode` = 2).
  Settings: przechodzi po kontrolkach; Presets: Name → Language → Provider → Model → lista modeli,
  Shift-Tab wraca; Meetings: preset → Record → wyszukiwarka, potem zawija do początku.

## Krok 8 — Wygląd

- ✅ **Tryb ciemny i jasny** — czytelne w Meetings (nagłówek dnia, wiersze sesji), w widoku
  spotkania (czasy jako linki, „Me"/„Them", tekst), w Presets i Settings. Sprawdzone na zrzutach
  użytkownika i własnych zrzutach okna.
- ✅ **Reduce Motion** — relacja użytkownika (sprawdzone wcześniej: ikona w pływającym oknie nie
  pulsuje). Kod: `RecordingController.swift:88-97` (`symbolEffect(.pulse, isActive: !reduceMotion)`).
- ✅ **VoiceOver na liście sesji** — relacja użytkownika (czyta wiersz). Proces po teście zgaszony
  (sprawdzone `pgrep -lf VoiceOver` — brak).

## Krok 8b — poprawki z E4 + checklista S15fix

- ✅ **Pływające okno bez nagrania** (`Recording → Show Recording Window`) — panel z wyborem presetu
  i przyciskiem „Record", bez licznika; brak nowego katalogu sesji (nic się nie nagrało).
- ✅ **Odsłuch przy usuniętym pliku mikrofonu** — `mic_raw.caf` schowany (`mv … .caf.off`); klik
  w czas wiersza „Me" → czytelny komunikat
  *„Something went wrong — Couldn't open the mic_raw recording: The operation couldn't be
  completed. (OSStatus error 2003334207.)"*; po przywróceniu pliku ponowne kliknięcie **gra**
  (druga połowa testu: „czytelny błąd, ponowna próba").
- ✅ **Dostawca bez klucza** — dodany dostawca bez klucza → `Refresh Models` →
  *„No API key for OpenRouter. Remove the provider and add it again with a key."*; sprzątnięty
  (jeden dostawca, `providers.json` bez zmian).
- ✅ **Preset zamrożony przy starcie** — cztery nagrania (11:02 i 11:03 z Polski `pl`, 11:04 i 11:10
  z English `en`); w każdym `<sesja>/preset.json` == migawka `runs/*/run.json`. Przełączenie chipu
  w trakcie nagrania nie zmieniło przebiegu transkrypcji (relacja użytkownika + dowód w plikach).
- ✅ **Blokada drugiego nagrania** — ⌘⇧R jest **przełącznikiem** (`MeetNotesApp.swift:23-27`: jedna
  pozycja „Record Meeting"/„Stop Recording"), więc drugie naciśnięcie zatrzymuje nagranie, a nie
  startuje drugiego. Guard istnieje w kodzie (`AppModel.startRecording` → „A recording is already in
  progress."; `RecordingController.StartError.alreadyRecording`), ale **z UI nieosiągalny** — żadna
  ścieżka interfejsu nie woła `startRecording`, gdy trwa nagranie. Zapisane jako „pokrywa kod".
- ✅ **Prawdziwe spotkanie (Teams, 128 s)** — oba tory, brak luk w nagraniu; transkrypt 33 wypowiedzi
  (13 Me / 20 Them), 2 flagi języka. Odsłuch: `system.caf` ma treść spotkania — whisper na 30-s
  wycinku: *„Yeah, we'll see. - Okay. Let's turn this off. Turn that off. I recorded him, just save my
  changes, why?"*; RMS −26,7 dBFS, peak −4,2 dBFS.
- ✅ **Me = Twój głos** — osobne nagranie 12:17 (`system` 0,00 s, `mic_raw` 10,09 s, preset Polski):
  klik w wiersz „Me" gra własny głos; transkrypt: „Raz, dwa, trzy, cztery, pięć, sześć, dzień dobry…".
- ✅ **Przerwanie w trakcie transkrypcji (⌘Q)** — po Stop i ⌘Q wiersz pokazuje **„Interrupted"**
  (sprawdzone zrzutem), a `runs/<id>/` przerwanego przebiegu ma `input.json` i **brak** `run.json`.
- ✅ **„Resume Transcription"** — po restarcie wznowienie pisze do **tego samego** katalogu przebiegu
  (`…09-13-06Z-ce4c`) z migawką z `input.json`: język **en**, preset **English**, `requestCount` = 3 =
  `chunkCount` = wszystkie brakujące okna. Ten sam `runID` jest dowodem, że poszła ścieżka `resume`
  (nowy przycisk „Transcribe with…" tworzy nowy runID — zaobserwowane przy pomylonym kliknięciu).
- ✅ **Transkrypt pojawia się sam** w otwartym widoku spotkania po zakończeniu transkrypcji (🟡).
- ✅ **Nagrywanie bez ważnego presetu** — relacja użytkownika (sprawdzone wcześniej); kod:
  `AppModel.swift:200-204` (komunikat „Choose a preset with a language before recording." +
  `section = .presets`).
- ⚠️ **Podwójne „Retry Failed Parts"** — **nie pokryte na żywo**: przycisk pokazuje się tylko przy
  transkrypcie z lukami, a żadna z 12 sesji nie ma `failedChunks`. Pokrywa kod (`transcribing`,
  `busy` w `MeetingDetailView`).

## Krok 9 — przebudowa a TCC

- ✅ **A.** `scripts/run.sh` (podpis certyfikatem) → aplikacja wstaje, **brak arkusza uprawnień**
  i monitu o mikrofon (`Authority=MeetNotes Dev`).
- ✅ **B.** `MEETNOTES_SIGN_IDENTITY=- scripts/run.sh` (podpis ad-hoc, `Signature=adhoc`) → **arkusz
  „Set up recording" wraca** (dwa okna: główne + arkusz 480×265).
- ✅ **C.** powrót do podpisu certyfikatem → arkusz znowu znika; nagranie 5–10 s ruszyło **bez
  żadnego monitu**.
- Wniosek: uprawnienia TCC wiszą na podpisie, nie na ścieżce paczki — potwierdza spec rdzenia §8.

## Krok 10 — wyniki i commit

Ten plik + odhaczone kroki w `plans/2026-09-24-faza1-04-powloka-aplikacji.md` (zadanie D3) + wpisy
do `docs/superpowers/BACKLOG.md`.

## Odkrycia z odbioru (poza listą kroków)

1. **❌ W trakcie nagrania lista pokazuje sesję w toku jako osobny wiersz ze statusem „Recovered"**
   (zaobserwowane 4×: 10:54, 11:04, 12:24, 12:27 — ostatnie potwierdzone zrzutem na żywo, gdy
   w dzienniku `2026-10-13T10-27-14Z-6d17` nie było jeszcze `session.ended`). Dwie warstwy:
   - **etykieta** — podsumowanie liczone z dziennika startuje z `crashed: true`
     (`SessionSummary.swift:82`) i zdejmuje je dopiero `session.ended` (`:123-125`), a lista sprawdza
     `crashed` jako pierwszy warunek (`MeetingsView.swift:127-128`) → „Recovered" („aplikacja padła
     w trakcie") dostaje każde trwające nagranie;
   - **wiersza nie powinno tam być** — filtr `s.url != model.recording.directory`
     (`MeetingsView.swift:17-20`) nie odsiewa sesji w toku. Najbardziej oczywistą przyczynę
     (nierówność URL-i) wykluczono doświadczalnie: URL z `appendingPathComponent` == URL
     z `contentsOfDirectory` (test w Swifcie). Przyczyna nieustalona z lektury kodu — kandydat
     pierwszy do sprawdzenia: porównywanie po `lastPathComponent`.
2. **⚠️ Preset w oknie głównym jest nieczytelny** — toolbar pokazuje **samą ikonę** (bez nazwy), więc
   kryterium kroku 4 („chip przy Record pokazuje język") nie jest widoczne bez rozwijania menu;
   etykieta dostępności tego elementu to wręcz „Edit", więc VoiceOver nie powie, jaki preset jest
   wybrany. Nazwa jest widoczna w menu, w pływającym oknie i — w trakcie nagrania — w wierszu listy
   i w panelu. Do przeprojektowania razem z uwagami 1–7 z `reports/S17-uwagi-uzytkownika.md`.
3. **Uwaga pomiarowa: nagranie bez dźwięku systemowego degeneruje oś sesji.** 12:17: tor `system`
   0,00 s przy 10,09 s mikrofonu; 12:27: `system` 3,72 s przy 60,80 s mikrofonu → `offsetSeconds`
   mikrofonu −57,08 s, a wiersz pokazuje „0 min". Transkrypcja mówionych fragmentów działa
   (`Nagrywam raz, dwa, trzy.`), więc to nie jest gubienie treści — tylko czas trwania/oś oparte
   wyłącznie na torze `system` (spec rdzenia §6).
4. **Potwierdzenie z realnego użycia (dla pozycji C backlogu — offline AEC):** użytkownik **nie mówi**
   na spotkaniach (tylko słucha). W transkrypcie widać pary identycznych wypowiedzi w tej samej
   sekundzie, np. `0:13 Them „let's turn this off."` i `0:13 Me „Let's turn this off."` — tor
   mikrofonu zbiera niemal wyłącznie przeciek z głośników.
5. **Drobiazgi → BACKLOG**: surowy kod `OSStatus` w komunikacie o brakującym pliku; dozwolone dwie
   identyczne nazwy dostawców (komunikat „No API key for <nazwa>" staje się niejednoznaczny);
   „0 min" dla nagrań bez dźwięku systemowego (patrz pkt 3).

## Ograniczenia tej rundy

- Stan `.devdata` po odbiorze: 12 sesji testowych (szum po nagraniach próbnych — kroki 1–2 planu
  zakładały czysty katalog, więc przed kolejną bramką można go wyczyścić). W sesji 11:10 nowszy
  przebieg `…09-15-10Z-cbca` (powstał przez kliknięcie „Transcribe with English" zamiast „Resume
  Transcription") przeniesiono do `~/.hermes/cache/scratch/mn-s17/cbca-hidden`, żeby przywrócić stan
  „Interrupted" dla testu wznowienia; kopia przerwanego przebiegu (`ce4c-backup`) leży obok.
  Żadnych plików nie usunięto.
- Pływający panel (`NSPanel`, `nonactivatingPanel`) **nie jest widoczny** w liście okien systemu ani
  w drzewie AX — wszystko, co o nim wiemy, opiera się na zrzutach użytkownika.
- Pomocniczy model wizji użyty do odczytu ekranu **bywa konfabuluje** opisy (raz opisał nieistniejące
  kontrolki arkusza) — wszystkie wnioski opierają się na drzewie AX, plikach i pomiarach; miejsca
  oparte na wizji są oznaczone.
- Podwójne „Retry Failed Parts" i „nagrywanie bez ważnego presetu" nie zostały odtworzone na żywo
  w tej rundzie (pierwsze jest nieosiągalne bez transkryptu z lukami, drugie — na relację
  użytkownika i kod).
