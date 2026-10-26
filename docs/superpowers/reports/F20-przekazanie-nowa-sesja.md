# Faza 2.0 „Lokalne modele" — przekazanie do nowej sesji (2026-10-20)

> Plik dla sesji, która wznawia pracę. Stan kodu i testów jest w `CLAUDE.md` („Stan"); tu: co zostało zrobione, czego nie, gdzie są dowody, jak wznowić.

## 1. Stan w jednym akapicie

Faza 2.0 jest **zaimplementowana i zielona na gałęzi `faza20`** (HEAD `b73d858` + commit dokumentów z tego przekazania; `scripts/test.sh` **561/561**, exit 0, sprawdzone osobnym przebiegiem
po ostatnim scaleniu). **Nie jest scalona do `master` i nie ma tagu** — to decyzja użytkownika. Żaden agent nie pracuje w tle. 2.0a = lokalny ASR Parakeet TDT v3 (FluidAudio, moduł
`MeetNotesLocalASR`, nowy `ProviderKind.fluidAudio`). 2.0b = Ollama / llama.cpp / oMLX jako lokalni dostawcy tekstu (limity czatu, `finish_reason: "length"` = błąd, `reasoning_effort: "none"`,
budżet kontekstu „Context window", numeracja partii korekty 1..N, map-reduce notatki z anulowaniem i postępem, jawny błąd zamiast cichego obcięcia wejścia). Wbudowany model tekstowy to 2.1+.

## 2. Gdzie są dowody (czytać w tej kolejności)

| Co | Plik |
|---|---|
| Spec (z §11, §13, §14 — decyzje Opusa i korekty) | `docs/superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md` |
| Plan zadań T0–T14 | `docs/superpowers/plans/2026-10-20-faza20-lokalne-modele.md` |
| Dziennik decyzji Opusa + lista „Do potwierdzenia rano" (1–14) | `docs/superpowers/reports/F20-decyzje-opusa.md` |
| Recenzje speca i planu | `docs/superpowers/reports/F20-recenzja-design.md`, `F20-recenzja-planu.md` |
| Spiki: S0 FluidAudio, S1 jakość ASR, S2 serwery tekstowe | `docs/superpowers/spikes/2026-10-20-f20-s0-…`, `…-s1-…`, `…-s2-…` |
| Odbiór 2.0a, odbiór 2.0b, przegląd całości | `docs/superpowers/reports/F20-2.0a-odbior.md`, `F20-2.0b-odbior.md`, `F20-przeglad-calosci.md` |
| Odłożone rzeczy | `docs/superpowers/BACKLOG.md` (sekcja „Z fazy 2.0"), `ROADMAP.md` |

## 3. Co zostało dla użytkownika (agenci nie mogą)

1. **Scalenie `faza20` → `master`** (wnosi też markę Yascribe z `faza15`). Bez tagu ani scalenia nic nie jest zrobione „po cichu".
2. **Klik „Download (483 MB)"** na karcie modelu w Settings (drugi egzemplarz modelu w `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3`; stary `-coreml` zostaje nietknięty;
   kopia testowa jest w `.devdata/model-store`). Pomiar „Preparing model…" (ok. 20–60 s) i cache ANE w `.app`.
3. **Powtórzenie T8 z wyłączonym Wi-Fi** (agent nie mógł zmienić ustawień sieci; dowód zastępczy: 0 gniazd, piaskownica bez sieci, identyczny wynik).
4. **Nagranie na żywo**: kryterium 3.1 (milczący mikrofon przy głośnikach) i para PL+EN (pomiar „T11" z fazy 1.5); weryfikacja przesunięcia mikrofonu (S1: bez właściwego offsetu filtr przesłuchu zawodzi).
5. **oMLX**: model mieszczący się w 16 GB i własny klucz (wpisujesz sam w aplikacji); S2 nie zmierzył oMLX (ochrona pamięci 507 na jedynym modelu MLX na dysku). Uwaga: agent S2 raz wypisał
   `~/.omlx/settings.json` do swojego logu, więc klucz i sekret oMLX były w danych sesji — rozważ rotację klucza.
6. **Baseline API** (ta sama notatka i korekta przez OpenRouter) — wymaga Twojego klucza i kosztu.
7. **Kontekst Ollamy**: przy domyślnych 4096 tokenów notatka z 60 min nie powstaje (jawny błąd); realnie `OLLAMA_CONTEXT_LENGTH` ≥ 16384 (end-to-end 60 min przy 16384 nie zmierzone).
8. Pozycje 1–14 z „Do potwierdzenia rano" w `F20-decyzje-opusa.md` (m.in. lokalna korekta: `bonsai-2` zmienił datę, a bramka `accepts` ją przepuściła; reguła ThinkingStripper — niedomknięty `<think>`
   tylko na początku odpowiedzi — ustalona przez orkiestratora, do potwierdzenia).

## 4. Wiedza operacyjna z tej sesji (przyda się przy kolejnych agentach/worktree)

- **Worktree agentów startują z `master`, nie z bieżącej gałęzi.** Każdy brief zaczynał się od `git merge --ff-only faza20` albo `git reset --hard faza20`. Scalanie gałęzi agentów do `faza20` robił orkiestrator
  (użytkownik zgodził się na to w tej fazie); po każdym scaleniu pełny `scripts/test.sh` w głównym checkout.
- **Dysk**: każdy worktree z `.build` to ok. 1,5 GB; 14 worktree zapełniło dysk do 100% (krok `check-bundle` w `test.sh` kończy się wtedy kodem 5, `codesign` pada). Po zakończeniu agenta kasować jego `.build` i `.design`.
  Katalogi `.claude/worktrees/agent-*` to wyłącznie artefakty tej sesji (zmergowane gałęzie `worktree-agent-*`); starsze worktree (`adoring-pasteur-…`, `faza16`, …) są użytkownika — nie ruszać.
- **SwiftPM**: zawsze `--disable-keychain` (skrypty już go przekazują); pierwszy `resolve` bez niego wisi na odczycie pęku kluczy. `scripts/test.sh` liczy też cel z jednym testem (poprawione regexem `tests?`).
- **Mutacje nie mogą dotykać sieci**: mutacja podmieniająca loader FluidAudio na wersję sieciową pobrała 469 MB. Testy chroniące (`LocalASRNetworkGuardTests`) zakazują `AsrModels.load`/`downloadAndLoad`,
  `ModelHub`, `HFClient`… poza `ModelStore`; w teście silnika `ModelHub.offlineMode = true`.
- **Limit użycia sesji** (429) zatrzymuje agentów w połowie: wznawiać `SendMessage` do tego samego agenta (praca jest zachowana).
- Kod modelu testowego: `.devdata/model-store/parakeet-tdt-0.6b-v3` (23 pliki, 483 257 242 B, gitignored). Korpus S1: `.devdata/s1-corpus/` (gitignored, prywatne nagrania służbowe — nic z nich nie wchodzi do repo ani raportów).

## 5. Aplikacja na pulpicie

Zbudowana wersja **release** z `faza20`: `~/Applications/MeetNotes.app` (podpis „MeetNotes Dev", ten sam co w `scripts/bundle.sh`, więc zgody TCC przetrwają przebudowę). Skrót na pulpicie to mały launcher
(`~/Desktop/MeetNotes.app`), który uruchamia ją z `MEETNOTES_DATA_DIR=/Users/michalprzytulski/meetnotes/.devdata` — dokładnie tak jak `scripts/run.sh` (Twoje sesje, presety i nagrania leżą w `.devdata`, a zwykłe
dwukliknięcie samej aplikacji użyłoby pustego `~/Library/Application Support`). Odświeżenie po zmianach w kodzie:

```bash
CONFIG=release MEETNOTES_APP="$HOME/Applications/MeetNotes.app" scripts/bundle.sh
```

Uwaga: to build z niescalonej gałęzi na Twoich prawdziwych danych w `.devdata`. Nowe pola w plikach są wyłącznie opcjonalne (E6), więc wrócenie do buildu z `master` jest bezpieczne; mimo to zrób kopię `.devdata`
przed pierwszym uruchomieniem, jeśli zależy Ci na nagraniach.
