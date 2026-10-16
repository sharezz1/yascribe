# Spike fazy 1.6 — wykrywanie spotkań (T0)

> 2026-10-16, sprzęt użytkownika (macOS 27, Exchange + Teams). Sondy: `Sources/MeetNotesApp/Probes.swift`
> (`MEETNOTES_PROBE=calendar|audio|login`). **Bez tytułów, adresów e-mail i treści wydarzeń** — tylko flagi,
> liczby, rodzaje pól i bundle ID. Spec: `docs/superpowers/specs/2026-10-16-faza16-kalendarz-design.md` §5.

## 1. Uprawnienia

- Monit o dostęp do kalendarza pokazał się jako **„Pozwolić aplikacji MeetNotes…"** (zrzut `SCR-20261016-rcel`):
  zgoda przypisana do **MeetNotes**, nie do terminala (uruchomienie przez `open -n`, podpis „MeetNotes Dev").
- Klucz `NSCalendarsFullAccessUsageDescription` — nazwa potwierdzona po plistach systemowych (nagłówki SDK
  nie zawierają kluczy plist). API: `requestFullAccessToEvents`, macOS 14.
- Odczyt listy procesów audio: `OSStatus=0`, 37 obiektów. Użytkownik nie zgłosił żadnego monitu systemowego przy
  sondzie audio (jedyny monit w spike: kalendarz). **Wniosek: lista procesów nie wymaga uprawnienia TCC.**
- `login` (`SMAppService`): **niezmierzone** — wymaga ręcznego uruchomienia przez użytkownika (zmienia pozycje
  logowania w systemie).

## 2. Kalendarz (Exchange) — 59 wydarzeń z okna −14…+7 dni

| Cecha | Wynik |
|---|---|
| Link Teams | w **treści** (`notes`) wydarzenia, format `teams.microsoft.com/meet/…`; nie w polu URL; w lokalizacji tylko tekst „Microsoft Teams" (bez adresu). Stary wzorzec `/l/meetup-join` nie złapałby **żadnego** wydarzenia. |
| Wydarzenia z linkiem Teams | 49 z 59 (26 zaakceptowanych, 23 bez odpowiedzi) |
| `webex.com` w treści | 29 z 49 wydarzeń Teams — dopisek o łączeniu z urządzeń wideo, **nie jest wzorcem spotkania** |
| Zoom | 3 (lokalizacja + treść), status użytkownika *tentative* |
| Całodniowe | 7 (urodziny `cal=4`, subskrypcja `cal=3`, Exchange 24 h i 72 h) |
| Bez linku, nie całodniowe | 0 w oknie (wizyta u lekarza/spotkanie stacjonarne: brak próbki) |
| Brak w oknie | odrzucone (`declined`), anulowane (`canceled`), `unavailable` |

**Spotkania bez odpowiedzi** (`myStatus = unknown`, dostępność *tentative*): 23 wydarzenia, wszystkie z linkiem Teams —
codzienne półgodzinne spotkania z ~50 uczestnikami i cykliczne. Filtr wymagający odpowiedzi użytkownika (spec §4.3 pkt 5)
je odcina.

**OOO (Exchange), wpis 1.12.2026:** całodniowe, 72 h, `availability = busy` (**nie** `unavailable`), bez linku,
bez uczestników, `myStatus = none`. EventKit nie oznacza OOO flagą → `availability` nie jest sygnałem OOO; odcinają
je: brak linku + całodniowe + długość. **Niezmierzone:** OOO czasowe (kilkugodzinne) — odpada przez brak linku.

## 3. Audio — procesy trzymające wejście

| Czas | Proces | Zdarzenie |
|---|---|---|
| 19:39:52 | `com.apple.CoreSpeech` | wejście **ON** od startu i przez cały pomiar (system; **lista ignorowanych**) |
| 20:02:30 → 20:02:56 | `com.microsoft.teams2.modulehost` | rozmowa Teams (26 s): ON → OFF |
| 20:04:10 → 20:04:37 | `com.microsoft.teams2.modulehost` | rozmowa z **wyciszeniem** w środku (27 s): jedna ciągła sesja |
| 20:06:08 → 20:06:12 | `com.electron.wispr-flow.helper` | dyktowanie Wispr Flow (4 s) |

Wnioski:
- Mikrofon trzyma **proces pomocniczy** `com.microsoft.teams2.modulehost`, nie `com.microsoft.teams2` →
  wykrywanie po **rodzinie** (prefiks `com.microsoft.teams2`), nie po pojedynczym procesie ani pid.
- **Wyciszenie w Teams nie zwalnia wejścia** (brak OFF/ON w trakcie wyciszenia) → wyciszenie nie jest fałszywym końcem.
- Rozłączenie = czyste OFF.
- Wispr Flow: `com.electron.wispr-flow.helper`; nie należy do listy aplikacji rozmów, więc wykluczony przez białą listę;
  dodatkowo krótki (4 s < `startSeconds`).
- Pomiary: **2 rozmowy** (26 s i 27 s), jedno wyciszenie — próba mała, wartości progów wymagają potwierdzenia na dłuższych
  rozmowach przy odbiorze T13.

## 4. Niezmierzone (użytkownik nie miał jak)

- **Poczekalnia Teams** przed dołączeniem — czy trzyma mikrofon i jak długo (fałszywy start, anty-cel #1). Decyzja przy
  odbiorze T13 (spec §6 pkt 2 dopuszcza odstępstwo).
- **Teams w przeglądarce** — poza zakresem planu (jak w „Poza zakresem").
- **Dyktowanie systemowe** (Fn Fn) — niezmierzone; `com.apple.CoreSpeech` trzyma wejście stale i tak jest ignorowany.
- **Uruchamianie przy logowaniu** (`SMAppService`) i zachowanie aplikacji bez okna — niezmierzone; do T11/T13.
- Wydarzenia: wizyta bez linku, OOO czasowe, odrzucone/anulowane — testy syntetyczne w T2 (statusy to wartości enum EventKit).

## 5. Wartości dla planu (czytają T1–T3)

| Wartość | Ustalenie | Podstawa |
|---|---|---|
| `callApps` | `com.microsoft.teams2` (dopasowanie po prefiksie) | §3, proces pomocniczy `modulehost` |
| `ignoredApps` | `com.apple.CoreSpeech`, `com.electron.wispr-flow` | §3 |
| `linkPatterns` | `teams.microsoft.com`, `teams.live.com`, `meet.google.com`, `zoom.us/j`; **bez** `webex.com` | §2 |
| Pole linku | `notes` (treść), potem `url`, `location` | §2 |
| Reguła OOO | brak linku + całodniowe + długość; `availability` **nie** używana | §2 |
| Odpowiedź użytkownika | `accepted`, `tentative`, `none` (własne) | §2 |
| `startSeconds` | **12 s** (szkic) — rozmowy 26–27 s; poczekalnia niezmierzona | §3, §4 |
| `releaseSeconds` | **20 s** (szkic) — wyciszenie nie zwalnia wejścia, więc margines na ponowne łączenie | §3 |
| `silenceSeconds` | **180 s** (szkic), bez pomiaru | — |
| `snoozeSeconds` | **600 s** (szkic) | — |
