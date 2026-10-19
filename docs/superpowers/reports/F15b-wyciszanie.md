# Faza 1.5b — wyciszanie torów w pigułce

Zadanie: `docs/design/macos.md` §11.5, akapit „Wyciszanie torów w pigułce” (decyzja użytkownika 2026-10-16),
oraz decyzja (b) z raportu F15-T13 część B (zdarzenie przy pierwszych niezerowych próbkach po `allZeros60s`).
Gałąź `claude/adoring-pasteur-77900b` z `faza15` @ `49c4980`. Plan i decyzje 1–4 zaakceptowane przez użytkownika 2026-10-19.

Commity: `aef4629` (T1 rdzeń), `efd1971` (T2 notatki), `1f75c3e` (T3 aplikacja), raport w commicie domykającym.
Testy: `scripts/test.sh` → **344/344** (było 334; +10: 5 rejestrator, 3 podsumowanie, 2 TrackProblem/MuteNote).

Merge Danger: NIEODWRACALNE — zmienia format dziennika sesji na dysku: trzy nowe rodzaje zdarzeń (`track.muted`,
`track.unmuted`, `track.audible`). Build sprzed 1.5b nie przeczyta dziennika, który je zawiera (`corruptLine`), a
`track.audible` powstaje w każdej sesji, w której dźwięk systemowy zaczął się po minucie ciszy. Nowy build czyta stare
dzienniki bez zmian (test na prawdziwej sesji z `.devdata`). Dlatego odbiór na żywo idzie na osobnym `.devdata` w
worktree (skopiowane tylko `providers/presets/settings/probe-cache.json`, bez sesji), a nie na danych z `faza15`.

## Co zrobione

**Rdzeń (`MeetNotesRecording`, `MeetNotesSessionFormat`)**
- `SessionRecorder.setMuted(_:_:) -> Bool`:
  - wyciszona porcja jest zapisywana jako zera tej samej długości i z tym samym czasem hosta: nie ma przerwy,
    `track.gap` ani fałszywego `stalled30s`, a tory zostają wyrównane;
  - odmowa (`false`), gdy po wyciszeniu nie zostałby żaden uruchomiony, niezakończony, niewyciszony tor. To obejmuje
    także jedyny tor, gdy drugi nie dostał uprawnienia. Odciszenie zawsze się udaje;
  - wyciszenie obowiązuje także wtedy, gdy nie udało się zapisać zdarzenia w dzienniku (prywatność).
- Zdarzenia dziennika: `track.muted`, `track.unmuted` (z `frameIndex` = ramka, od której tor milczy / znów nagrywa)
  i `track.audible` (pierwsza niezerowa próbka po `allZerosNs`).
- `SessionSummary.Track` dostaje dwa opcjonalne pola: `mutes: [Mute]?` i `audibleFrame: Int?`.
  - Wyciszenie trwające przy Stop kończy się na ostatniej ramce toru.
  - Po awarii zostaje otwarte (`endFrame == nil`, w transkrypcie „muted from 0:10 to the end”).
- Wykrywacz zer i `track.audible` patrzą na surowy dźwięk, więc wyciszony, ale działający tor systemowy nie dostaje
  `allZeros`. Poziom (`currentLevels`) też jest surowy (decyzja 3). Próg ciszy (`lastLoudAt`) liczy zapisany dźwięk,
  więc wyciszony tor jest cichy (decyzja 4).

**Notatki (`MeetNotesNotes`)**
- `TrackProblem`: przy `track.audible` od razu neutralna linia „System audio was silent for the first minute;
  recording continued.”, a w szczegółach „Sound started at M:SS”, bez czekania na transkrypt. Sesje bez tego zdarzenia
  (stare) rozstrzyga dalej transkrypt, jak dotąd.
- `MuteNote.of(summary:)`: „Microphone muted 0:05–0:12” na osi sesji (`SessionClock`, ta sama co `Utterance.start`).
  `Transcript` i `MeetNotesTranscription` zostały bez zmian. Bramka energetyczna pomija cyfrową ciszę sama z siebie.

**Aplikacja**
- Rozwinięta pigułka:
  - ikona toru jest przełącznikiem (`mic`/`mic.slash`, `speaker.wave.2`/`speaker.slash`), z `.help` i etykietą
    VoiceOver „Mute microphone” / „Unmute system audio”;
  - wyciszony tor ma szary pasek (`mnText3`, rzeczywisty poziom) i słowo „Muted” zamiast ✓.
- Ostrzeżenie „Nothing is being recorded” zastępuje linię presetu na 4 s (decyzja 1). Przychodzi z odmowy rdzenia, nie
  z osobnego sprawdzenia w interfejsie. Drugi przełącznik zostaje aktywny.
- Zwinięta pigułka: `mic.slash` obok licznika, w miejscu zarezerwowanym na stałe (decyzja 2). Szerokość jest stała,
  więc `fit()` się nie zmienia. Słupki poziomu pomijają wyciszony tor (pokazują to, co się nagrywa).
- Każde nagranie startuje bez wyciszenia. Stan zerują `start` i `finish`.
- Transcript: linia wyciszenia między wypowiedziami w kolejności czasu (ikona i tekst w `text2`), także w Copy jako
  „[0:00:17] Microphone muted 0:17–0:19”.
- Komentarz `expandedBody` mówi już „Stop i wyciszanie”. **Spec decyzja 4 („rozwinięcie tylko do odczytu”) zmieniona**
  zgodnie z §11.5.

## Mutacje (każda: `git add`, mutacja, `scripts/test.sh`, `git checkout`)

| # | Mutacja | Padający test |
|---|---|---|
| M1 | wyciszona porcja zapisywana bez zmian | `mutedRangeIsDigitalSilenceAndTracksStayAligned`, `mutedSystemTrackIsNotMistakenForMissingPermission` |
| M2 | brak zakazu wyciszenia obu | `bothTracksCannotBeMutedAtOnce` |
| M3 | brak zapisu `track.muted/unmuted` | `bothTracksCannotBeMutedAtOnce`, `mutedRangeIsDigitalSilenceAndTracksStayAligned` |
| M4 | wyciszenie przy Stop niezamknięte | `bothTracksCannotBeMutedAtOnce`, `mutePeriodsAreCollectedAndOneOpenAtStopEndsWithTheTrack` |
| M5 | `track.audible` nieuzbrojone po `allZeros` | `soundAfterAllZerosIsJournaledAsAudible` |
| M6 | wyciszony tor podtrzymuje próg ciszy | `mutedTrackIsSilentForTheSilenceConditionButKeepsItsRealLevel` |
| M7 | wykrywacz zer na zapisanym dźwięku | `mutedSystemTrackIsNotMistakenForMissingPermission` |
| M8 | `TrackProblem` ignoruje `audibleFrame` | `journaledSoundAfterSilenceIsInformationWithoutATranscript` |
| M9 | koniec okresu = jego początek | `mutePeriodsBecomeTranscriptLinesOnTheSessionAxis` |

Pierwsze podejścia do M3 i M9 się nie skompilowały (zła składnia mutacji), więc nie miały znaczenia. Powtórzone
z kompilującą mutacją, wyniki w tabeli. Test „stare dzienniki” (`journalAndSummaryFromBeforeMutingLoadUnchanged`)
to strażnik regresji, nie bramka, więc nie ma mutacji. Wczytuje prawdziwy dziennik i `session.json` z sesji
`.devdata/sessions/2026-10-13T10-27-14Z-6d17` i sprawdza, że przebudowa daje identyczne podsumowanie.

## Migawki (`scripts/snapshot.sh`, oba motywy)

`pill-collapsed-muted`, `pill-expanded-muted`, `pill-expanded-warning` (dźwięk systemowy wyciszony + ostrzeżenie),
`meeting-transcript-muted` (linia „Microphone muted 0:17–0:19” między 0:12 a 0:20). Obejrzane. Zwinięta bez wyciszenia
ma po prawej od licznika puste ~22 pt (zarezerwowane miejsce, decyzja 2).

## Uwagi i rzeczy do Twojej oceny przy odbiorze

1. Kolumna stanu w wierszu toru ma teraz 44 pt (na „Muted”), także bez wyciszenia, więc paski w rozwiniętej pigułce są
   o ~30 pt krótsze niż przed zmianą. Dzięki temu pasek nie skacze przy przełączaniu.
2. Wyciszenie liczy się od następnej porcji audio (dokładność ~10–20 ms). Okres w dzienniku to dokładne ramki, które
   zapisały ciszę.
3. **Pytanie do użytkownika.** Decyzja 4 dotyczy też pytania „Meeting ended?” z fazy 1.6 (`silentSeconds` używa
   tego samego `lastLoudAt`; próg `MeetingTuning.silenceSeconds` = 180 s). Wyciszony mikrofon przy milczącej drugiej
   stronie wywoła więc to pytanie już po 3 minutach, a autostop po 10 min. Pytanie tylko pyta (Stop / Continue).
4. Pole przełącznika to ikona 14×20 pt. Jeśli w praktyce trudno w nią trafić, łatwo powiększyć.
5. Poza zakresem (zgodnie z planem): skrót klawiszowy do wyciszania, zapamiętywanie wyciszenia między nagraniami.

## Odbiór na żywo (wymaga użytkownika)

W worktree, na osobnym `.devdata` (patrz Merge Danger), przy zamkniętej innej instancji MeetNotes:

```bash
cd /Users/michalprzytulski/meetnotes/.claude/worktrees/adoring-pasteur-77900b && scripts/run.sh
```

| # | Punkt | Wynik | Uwaga |
|---|---|---|---|
| 1 | Nagranie startuje bez wyciszenia; rozwinięta pigułka: klik w ikonę mikrofonu → `mic.slash`, szary pasek reaguje na głos, „Muted” | | |
| 2 | Zwinięta pigułka przy wyciszonym mikrofonie: `mic.slash` obok licznika, rozmiar okna bez zmian | | |
| 3 | Próba wyciszenia drugiego toru → „Nothing is being recorded” na ~4 s, nic się nie wycisza | | |
| 4 | Wyciszenie dźwięku systemowego (`speaker.slash`) i odciszenie | | |
| 5 | Po Stop i transkrypcji: w Transcript linia „Microphone muted M:SS–M:SS” we właściwym miejscu; Copy ją zawiera | | |
| 6 | Wypowiedzi z czasu wyciszenia nie ma w transkrypcie; czasy wypowiedzi po odciszeniu zgadzają się z odsłuchem | | |
| 7 | Następne nagranie znów startuje bez wyciszenia | | |
| 8 | (opcjonalnie) Film/dźwięk systemowy dopiero po ≥ 60 s ciszy → w widoku od razu neutralne „silent for the first minute”, bez ⚠ na liście, jeszcze przed transkryptem | | |
