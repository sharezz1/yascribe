# Faza 1 — runbook wykonania

> Dla orkiestratora (Hermes). Użytkownik wkleja Hermesowi jedno polecenie (§0); dalej Hermes sam prowadzi sesje, przydziela agentów i czyta raporty.
> Plan: `2026-09-24-faza1-00-przeglad.md` (zasady §0, ograniczenia §4) + plany 01–05.
> Ten dokument mówi **w jakiej kolejności, jakim modelem i jakim poleceniem** uruchamiać sesje.

## 0. Polecenie główne dla Hermesa (wkleja użytkownik, raz)

```text
Jesteś orkiestratorem wykonania fazy 1 aplikacji MeetNotes.
Repozytorium: /Users/michalprzytulski/meetnotes.

Przeczytaj w całości, w tej kolejności:
1. docs/superpowers/plans/2026-09-25-faza1-runbook.md — Twój plan pracy.
2. docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md — §0 (zasady, modele) i §4 (ograniczenia).

Twoja rola:
- Prowadzisz sesje S0–S18 z runbooka §2, po kolei. Każdą sesję zlecasz agentowi na modelu
  z kolumny „Model" (F = deepseek-v4.1-flash przez OpenCode Go, K = Claude Opus 5.5 przez
  Claude Code, R = GPT 6 Sol przez OpenRouter), poleceniem z runbooka §3 z podstawionymi
  polami.
- Po każdej sesji czytasz raport docs/superpowers/reports/<sesja>.md. Idziesz dalej tylko,
  jeśli ostatnia linia scripts/test.sh zgadza się z kolumną „Testy po sesji" i raport nie
  zgłasza rozbieżności.
- Po sesjach z „Przegląd po: tak" zlecasz przegląd modelowi R poleceniem z runbooka §4.
  Uwagi z przeglądu wracają do tego samego agenta K jako poprawki; potem przegląd jeszcze raz.
  Najwyżej dwie rundy — trzecia runda = zgłoś użytkownikowi.
- Sesje z „Ty? tak" (S5, S9, S13, S14 krok 1, S17) prowadzisz z użytkownikiem: agent wypisuje
  polecenia, użytkownik je wykonuje i odsyła wynik. Nie zmieniasz za niego Ustawień
  systemowych, pęku kluczy ani klucza API.
- Bramki z runbooka §2 i każde „STOP" z planu: zatrzymujesz się i pytasz użytkownika.
  Nie zmieniasz planu, speców ani kolejności sesji sam.
- Po każdej sesji wysyłasz użytkownikowi jedną linię: sesja, wynik testów, co dalej.

Zacznij od sesji S0.
```

## 1. Zanim ruszysz (jednorazowo, użytkownik)

| # | Co | Po co |
|---|---|---|
| P1 | Zatwierdź zadanie 0 (przegląd §6) | bramka G0 — zmiany w specach |
| P2 | ~~Zdecyduj R5, R8, W6~~ — zdecydowane 2026-09-25 (§5) | — |
| P3 | Na dni sesji A10, B5, C5, D3 zarezerwuj czas przy komputerze | nagrywanie, uprawnienia, klucz API |
| P4 | Klucz OpenRoutera pod ręką (dopiero od B5) | `export MEETNOTES_API_KEY=…` w Twoim terminalu |

Praca na gałęzi `faza1`, nie na `master`. Tworzy ją sesja 0.

## 2. Sesje

Legenda kolumny **Model**: `F` = szybki (`deepseek-v4.1-flash`, OpenCode Go), `K` = kodowy (Claude Opus 5.5, Claude Code), `R` = przegląd (GPT 6 Sol, OpenRouter). **Ty** = sesja wymaga użytkownika przy komputerze.

Sesje ✅ z tego samego wiersza wolno łączyć w jedną rozmowę. Zatrzymaj się przy pierwszej rozbieżności z „oczekiwane".

| Sesja | Zadania | Plik | Model | Ty? | Testy po sesji | Przegląd po? |
|---|---|---|---|---|---|---|
| S0 | zadanie 0 (speki) + gałąź `faza1` | 00 | F | zatwierdzenie | — | nie |
| S1 | A1–A3 | 01 | F | — | 11 | nie |
| S2 | A4–A8 | 01 | F | — | 44 | nie |
| S3 | A9 | 01 | K | — | 44 | **tak** |
| S4 | E1 | 05 | K | — | 47 | **tak** |
| S5 | A10 (sondy S1, S2, T1–T9) | 01 | F | **tak** | — | nie |
| S6 | B1–B3 | 02 | F | — | 72 | nie |
| S7 | E2 | 05 | K | — | 77 | **tak** |
| S8 | B4 | 02 | K | — | 77 | nie |
| S9 | B5 (sondy na żywo, G3) | 02 | F | **tak** + klucz | — | nie |
| S10 | C1–C3 | 03 | F | — | 99 | nie |
| S11 | E3, potem E5 | 05 | K | — | 106, po E5: 106+N | **tak** |
| S12 | C4 | 03 | K | — | 106 | **tak** |
| S13 | C5 (transkrypcja na żywo) | 03 | F | **tak** + klucz | — | nie |
| S14 | D1 (krok 1: certyfikat — użytkownik) | 04 | K | **tak** (krok 1) | 106 | nie |
| S15 | D2 | 04 | K | — | 106 | **tak** |
| S16 | E4 | 05 | K | — | 106 | **tak** |
| S17 | D3 (odbiór ręczny) | 04 | F | **tak** | — | nie |
| S18 | przegląd całej gałęzi | wszystkie | R | — | 106 | — |

> Liczby od S6 przesunięte o +7: +6 po poprawkach S3+S4 (decyzja 2026-09-25) i +1 po torze `mic_raw` pod VP (test `mixesMicArrayChannelsWithGain`, sonda S5 2026-09-29; `docs/superpowers/reports/S5-S2-poprawka-aec.md`).

**Bramki — orkiestrator zatrzymuje się i pyta użytkownika:**
- S5: wynik S1 (błąd czy zera przy odmowie) i S2 (dwa strumienie mikrofonu naraz). Przy niepowodzeniu S2 — decyzja użytkownika.
- S9: jeśli `mai-transcribe-2` nie przechodzi sondy z błędem formatu żądania → zmiana na multipart, decyzja orkiestratora.
- S13: pamięć ponad 3 GB → plan awaryjny z C5 krok 6.

## 3. Polecenie startowe sesji (orkiestrator wysyła agentowi)

Orkiestrator podmienia `{SESJA}`, `{ZADANIA}` i `{PLIK}` z tabeli §2.

```text
Jesteś wykonawcą planu MeetNotes. Repozytorium: /Users/michalprzytulski/meetnotes, gałąź faza1
(w sesji S0 utwórz ją: git checkout -b faza1).

1. Przeczytaj docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md — §0 i §4 w całości.
2. Przeczytaj w docs/superpowers/plans/{PLIK} zadania {ZADANIA} w całości, zanim zaczniesz.
3. Wykonuj krok po kroku. Kod przepisuj dosłownie. Po każdym „Uruchom" porównaj wynik z
   „oczekiwane" — przy rozbieżności zatrzymaj się i opisz ją, nie naprawiaj na ślepo.
   Wyjątek: w zadaniach ⚠️ błąd kompilacji napraw minimalnie i opisz.
4. Odhaczaj wykonane kroki w pliku planu (- [ ] → - [x]) i commituj je razem z zadaniem.
5. Testy tylko przez scripts/test.sh. Kod 3 = rm -rf .build i powtórz. Kod 4 = wynik nieważny, STOP.
6. Kroki wymagające użytkownika: wypisz mu polecenia i czekaj. Nie zmieniaj Ustawień systemowych,
   pęku kluczy ani klucza API.
7. Na koniec zapisz raport do docs/superpowers/reports/{SESJA}.md: zadania, hashe commitów,
   ostatnia linia scripts/test.sh, odchylenia od planu z powodem, pytania do orkiestratora.
   Dodaj raport do ostatniego commita. Zakończ odpowiedź ostatnią linią scripts/test.sh.

Sesja: {SESJA}. Zadania: {ZADANIA}.
```

## 4. Polecenie przeglądu (po sesjach z „tak" w kolumnie „Przegląd po?")

Inny model niż wykonawca. Podmień `{SESJA}` i `{ZAKRES}`, np. `git diff <hash przed>..HEAD`.

```text
Jesteś recenzentem. Repozytorium /Users/michalprzytulski/meetnotes, gałąź faza1.
Przeczytaj docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md §4, raport
docs/superpowers/reports/{SESJA}.md i zmiany {ZAKRES}.

Szukaj błędów, nie oceniaj. Sprawdź:
1. Czy kod robi to, co mówią komentarze i plan. Poprawki „minimalne" nie mogą zmieniać zachowania.
2. Czy testy rzeczywiście sprawdzają wymaganie. Czy mutacja z planu była wykonana i dała czerwień.
3. Wycieki zasobów, wyścigi, połknięte błędy, zapis poza katalogiem sesji.

Uruchom scripts/test.sh i podaj ostatnią linię. Wynik zapisz do
docs/superpowers/reports/{SESJA}-przeglad.md: każdy punkt = plik, miejsce, problem, propozycja.
Niczego nie naprawiaj.
```

## 5. Decyzje R5, R8, W6 — opcje

Plan działa przy każdej z opcji. Domyślne (pierwsze) nie wymagają żadnej zmiany.

**Decyzja użytkownika z 2026-09-25: R5 a, R8 a, W6 a** — bez zmian w planie.

| # | Sprawa | Opcje | Rekomendacja |
|---|---|---|---|
| **R5** | Aplikacja nagrywa zawsze trzema źródłami: system, `mic_raw`, `mic_aec` — na sztywno w `RecordingController` | **a)** zostawić. Jeśli sonda S2 wykaże, że dwa strumienie mikrofonu nie działają naraz, plan i tak staje, a zmiana to jedna linia. **b)** przełącznik w Settings „Echo cancellation copy (mic_aec)" — wyłączenie nagrywa tylko surowy mikrofon | **a)** — decyzja po wyniku S2, nie przed |
| **R8** | Preset ma dwa osobne prompty (korekta, podsumowanie), ale nic nie wymusza ich treści | **a)** zostawić — w fazie 1 korekta i podsumowanie nie są wykonywane, tylko konfigurowane. **b)** walidacja: gdy rola jest ustawiona, prompt niepusty i różny od drugiego. **c)** domyślne szablony promptów przy tworzeniu presetu | **a)** teraz, **c)** w fazie 3, razem z notatkami |
| **W6** | Wynik sondy w cache jest przypisany do dostawcy, modelu, roli i języka — bez adresu dostawcy | **a)** zostawić — adresu dostawcy nie da się edytować, tylko usunąć i dodać nowego (nowe ID = czysty cache). **b)** adres w kluczu cache. **c)** ważność wyniku np. 30 dni, potem „Not tested" | **a)** teraz, **b)** gdy dojdzie edycja dostawcy |

## 6. Stan wiedzy o kodzie przed startem

- ✅ A1–A8, B1–B3, C1–C3: kod ze spike'a, skompilowany i przetestowany.
- 🔧 A8 (źródła sprzętowe), D2 (aplikacja): skompilowane, nigdy nieuruchomione.
- ✅ E1–E4 i poprawki po recenzjach w A4, C2, C3, D2: przebieg kontrolny 2026-09-25 (Sonnet, kopia spike'a) — wszystko weszło dosłownie, bez poprawek kompilacji; `scripts/test.sh` 99/99; obie mutacje dały czerwień; obie aplikacje budują się.
- 🔧 CLI (A9, B4, C4): pełna wersja skompilowana i sprawdzona dymnie; wersje pośrednie po A9 i B4 nie były kompilowane osobno.
- ⚠️ D1 (`Info.plist`, `bundle.sh`, `run.sh`): nigdy nieuruchomione.
- Nigdy nieuruchomione na sprzęcie: źródła audio (A8), aplikacja (D2, E4). To sprawdzają sesje S5 i S17.
