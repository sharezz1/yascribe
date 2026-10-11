# Przegląd S7 — zadanie E2 (dostawcy)

**Zakres:** `git diff 63769e0..bda1fec` (E2: `Probe.swift`, `Preset.swift`, `OpenAICompatibleClient.swift`, 5 nowych testów, odhaczone kroki planu), raport `S7.md`, plan 00 §4, plan 05 §E2.
**Testy:** `scripts/test.sh` → ostatnia linia: `test.sh: 77/77 testów uruchomionych i zaliczonych.` (kod 0).
**Uwaga organizacyjna:** w trakcie przeglądu HEAD przesunął się na `6d3af1d` („Plan E4: odznaka sondy czyta wynik dla jezyka presetu") — sam dokument, poza zakresem diffu; dotyczy pytania 1 (patrz niżej).

**Zgodność kod ↔ plan:** wszystkie bloki „zamień A na B" z E2 (kroki 3–6) weszły dosłownie, żadnych poprawek kompilacji poza planem nie ma — raportowi „brak odchyleń" potwierdzony. Kroki E2 1–8 odhaczone w planie, commit zgodny z krokiem 8 (plan dodany do `git add`, zgłoszone jako odchylenie).

## Uwagi

### 1. Test nie ćwiczy sanitizacji treści błędu (martwy)
- **Plik:** `Tests/MeetNotesProvidersTests/ClientTests.swift`
- **Miejsce:** `errorBodyEchoingTheKeyIsSanitized`, linie 55–64 (literal z planu 05, E2 krok 1)
- **Problem:** stub zwraca treść `Bearer test-f...123`, a klucz w teście to `test-fake-SECRET123`. Zapis `test-f...123` nie jest tym kluczem — `replacingOccurrences(of: key, ...)` z kroku 5 nie ma czego zamieniać, a asercja `!"\(error)".contains("SECRET123")` przechodzi, bo treść nigdy nie zawierała `SECRET123`. Test zalicza się także po cofnięciu kroku 5 (mutacja „bez sanitizacji" = zielone). Wymaganie „treść błędu HTTP bez klucza" nie jest sprawdzane.
- **Propozycja:** stub niech zwróci klucz dosłownie: `fail(400, "{\"error\":\"bad header Authorization: Bearer test-fake-SECRET123\"}")`, a asercja niech sprawdza brak `"test-fake-SECRET123"` i/lub obecność maski `"••••"`. (Winny jest literal planu — wykonawca przepisał zgodnie z instrukcją; poprawić plan i test.)

### 2. `r.language` z `probe()` nie jest pokryte żadnym testem
- **Plik:** `Tests/MeetNotesProvidersTests/ProbeTests.swift`, `PresetTests.swift`
- **Miejsce:** `probeResultsForDifferentLanguagesDoNotOverwriteEachOther` (PresetTests:60–68) buduje `ProbeResult` ręcznie z `language:`; `transcriptionModelTypedByHandPassesTheProbe` (ProbeTests:9–20) nie sprawdza `r.language`
- **Problem:** mutacja „usuń `r.language = language`" (`Sources/MeetNotesProviders/Probe.swift:62`) zostawia 77/77 zielone — test cache'a sprawdza sam klucz `ProbeCache`, a wiązanie „sonda → wynik z językiem" (krok 3 planu) nie jest sprawdzone nigdzie. Po takiej mutacji wynik sondy ASR trafiałby pod klucz „bez języka" (cichy powrót do błędu sprzed E2) i nic by nie wykryło.
- **Propozycja:** w `transcriptionModelTypedByHandPassesTheProbe` dodać `#expect(r.language == .polish)`; dołożyć asercję `#expect(r.language == nil)` dla `probe(..., language: nil)` (rola nie-ASR / brak języka).

### 3. Plan E2 nie ma kroku z mutacją
- **Plik:** `docs/superpowers/plans/2026-09-24-faza1-05-poprawki-po-recenzjach.md`
- **Miejsce:** zadanie E2 (kroki 1–8; E1 ma mutację w kroku 9, E3 w kroku 8)
- **Problem:** bez mutacji czerwień z kroku 2 (błąd kompilacji `extra argument 'language'`) nie dowodzi działania testów — i faktycznie puściła uwagi 1 i 2. Raport uczciwie nie zgłasza mutacji (nie było jej w planie), ale to luka planu, nie raportu.
- **Propozycja:** dodać krok mutacji E2: (a) cofnij krok 5 → `errorBodyEchoingTheKeyIsSanitized` musi paść (po uwadze 1); (b) usuń `r.language = language` → test z uwagi 2 musi paść; (c) `key(...)` bez języka → `probeResultsForDifferentLanguagesDoNotOverwriteEachOther` musi paść.

### 4. Komentarz `ProbeResult.language` i zachowanie przy `language: nil` się rozjeżdżają
- **Plik:** `Sources/MeetNotesProviders/Probe.swift`
- **Miejsce:** linie 29–30 (komentarz), 61–62 (`let lang = language ?? .english`; `r.language = language`), 72 (`classifyLanguage(model:language: lang)`)
- **Problem:** przy `probe(..., language: nil)` klasyfikacja idzie dla `.english`, a pole `language` i klucz cache mówią „brak języka" — komentarz „Język, dla którego sonda ASR klasyfikowała obsługę języka" nie odpowiada temu, co zaszło. Dodatkowo taka sonda nie jest „bez języka" nawet na poziomie HTTP: `langParam = clip.language == lang ? lang : nil` daje `.english`, więc żądanie leci z `language: "en"`. Wpis pod kluczem „-" niesie więc wynik angielski i jest tak czytany (np. przez `ProbeBadges`, gdy draft nie ma jeszcze języka).
- **Propozycja:** przy `language == nil` nie ustawiać `languageHandling` (zostawić `nil` — klasa obsługi jest per język) albo zapisać `r.language = lang` i zaktualizować komentarz; wariant drugi zmienia kluczowanie, więc wymaga decyzji razem z pytaniem 2. Zachowanie bieżące jest literalne wg planu — do decyzji autora planu, nie cicha zmiana.

### 5. Martwe wpisy cache'a sprzed E2 zostają w `probe-cache.json`
- **Plik:** `Sources/MeetNotesProviders/Preset.swift`
- **Miejsce:** `ProbeCache` (linie 67–81)
- **Problem:** zmiana klucza z 3 na 4 składniki unieważnia wszystkie wpisy zapisane przed E2 — zostają w słowniku i w pliku na zawsze, nigdy nieodczytane (brak migracji ani sprzątania). Nie psuje działania (najwyżej ponowna sonda), ale plik rośnie bez potrzeby, a przy ręcznym odczycie myli.
- **Propozycja:** przy `load` migracja starych kluczy (dopisanie `|-`) albo wyrzucenie wpisów bez 4. składnika przy pierwszym zapisie; kiedyś też rozważyć TTL wg `checkedAt` (na razie nieużywane).

## Pytania z raportu S7

1. **Odznaka sondy ASR w D2 a cache z językiem** — tak, to realny dysonans: po E2 wpis ASR powstaje pod kluczem z językiem (`probe(..., language:)` → `r.language`), a `ProbeBadges` w planie 04 (~914) czyta `result(provider:model:role:)` z `language: nil`, więc po teście odznaka ASR byłaby pusta; dla correction/summary/embedding problemu nie ma, bo `r.language` jest ustawiane wyłącznie w gałęzi `.asr`. Zgłoszone rozwiązanie (commit `6d3af1d`, E4 krok 5b: `result(..., language: language)`) jest poprawne i symetryczne — `RoleEditor` dostaje `language:` tylko dla roli ASR (plan 04: 868–870), a dla pozostałych ról `nil`, dokładnie jak przy zapisie. Dwie rezydualne uwagi: (a) jeśli użytkownik przyciśnie Test przed wybraniem języka draftu, wynik ląduje pod „-", a po wyborze języka odznaka zniknie („Not tested") — spójne z per-językowym cache'em, ale warto wiedzieć; (b) to samo tyczy się blokady czatu w E4 krok 2(d) — czyta z `p.language`, więc sonda zrobiona przed wyborem języka jej nie zasili (patrz uwaga 4).

2. **Sonda ASR bez języka pod kluczem „bez języka"** — samo kluczowanie jest konsekwentne (zapis i odczyt z `language: nil` trafiają na ten sam klucz), ale dwie rzeczy z raportu wymagają korekty. Po pierwsze: „w aplikacji to raczej nie wystąpi" — wystąpi; `Preset.validate()` działa dopiero przy zapisie (`PresetsFile.upsert`), a przycisk Test w `RoleEditor` jest włączony samym `!a.model.isEmpty`, więc nowy draft (`language: nil` na starcie, plan 04: 836) przechodzi sondę ASR bez języka normalnie w UI. Po drugie: to nie jest wynik „bez języka", tylko wynik dla angielskiego (`lang = language ?? .english`, klasyfikacja `classifyLanguage(..., .english)`, żądanie HTTP z `language: "en"`) — pod kluczem „-" siedzi więc klasyfikacja angielska, którą odznaka pokaże dla draftu w dowolnym języku. „Jak ma zostać": zostawić kluczowanie (wariant B z uwagi 4), ale przy `language == nil` nie przypisywać `languageHandling` albo przypisać `r.language = .english` — inaczej komentarz pola i semantyka klucza mijają się z prawdą.

## Wynik testów

`scripts/test.sh` — ostatnia linia: `test.sh: 77/77 testów uruchomionych i zaliczonych.` (zgodne z krokiem 7 planu i raportem).
