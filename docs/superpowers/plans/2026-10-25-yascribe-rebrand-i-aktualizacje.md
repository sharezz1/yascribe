# Yascribe: rename i aktualizacje przez Sparkle — plan implementacji

> **Dla wykonawców (Claude Code):** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (rekomendowane) albo `superpowers:executing-plans`. Najpierw „Instrukcja wykonania" poniżej. Kroki używają pól `- [ ]`. **Nie zaczynaj, dopóki użytkownik nie zaakceptował planu.**

**Cel:** `Yascribe.app` zainstalowana w `/Applications`, aktualizowana przyciskiem (Sparkle 2) z wydań w GitHub Releases nowego, publicznego repo `sharezz1/yascribe`; pełny rename z migracją danych i kluczy.

**Architektura:** (1) spike S0 rozstrzyga Sparkle przy samych CLT i dostęp do starej pozycji pęku po zmianie bundle ID; (2) historia git przepisana (bez adresu służbowego) do nowego repo; (3) mechaniczny rename + jednorazowa migracja przy pierwszym starcie (`DataDirectoryMigration`, `KeyMigration`); (4) nowy moduł `YascribeUpdates` (jedyny importujący Sparkle) z `UpdateController` i `RestartGate`, osadzanie frameworka w `bundle.sh`; (5) `scripts/release.sh`; (6) audyt, upublicznienie, `v0.1.0`, instalacja, próba `v0.1.1`.

**Stos:** Swift 6.4 (tryb 6), tylko Command Line Tools, `swift-testing`, SwiftUI + AppKit, Sparkle 2 (`binaryTarget`, pin dokładny), `gh`, `git filter-repo`, `codesign`, `xmllint`.

**Spec:** `docs/superpowers/specs/2026-10-25-yascribe-rebrand-i-aktualizacje-design.md` (commit `d8e602c`; sekcje „Moje decyzje po przeglądzie projektu" i „Poprawki po recenzji Codexa" są wiążące). Plan argumentuje ze speca; wykonawca czyta oba.

## Wspólne ograniczenia

Obowiązują w każdym zadaniu (dosłownie ze speca i `CLAUDE.md`):

- **Toolchain:** Swift 6.4, tylko Command Line Tools, bez Xcode; `swift-testing`. **Testy wyłącznie `scripts/test.sh`** (kod 3 = usterka pluginu: `rm -rf .build` i raz powtórz; 4 = rozjazd liczby = STOP). Każdy `@Test` zaczyna linię (test.sh liczy `grep -E '^[[:space:]]*@Test'`). Katalogi tymczasowe w testach: `mn-<UUID>` (po rename prefiks zostaje `mn-`, wzorzec sprzątający w `test.sh` się nie zmienia).
- Po rename `scripts/test.sh` ma dać **744/744**; liczba testów po każdym następnym zadaniu = poprzednia + liczba nowych `@Test` tego zadania (inna różnica = STOP).
- SwiftPM pobiera `binaryTarget` tylko z `--disable-keychain` (skrypty już to robią); po zmianie `Package.swift` lub `rm -rf .build`: `swift package --disable-keychain resolve`.
- SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview` (stan lokalny: `ObservableObject` + `@StateObject`; `@Observable` działa). Nowe pola w zapisywanych typach **tylko opcjonalne**.
- **Nigdy `git add -A` ani `git add .`** — jawne ścieżki. Hook pre-commit (`core.hooksPath scripts/hooks`) sprawdza hashe w backtickach w `docs/**/*.md`. Mutacja każdej bramki: wprowadź → test ma paść → `git checkout <plik>`.
- **Klucze API wpisuje wyłącznie użytkownik**; klucz prywatny EdDSA zostaje w jego pęku login; token GitHub, klucze i klucz EdDSA nigdy do repo, logu ani czatu. Literały testowe `test-fake-…`. Nie zmieniamy Ustawień systemowych, TCC ani pęku użytkownika — to robi użytkownik (kroki oznaczone **[UŻYTKOWNIK]**).
- **Interfejs po angielsku, dokumenty w repo po polsku.** Poza zakresem: notaryzacja/Developer ID, delta, kanały beta, wymuszone i automatyczne instalacje, przepisywanie historycznych dokumentów (jedyny wyjątek: podmiana cytowanych hashy w T1).
- **Anty-cele (porażka nawet przy „działa"):** aktualizacja przerywa nagranie; utrata danych lub kluczy przy pierwszym starcie; klucz EdDSA/token w repo, logu lub czacie; wydanie bez podpisu EdDSA, które aplikacja przyjmie.
- Wydanie i upublicznienie to działania publiczne: agent wykonuje je dopiero na jawne „tak"/„wydaj" użytkownika w czacie (punkty **STOP-U**).
- Certyfikat podpisu zostaje „MeetNotes Dev"; `bundle.sh` przyjmuje `YASCRIBE_SIGN_IDENTITY` z tą domyślną nazwą. Zmiennych `MEETNOTES_*` nie zostawiamy jako aliasów.

## Review Focus (czego spec nie mówi dosłownie, a co użytkownik napotka)

Każda linia ma test w zadaniu, które posiada kod. Najpierw najbardziej prawdopodobne:

1. **Użytkownik ma dane w `MeetNotes/` i jednocześnie niepusty `Yascribe/`** (np. po uruchomieniu nowej wersji z `YASCRIBE_DATA_DIR` albo po pierwszym starcie sprzed migracji). Oczekiwane: blokujący alert, żadnego cichego scalania ani wyboru. Test: `bothDirectoriesWithDataAreReportedNotMerged` (T3).
2. **Stara pozycja pęku nieczytelna po zmianie bundle ID** (odmowa dostępu ≠ brak klucza). Oczekiwane: komunikat „couldn't read the old key (access denied)" i ponowne wpisanie, nie „no key". Test: `unreadableOldKeyIsReportedNotTreatedAsMissing` (T3).
3. **Stara aplikacja nadal działa podczas migracji** (zapisuje do `MeetNotes/`). Oczekiwane: katalog nie jest ruszany, komunikat „quit the old MeetNotes first". Test: `runningOldAppBlocksTheMove` (T3).
4. **Aktualizacja albo ⌘Q w trakcie nagrania/zapisu.** Oczekiwane: restart odroczony, zamknięcie odmówione, nowe nagranie zablokowane w trakcie instalacji. Testy: `postponesWhileBusy`, `terminationIsRefusedWhileBusy`, `installingBlocksNewRecording` (T4); test na żywo w T9.
5. **Wydanie z podpisem ad-hoc albo z numerem builda nie większym od opublikowanego.** Oczekiwane: `release.sh` odmawia przed wysłaniem czegokolwiek. Testy: `check-release.sh` przypadki `adhoc-signature-rejected`, `non-increasing-build-rejected` (T6).

## Instrukcja wykonania

**Gałęzie i repo.** T0 pracuje na kopii w scratchpadzie. T1 tworzy **nowy checkout** `/Users/michalprzytulski/yascribe` (remote `origin` = `sharezz1/yascribe`); obecny `/Users/michalprzytulski/meetnotes` zostaje prywatnym archiwum (nic w nim nie zmieniamy po T1). Od T2 wszystkie zadania w nowym checkoucie: T2–T3 na gałęzi `rename` (PR do `master`, `--merge`), T4–T6 na gałęzi `sparkle` (PR do `master`, `--merge`); merge do `master` wymaga zgody użytkownika (**STOP-U**). Katalog projektu zmienia się, więc pamięć projektu Claude Code (`~/.claude/projects/-Users-michalprzytulski-meetnotes/memory/`) nie obejmie nowego checkoutu — użytkownik może ją skopiować pod nową ścieżkę (**[UŻYTKOWNIK]**, opcjonalnie).

### Przydział modeli

| Model | Zadania / kroki |
|---|---|
| **Haiku** (`model: "haiku"`) | uruchomienia `scripts/test.sh` i porównanie liczby, mutacje wg przepisu, `grep` kontrolne, odhaczanie `- [ ]`, edycje dokumentów żywych (T2 krok 7, T10), aktualizacja artefaktu „Mapa faz Yascribe" |
| **Sonnet** (główna sesja) | implementacja z gotowymi sygnaturami i testami: T2 (rename), T3, T4, T5, T6 |
| **Opus** (`model: "opus"` lub `advisor`) | **T0** (spike), **T1** (przepisanie historii: operacja nieodwracalna w sensie kopii), **przegląd T3** (utrata danych), **przegląd T6** (wydanie), **T7** (audyt), **T9** (wydania i próba aktualizacji), jeden przegląd całości przed scaleniem `sparkle` |

Przepis mutacji (Haiku): (a) zastage'uj jawnie pliki zadania, (b) wprowadź mutację, (c) `scripts/test.sh --filter <Nazwa>` — **oczekiwane: pada** (nie pada = STOP), (d) `git checkout <plik>`, (e) pełne `scripts/test.sh`.

### Kroki użytkownika (zbiorczo)

1. T0: uruchomić trzy polecenia sondy pęku i opisać, czy pojawiło się okno dostępu; potem usunąć wpis testowy.
2. T1: `brew install git-filter-repo`; ustawienia konta GitHub „Keep my email addresses private" i „Block command line pushes that expose my email"; decyzja o worktree `meetnotes-codex`; decyzja o imieniu i nazwisku autora (domyślnie zostaje).
3. T8: `generate_keys` (klucz prywatny zostaje w pęku login), podanie agentowi klucza **publicznego**; „Always Allow" przy pierwszym `sign_update`.
4. T7: decyzja O2 po skanie i osobne „tak" na `gh repo edit --visibility public`.
5. T9: „tak"/„wydaj" przed `v0.1.0` i przed `v0.1.1`; zgody TCC (mikrofon, dźwięk systemowy, kalendarz) po pierwszym uruchomieniu `/Applications/Yascribe.app`; kliknięcie „Check for Updates…" → „Install"; test aktualizacji w trakcie nagrania; usunięcie starej pozycji `meetnotes.provider` w Keychain Access i starego `MeetNotes.app`, jeśli istnieje.

### Co robi którą część listy

| Spec | Zadanie |
|---|---|
| Spike S0, poprawki 3 i 8 | T0 |
| O1, poprawka 12, §5 (nowe repo) | T1 |
| §1 Rename | T2 |
| §2 Migracja, poprawki 2, 3, 4 | T3 |
| §3 Sparkle, poprawki 1, 7, 10 | T4, T5 |
| §4 `release.sh`, poprawki 5, 9, 11 | T6 |
| §5 Upublicznienie, poprawka 6, O2 | T7 |
| klucz EdDSA, SUPublicEDKey | T8 |
| Kolejność 5, instalacja, próba aktualizacji | T9 |
| dokumenty żywe, artefakt | T2 krok 7, T10 |

---

### Task 0: Spike S0 — Sparkle przy samych CLT i pęk po zmianie bundle ID (wyrzucany)

**Model:** Opus. **Wynik:** `docs/superpowers/spikes/2026-10-25-yascribe-s0-sparkle-i-pek.md` (jedyny trwały plik; kod spike'u nie trafia do repo). GO/NO-GO wg speca; NO-GO Sparkle = STOP i powrót do użytkownika z wariantem B (nie przechodzimy sami).

**Files:**
- Create: `docs/superpowers/spikes/2026-10-25-yascribe-s0-sparkle-i-pek.md`
- Spike w kopii: `$SCRATCH/s0/` (`git clone --no-local /Users/michalprzytulski/meetnotes $SCRATCH/s0`; brak rename; `$SCRATCH` = katalog scratchpada sesji)

**Interfaces:**
- Produces (dla T4–T6): dokładna wersja Sparkle (pin), ścieżki `Sparkle.framework` i `bin/{generate_keys,sign_update,generate_appcast}` w `.build/artifacts/`, komplet kroków osadzania i podpisu od środka, wymagane klucze `Info.plist`, wynik testów rozpakowanej kopii, odpowiedź na pytanie pęku (macierz niżej).

**Część A — Sparkle (agent):**

- [ ] **Step 1: Dobierz pin.** `gh api repos/sparkle-project/Sparkle/releases --jq '.[].tag_name'` — najnowsze wydanie stabilne z maja 2026 lub starsze (nie `-beta`); zapisz w raporcie. W kopii: `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "<wersja>")`, zależność `.product(name: "Sparkle", package: "Sparkle")` w `MeetNotesApp`; `swift package --disable-keychain resolve`.
- [ ] **Step 2: Linkowanie i osadzenie.** W kopii `bundle.sh`: skopiuj `Sparkle.framework` (z `xcframework/macos-arm64_x86_64`) do `Contents/Frameworks` przez `ditto` (zachowuje symlinki), `install_name_tool -add_rpath @executable_path/../Frameworks` na pliku wykonywalnym, usuń `Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices` (brak sandboxa).
- [ ] **Step 3: Podpis od środka** certyfikatem „MeetNotes Dev": `Autoupdate`, `Updater.app`, framework, aplikacja — każdy osobnym `codesign --force --sign "MeetNotes Dev"`, bez `--deep`; na końcu `codesign --verify --strict --deep "$APP"`.
- [ ] **Step 4: Kod spike'u.** `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` w `MeetNotesApp.init`, pozycja „Check for Updates…" wołająca `checkForUpdates(_:)`. `Info.plist` (tylko w kopii): `SUFeedURL=http://localhost:8123/appcast.xml`, `SUPublicEDKey`, `SUEnableAutomaticChecks=false`, `NSAppTransportSecurity/NSAllowsLocalNetworking=true`, wersje `0.1.0` (build 1) i `0.1.1` (build 2).
- [ ] **Step 5: Klucz jednorazowy bez pęku użytkownika.** Wygeneruj parę Ed25519 `openssl genpkey -algorithm ed25519`, wyprowadź 32-bajtowy seed i klucz publiczny jako base64 (format Sparkle), podaj `sign_update --ed-key-file <plik>`. Jeśli format nie pasuje — **[UŻYTKOWNIK]** uruchamia `generate_keys --account yascribe-s0` (wpis testowy) i po spike'u go usuwa; zapisz to w raporcie.
- [ ] **Step 6: Wydanie lokalne i próba.** Zbuduj `0.1.0` i `0.1.1`, `ditto -c -k --keepParent` zip `0.1.1`, podpis `sign_update`, ręczny `appcast.xml` (`sparkle:version`, `sparkle:shortVersionString`, `enclosure url/length/sparkle:edSignature`, `sparkle:minimumSystemVersion` 27.0), `python3 -m http.server 8123` w katalogu z zipem w tle.
- [ ] **Step 7: Test bez fałszywego GO (poprawka 8).** Rozpakuj `0.1.0` do **innego katalogu** (`$SCRATCH/s0-run/Yascribe.app`), przy niedostępnym `.build` (`mv .build .build.off`); sprawdź `otool -L` (Sparkle po `@rpath`), `otool -l | grep -A2 LC_RPATH`, symlinki frameworka (`ls -l`), prawa wykonywania `Autoupdate` i `Updater.app`; uruchom i kliknij „Check for Updates…". **GO** = widzi `0.1.1`, pobiera, weryfikuje EdDSA, podmienia i startuje. Dodatkowo **negatywna próba**: zip z popsutym podpisem w appcaście → Sparkle odmawia (anty-cel „wydanie bez podpisu").
- [ ] **Step 8: Sprawdź `bin/`.** `ls .build/artifacts/sparkle/Sparkle/bin/` — potwierdza, że `generate_keys` i `sign_update` są z artefaktu SwiftPM (spec, decyzja „Klucz EdDSA"); zanotuj usage `sign_update` (format wyjścia).

**Część B — pęk kluczy po zmianie bundle ID (agent przygotowuje, [UŻYTKOWNIK] uruchamia):**

- [ ] **Step 9: Sonda.** W kopii: cel `kc-probe` (plik wykonywalny) używający `KeychainSecretStore(service: "meetnotes.s0test")` z poleceniami `set`, `get`, `delete` dla UUID stałego i wartości `test-fake-s0` (nigdy prawdziwej usługi `meetnotes.provider`). Zbuduj dwie minimalne paczki `.app`, różniące się wyłącznie `CFBundleIdentifier`: `io.github.sharezz1.meetnotes.s0` i `io.github.sharezz1.yascribe.s0`, obie podpisane „MeetNotes Dev" (taki sam certyfikat jak aplikacja). Przygotuj `run-s0.sh` z trzema poleceniami i wypisz je użytkownikowi.
- [ ] **Step 10: [UŻYTKOWNIK]** w swoim terminalu: (1) paczką A `set`, (2) paczką A `get` (kontrola), (3) paczką B `get`; opisuje, czy pojawiło się okno dostępu do pęku, i co wypisało (1)–(3); na końcu `delete` (paczką A) usuwa wpis testowy. Agent niczego nie zapisuje w pęku.
- [ ] **Step 11: Raport z macierzą.** Wynik (3): *odczyt bez okna* → migracja kluczy działa bezobsługowo; *okno, po „Allow" odczyt działa* → migracja kopiuje po zgodzie (nic do zmiany w kodzie); *odmowa/błąd* → `KeyMigration` zgłosi `unreadable` i użytkownik wpisuje klucz ponownie. Żaden z trzech wyników nie blokuje planu; zmienia tylko treść komunikatu w T3. Dopisz: czy `-25293`/`-25244`/`-34018` itp. — dokładny kod `OSStatus` odmowy do testu T3.
- [ ] **Step 12: Commit raportu** w repo (na gałęzi planu lub, po T1, w nowym repo): `git add docs/superpowers/spikes/2026-10-25-yascribe-s0-sparkle-i-pek.md && git commit -m "Spike S0 Yascribe: Sparkle bez Xcode i pęk po zmianie bundle ID"`. Kopię `$SCRATCH/s0` skasuj po wypisaniu wyniku.

---

### Task 1: Przepisanie historii i nowe repo `sharezz1/yascribe`

**Model:** Opus. Wymaga zgody (**STOP-U**) przed `git push` do nowego repo i przed tym, jak użytkownik zacznie je używać; stare repo zostaje nietknięte. Spec: O1, poprawka 12.

**Files:**
- Create: `scripts/rewrite-hashes.py` (jednorazowy, trafia do repo jako zapis operacji; w nowym repo)
- Modify: `scripts/check-hashes.allow` (uzupełnienie), 84 pliki `docs/**/*.md` (podmiana hashy)
- Create: `docs/superpowers/reports/Y-przepisanie-historii.md`

**Interfaces:**
- Produces: nowy checkout `/Users/michalprzytulski/yascribe` z `master` (przepisana historia + gałąź planu i speca scalone), 5 tagów przepiętych, mapa `commit-map` stary→nowy hash zapisana w raporcie (ścieżka kopii w scratchpadzie), `git config user.email` = `166069997+sharezz1@users.noreply.github.com` w tym repo.

- [ ] **Step 1: [UŻYTKOWNIK]** `brew install git-filter-repo`; potwierdza, że imię i nazwisko autora zostaje (domyślnie tak); decyduje o worktree `/Users/michalprzytulski/meetnotes-codex` (usunąć po T1 albo zostawić tylko jako część archiwum — nie może trafić do nowego repo, bo to osobny checkout starego).
- [ ] **Step 2: Kopia zapasowa.** `git -C /Users/michalprzytulski/meetnotes bundle create $SCRATCH/meetnotes-przed-przepisaniem.bundle --all`; `git bundle verify` ma zwrócić „is okay".
- [ ] **Step 3: Świeży klon do przepisania.** `git clone --no-local /Users/michalprzytulski/meetnotes $SCRATCH/rewrite` (filter-repo wymaga świeżego klonu). Wypisz stan *przed*: `git log --all --format='%ae%n%ce' | sort | uniq -c` (oczekiwane: adres służbowy dominuje), `git rev-list --all --count`, `git tag`.
- [ ] **Step 4: Mapa autorów** `$SCRATCH/mailmap.txt`: `Michał Przytulski <166069997+sharezz1@users.noreply.github.com> <[adres służbowy]>` (jeśli użytkownik zmienił imię — odpowiednio); dodaj wiersze dla każdego innego adresu z kroku 3, który nie jest noreply. Uruchom `git filter-repo --mailmap $SCRATCH/mailmap.txt --force` (filter-repo przepina tagi sam i zapisuje `.git/filter-repo/commit-map`).
- [ ] **Step 5: Adres w treści.** `git log --all --format=%B | grep -ci 'yarrl'` oraz `git grep -il yarrl $(git rev-list --all)` (po filtrze); jeśli adres występuje w treści commitów (trailery, `Co-Authored-By`) lub w blobach — dodaj `--replace-message`/`--replace-text` z plikiem zamian i powtórz od kroku 3 na świeżym klonie. Warunek przejścia: `git log --all --format='%ae %ce' | sort -u` zwraca tylko noreply, a oba grepy — 0.
- [ ] **Step 6: Podmiana hashy.** `scripts/rewrite-hashes.py <commit-map>`: dla każdego tokenu `` `[0-9a-f]{7,40}` `` w `docs/**/*.md` znajdź jednoznaczny stary pełny hash po prefiksie, zamień na prefiks tej samej długości nowego hasha; zero trafień lub niejednoznaczność = wpis do raportu, nie zgadywanie; hashe z `check-hashes.allow` (też mapowane) i te, których nie ma w mapie (obiekty już wiszące), zostają i trafiają do raportu. Aktualizacja `scripts/check-hashes.allow` według tej samej mapy. Jeden commit „Hashe po przepisaniu historii (stary → nowy wg mapy)" **na wierzchu** `master`; to jedyny wyjątek od zakazu edycji dokumentów historycznych.
- [ ] **Step 7: Weryfikacja.** `git config core.hooksPath scripts/hooks && scripts/check-hashes.sh` → kod 0; liczba commitów równa kroku 3; `scripts/test.sh` → **744/744** (przepisanie historii nie zmienia kodu); `git tag` — 5 tagów (`faza-1.5`, `faza-1.5a`, `faza-1.5b-wyciszanie`, `faza-1.6`, `faza-2.0`) wskazują commity o tych samych tematach co wcześniej (porównaj `git log -1 --format=%s`).
- [ ] **Step 8: Scal gałąź planu.** Gałąź `docs/yascribe-rebrand-plan` (spec + plan) jest w klonie po filtrze; zrób `git merge --ff-only` (lub `--no-ff` jeśli nie jest potomkiem `master`) do `master` **przed** commitem z hashami (kolejność: scalenie → podmiana hashy, bo spec i plan też je cytują).
- [ ] **Step 9: Nowe repo prywatne i push.** `gh repo create sharezz1/yascribe --private` (**STOP-U** przed tym i przed pushem). Push tylko `master` i tagów: `git remote add origin git@github.com:sharezz1/yascribe.git` (lub https wg konta), `git push origin master` i `git push origin --tags` (żadnych pozostałych gałęzi, `--all` zabronione). `git ls-remote origin` ma pokazać wyłącznie `master` i 5 tagów.
- [ ] **Step 10: Nowy checkout roboczy.** `git clone git@github.com:sharezz1/yascribe.git /Users/michalprzytulski/yascribe`; w nim `git config user.email '166069997+sharezz1@users.noreply.github.com'`, `git config user.name 'Michał Przytulski'` (lub wg kroku 1), `git config core.hooksPath scripts/hooks`; globalny adres służbowy zostaje poza repo. `git log --format=%ae | sort -u` w nowym checkoucie = tylko noreply.
- [ ] **Step 11: [UŻYTKOWNIK]** na koncie GitHub: „Keep my email addresses private" i „Block command line pushes that expose my email" (ustawienia konta, nie repo). Agent nie dotyka ustawień konta.
- [ ] **Step 12: Raport** `docs/superpowers/reports/Y-przepisanie-historii.md` (liczby przed/po, ścieżka bundle i `commit-map` w scratchpadzie, lista hashy bez mapowania, wynik kroków 5, 7, 9, 10) i commit w nowym checkoucie: `git add docs/superpowers/reports/Y-przepisanie-historii.md scripts/rewrite-hashes.py && git commit -m "Raport i narzędzie: przepisanie historii do yascribe"`.

---

### Task 2: Rename `MeetNotes` → `Yascribe` (jeden mechaniczny commit + poprawki)

**Model:** Sonnet (kroki uruchomieniowe Haiku). Gałąź `rename` w `/Users/michalprzytulski/yascribe`. **Warunek zakończenia: `scripts/test.sh` = 744/744.** Spec §1.

**Files (tablica ze speca):**
- Modify: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/*.sh`, `Resources/Info.plist`, `CLAUDE.md`, `docs/superpowers/ROADMAP.md`, `docs/superpowers/BACKLOG.md`, `docs/design/macos.md`, `docs/wymagania.md`
- Rename (git mv): `Sources/MeetNotes*` → `Sources/Yascribe*`, `Sources/meetnotes-cli` → `Sources/yascribe-cli`, `Tests/MeetNotes*Tests` → `Tests/Yascribe*Tests`, `Sources/MeetNotesApp/MeetNotesApp.swift` → `YascribeApp.swift` (i analogicznie każdy plik z `MeetNotes` w nazwie)

**Interfaces:**
- Produces (dla T3–T6): moduły `YascribeSessionFormat`, `YascribeRecording`, `YascribeProviders`, `YascribeLocalASR`, `YascribeTranscription`, `YascribeNotes`, `YascribeMeetings`, `YascribeApp`; produkty `YascribeApp`, `yascribe-cli`; `YascribePaths` (dawniej `MeetNotesPaths`) z `fromEnvironment` czytającym `YASCRIBE_DATA_DIR` i katalogiem `Application Support/Yascribe`; `KeychainSecretStore(service: "yascribe.provider")`; bundle ID `io.github.sharezz1.yascribe`; zmienne `YASCRIBE_DATA_DIR`, `YASCRIBE_MODEL_STORE`, `YASCRIBE_APP`, `YASCRIBE_SIGN_IDENTITY`, `YASCRIBE_SNAPSHOT_DIR`, `YASCRIBE_PROBE*`; paczka `.build/Yascribe.app`, plik wykonywalny `YascribeApp`.

- [ ] **Step 1: Stan wyjściowy.** Gałąź `rename` od `master`; `rm -rf .build && swift package --disable-keychain resolve && scripts/test.sh` → **744/744** (zapisz). Spis do kontroli: `git grep -il 'meetnotes' | wc -l` i `git grep -c '@Test' -- Tests | awk -F: '{s+=$2} END {print s}'`.
- [ ] **Step 2: Zmiany nazw plików i katalogów** przez `git mv` (najpierw katalogi, potem pliki z `MeetNotes` w nazwie: `git ls-files | grep -i meetnotes`). Pliki i katalogi nieśledzone (`.claude-flow`, `.devdata`, `.build`) nie istnieją dla tego kroku.
- [ ] **Step 3: Podmiana tekstu — wyłącznie w plikach śledzonych** i tylko poza `docs/superpowers/{specs,plans,reports,spikes}/` i `docs/design/inspiracje/` (historyczne zostają). Kolejność reguł (od najdłuższej):
  `io.github.sharezz1.meetnotes` → `io.github.sharezz1.yascribe`; `meetnotes-cli` → `yascribe-cli`; `meetnotes.provider` → `yascribe.provider`; `MEETNOTES_` → `YASCRIBE_`; `MeetNotes` → `Yascribe`. **Wyjątki zachowane przez zamianę zastępczą przed i po:** certyfikat `MeetNotes Dev` (w `bundle.sh`, `check-bundle.sh`, `snapshot.sh`, `CLAUDE.md`; domyślna wartość `YASCRIBE_SIGN_IDENTITY`), nazwa repo w `CLAUDE.md`/dokumentach żywych tam, gdzie mowa o starym repo archiwum (`sharezz1/meetnotes`), cytaty historycznych ścieżek i hashy w `ROADMAP.md`/`BACKLOG.md` (zostają jak były). Teksty `Info.plist` stają się „Yascribe records …", `CFBundleName`/`DisplayName` = „Yascribe", `CFBundleExecutable` = `YascribeApp`.
- [ ] **Step 4: `Package.swift`:** `name: "Yascribe"`, produkty `YascribeApp` i `yascribe-cli`, wszystkie targety i `testTarget` zgodnie z tabelą; **pin FluidAudio bez zmian** (`exact: "0.17.7"`); komentarz o jedynym pinie uzupełnia T4. `scripts/run.sh`: `pgrep -x YascribeApp` (komunikaty także), `open -n --env YASCRIBE_DATA_DIR=…`. `scripts/test.sh` — wzorzec sprzątający `mn-…` bez zmian. Uwaga: **po rename `run.sh` nie wykryje działającej starej `MeetNotesApp`** — migracja (T3) sprawdza to własnym testem.
- [ ] **Step 5: Czyste odtworzenie i bramka.** `rm -rf .build && swift package --disable-keychain resolve && scripts/test.sh` → **744/744**, `check-bundle.sh` OK (`.build/check/Yascribe.app`); `scripts/bundle.sh` zwraca `.build/Yascribe.app`, `plutil -extract CFBundleIdentifier raw` = `io.github.sharezz1.yascribe`. Kontrola pozostałości: `git grep -in 'meetnotes' -- . ':!docs/superpowers/specs' ':!docs/superpowers/plans' ':!docs/superpowers/reports' ':!docs/superpowers/spikes' ':!docs/design/inspiracje'` — dozwolone tylko: certyfikat `MeetNotes Dev`, nazwa starego repo/archiwum w dokumentach żywych, ścieżki historyczne w BACKLOG/ROADMAP; każdy inny wynik = popraw.
- [ ] **Step 6: Commit mechaniczny** jednym commitem: `git add Package.swift Package.resolved Sources Tests scripts Resources` (jawne ścieżki; `Package.resolved` jeśli się zmienił) `&& git commit -m "Rename MeetNotes → Yascribe (mechaniczny)"`; w komunikacie liczba plików i wynik 744/744. Dokumenty żywe w osobnym commicie (krok 7).
- [ ] **Step 7: [haiku] Dokumenty żywe.** `CLAUDE.md` (nazwa produktu, tabela ścieżek, moduły `Yascribe*`, zmienne `YASCRIBE_*`, `Yascribe.app`; stan „Faza 2.1.x — rename" dopisze T10), `ROADMAP.md`, `BACKLOG.md`, `docs/design/macos.md`, `docs/wymagania.md` wg reguł kroku 3; `scripts/check-hashes.sh` → kod 0. Commit: `git add CLAUDE.md docs/superpowers/ROADMAP.md docs/superpowers/BACKLOG.md docs/design/macos.md docs/wymagania.md && git commit -m "Dokumenty żywe: nazwa Yascribe"`.
- [ ] **Step 8: Uwaga o nazwie „Yascribe model".** Karta modelu lokalnego (Parakeet) i etykieta „Yascribe" w menu dostawców nazywają się już „Yascribe" — po rename kolidują z nazwą aplikacji. **Nie zmieniaj** (poza zakresem); wpisz do `BACKLOG.md` pozycję „Nazwa karty/dostawcy „Yascribe" vs nazwa aplikacji" i zgłoś użytkownikowi w raporcie.

---

### Task 3: Migracja danych i kluczy przy pierwszym starcie

**Model:** Sonnet (implementacja), **Opus (przegląd po zadaniu: utrata danych)**. Gałąź `rename`. Spec §2, poprawki 2, 3, 4.

**Files:**
- Create: `Sources/YascribeProviders/DataMigration.swift`, `Sources/YascribeProviders/KeyMigration.swift`
- Modify: `Sources/YascribeProviders/Stores.swift` (`YascribePaths.isOverridden`), `Sources/YascribeApp/YascribeApp.swift` (migracja przed `AppModel()`), `Sources/YascribeApp/AppModel.swift` (komunikat o kluczach)
- Test: `Tests/YascribeProvidersTests/DataMigrationTests.swift`, `Tests/YascribeProvidersTests/KeyMigrationTests.swift`

**Interfaces:**
- Produces:
  - `public enum DataMigrationOutcome: Equatable, Sendable { case notNeeded, moved, bothHaveData, oldAppRunning, failed(String) }`
  - `public struct DataDirectoryMigration: Sendable { public init(oldRoot: URL, newRoot: URL, isOldAppRunning: @escaping @Sendable () -> Bool); public func run() -> DataMigrationOutcome }` — „znane pliki": `providers.json`, `presets.json`, `settings.json`, `templates.json`, `dictionary.json`, `sessions`; katalog „ma dane" ⇔ istnieje którykolwiek z nich.
  - `public enum KeyMigrationOutcome: Equatable, Sendable { case copied, alreadyPresent, noOldKey, unreadable(Int32) }`
  - `public struct KeyMigration: Sendable { public init(old: any SecretStore, new: any SecretStore); public func run(providerIDs: [UUID]) -> [UUID: KeyMigrationOutcome] }`
  - `YascribePaths.isOverridden(_ env: [String: String]) -> Bool` (true gdy `YASCRIBE_DATA_DIR` niepusty).
- Zasady: migracja katalogu nie rusza niczego, gdy `isOverridden`; pusty `Yascribe/` (zero wpisów) = nieistniejący i jest usuwany przed `moveItem`; `Yascribe/` bez znanych plików, ale z innymi wpisami → `failed("unexpected files in …")`; `moveItem` nie kopiuje ani nie kasuje; błąd = `failed` i **stary katalog nietknięty**. Klucze: stara pozycja **nigdy nie jest usuwana**; po przebiegu zapis znacznika `legacy-migration.json` w katalogu danych (`{"keysChecked": true}`), kolejne starty pomijają krok kluczy.

- [ ] **Step 1: Testy katalogu (nazwy i asercje, fałszywe katalogi `mn-<UUID>`; zapisz 7 testów):**
  - `movesOldDirectoryWhenNewIsMissing` — stary ma `providers.json`; po `run()` `.moved`, nowy ma plik o tych samych bajtach, stary nie istnieje.
  - `emptyNewDirectoryIsTreatedAsMissing` — nowy istnieje i pusty → `.moved`.
  - `bothDirectoriesWithDataAreReportedNotMerged` — oba mają `settings.json` → `.bothHaveData`, zawartość obu bez zmian. *(Review Focus 1)*
  - `runningOldAppBlocksTheMove` — `isOldAppRunning` zwraca true → `.oldAppRunning`, stary katalog nietknięty. *(Review Focus 3)*
  - `nothingToDoWhenOldIsMissing` — `.notNeeded`, nowy nie powstaje.
  - `moveFailureLeavesOldDirectoryIntactAndReportsError` — nowy rodzic tylko do odczytu (chmod 0o500) → `.failed`, stary ma wszystkie pliki; chmod przywrócony w `defer`.
  - `unknownFilesInNewDirectoryAreNotOverwritten` — nowy z obcym plikiem, bez znanych → `.failed`, oba katalogi bez zmian.
- [ ] **Step 2: Testy kluczy (fałszywe `InMemorySecretStore` i `FailingSecretStore` z `get` rzucającym `SecretStoreError.keychain(<kod z T0>)`; wartości `test-fake-…`; 5 testów):**
  - `copiesOldKeyWhenNewIsMissing` — wynik `.copied`, `new.get(id)` = wartość.
  - `keepsExistingNewKey` — nowy ma `test-fake-new`, stary `test-fake-old` → `.alreadyPresent`, nowy bez zmian.
  - `unreadableOldKeyIsReportedNotTreatedAsMissing` — `.unreadable(kod)`, nie `.noOldKey`. *(Review Focus 2)*
  - `neverDeletesTheOldKey` — po `.copied` `old.get(id)` nadal zwraca wartość.
  - `markerPreventsSecondRun` — funkcja pomocnicza `KeyMigrationMarker.shouldRun(root:)`/`markDone(root:)` (w `KeyMigration.swift`): po `markDone` `shouldRun` = false; brak pliku = true; nieczytelny plik = true (bez rzucania).
- [ ] **Step 3: Uruchom → mają paść** (`scripts/test.sh --filter DataMigrationTests`; „cannot find" lub brak symboli).
- [ ] **Step 4: Implementuj** `DataDirectoryMigration.run()` i `KeyMigration.run(providerIDs:)` wg sygnatur i zasad wyżej (`FileManager.moveItem`; stary katalog `MeetNotes` w `Application Support`, nowy `Yascribe` — literały starych nazw wyłącznie w `YascribeApp.swift` przy składaniu argumentów, nie w bibliotece). Testy mają przejść; liczba: **744 + 12 = 756**.
- [ ] **Step 5: Podłączenie w `YascribeApp`.** `private let model = AppModel()` → pole inicjowane w `init()` **po** migracji: (1) jeśli `!YascribePaths.isOverridden(env)`: `DataDirectoryMigration(oldRoot: …/MeetNotes, newRoot: …/Yascribe, isOldAppRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.sharezz1.meetnotes").isEmpty })`; (2) wynik: `.bothHaveData` → `NSAlert` krytyczny „Use Yascribe data" / „Quit" (blokujący `runModal`; „Quit" kończy proces bez startu `AppModel`); `.oldAppRunning` → alert „Quit the old MeetNotes first, then open Yascribe again." i wyjście; `.failed(msg)` → alert z komunikatem i wyjście (aplikacja nie startuje na pustym katalogu); (3) dopiero potem `AppModel()` (`load()`), zgodnie z poprawką 4: migracja przed wczytaniem i przed zapisem jakichkolwiek domyślnych plików; (4) po `AppModel.load()` `KeyMigration(old: KeychainSecretStore(service: "meetnotes.provider"), new: KeychainSecretStore())` dla UUID z `providers.json`, jeśli `KeyMigrationMarker.shouldRun`; wyniki `.unreadable` → w interfejsie jednorazowa informacja „Couldn't read the old key for <provider> (access denied). Enter it again in Settings." (treść wg macierzy z T0), potem `markDone`. Brak testu jednostkowego dla alertów (UI): pilnuje go krok odbioru T9 (świeży start na kopii danych).
- [ ] **Step 6: Mutacje (Haiku):** (a) w `run()` usuń gałąź `bothHaveData` (zawsze przenoś) → `bothDirectoriesWithDataAreReportedNotMerged` pada; (b) usuń sprawdzenie `isOldAppRunning` → `runningOldAppBlocksTheMove` pada; (c) w `KeyMigration` mapuj każdy błąd na `.noOldKey` → `unreadableOldKeyIsReportedNotTreatedAsMissing` pada; (d) po kopii wywołaj `old.delete(id)` → `neverDeletesTheOldKey` pada. Po każdej `git checkout`, na końcu pełne `scripts/test.sh` = **756/756**.
- [ ] **Step 7: Commit:** `git add Sources/YascribeProviders/DataMigration.swift Sources/YascribeProviders/KeyMigration.swift Sources/YascribeProviders/Stores.swift Sources/YascribeApp Tests/YascribeProvidersTests/DataMigrationTests.swift Tests/YascribeProvidersTests/KeyMigrationTests.swift && git commit -m "Migracja danych i kluczy MeetNotes → Yascribe przy pierwszym starcie"`.
- [ ] **Step 8: Przegląd Opusa** (osobny, read-only): czy któraś ścieżka może skasować lub przepisać dane użytkownika; czy `moveItem` na tym samym woluminie (Application Support) jest atomowy; czy `AppModel()` nie jest wywoływany przed migracją (np. przez `@main` inicjalizujący statyczne pole). Uwagi do raportu `docs/superpowers/reports/Y-przeglad-T3.md`; PR `rename` do `master` po **STOP-U** (`--merge`).

---

### Task 4: Moduł `YascribeUpdates`, `RestartGate`, ochrona nagrania

**Model:** Sonnet. Gałąź `sparkle` od `master` (po scaleniu `rename`). Spec §3, poprawki 1, 10. Wersję Sparkle bierz z raportu T0.

**Files:**
- Modify: `Package.swift` (zależność `Sparkle` z pinem z T0, target `YascribeUpdates`, `testTarget` `YascribeUpdatesTests`; komentarz: „Drugi pin zewnętrzny; Sparkle importuje wyłącznie YascribeUpdates")
- Create: `Sources/YascribeUpdates/RestartGate.swift`, `Sources/YascribeUpdates/UpdateController.swift`
- Modify: `Sources/YascribeApp/YascribeApp.swift` (menu, delegat aplikacji), `Sources/YascribeApp/RecordingController.swift` lub `AppModel.swift` (podanie `RecordingActivity`), `Sources/YascribeApp/SettingsView.swift` (przycisk i wersja)
- Test: `Tests/YascribeUpdatesTests/RestartGateTests.swift`

**Interfaces:**
- Produces:
  - `public protocol RecordingActivity: AnyObject, Sendable { var isBusy: Bool { get } }` (`true` gdy trwa nagrywanie lub zapis; `RecordingController` dostarcza przez cienki adapter).
  - `public final class RestartGate: @unchecked Sendable { public init(activity: any RecordingActivity); public func shouldPostpone(untilInvoking block: @escaping @Sendable () -> Void) -> Bool; public func activityDidChange(); public var isInstalling: Bool { get }; public func installationStarted(); public func shouldTerminate() -> Bool }`. `shouldPostpone` zwraca `true` i trzyma **jeden** blok, gdy `activity.isBusy`, inaczej `false` i nie wywołuje bloku; `activityDidChange()` wywołuje zatrzymany blok **dokładnie raz**, gdy `isBusy` spadło do `false`; `shouldTerminate()` = `!activity.isBusy`.
  - `@MainActor public final class UpdateController: ObservableObject { public init(gate: RestartGate); public var canCheck: Bool { get }; public func checkForUpdates(); public var currentVersion: String { get } }` — opakowuje `SPUStandardUpdaterController`; delegat Sparkle: `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` → `gate.shouldPostpone`; `updater(_:willInstallUpdate:)`/odpowiednik z T0 → `gate.installationStarted()`.
  - UI: pozycja „Check for Updates…" w menu aplikacji (po „About", poza `CommandMenu("Recording")`), w Settings sekcja „Updates": wersja (`CFBundleShortVersionString`, build) i przycisk „Check for Updates…" (`disabled(!canCheck)`).

- [ ] **Step 1: Testy `RestartGate` (nazwy i asercje, 5 testów, bez Sparkle; `FakeActivity` ze zmiennym `isBusy`):**
  - `postponesWhileBusy` — `isBusy = true`: `shouldPostpone` zwraca `true`, blok niewywołany. *(Review Focus 4)*
  - `proceedsWhenIdle` — `isBusy = false`: zwraca `false`, blok niewywołany.
  - `releasesBlockExactlyOnceWhenActivityEnds` — zatrzymany blok; `isBusy = false`, dwa razy `activityDidChange()` → licznik wywołań = 1.
  - `terminationIsRefusedWhileBusy` — `shouldTerminate()` = false przy `isBusy`, true po zakończeniu. *(Review Focus 4)*
  - `installingBlocksNewRecording` — po `installationStarted()` `isInstalling` = true; test w `YascribeApp`-niezależnej warstwie: `gate.canStartRecording` (dodaj właściwość `public var canStartRecording: Bool { !isInstalling }`) jest false. *(Review Focus 4)*
- [ ] **Step 2: Uruchom → padają** (brak typów). **Step 3: Implementuj** `RestartGate` (blokada `NSLock` na zatrzymanym bloku i fladze) i `UpdateController` wg sygnatur; `swift package --disable-keychain resolve`; testy zielone: **756 + 5 = 761**.
- [ ] **Step 4: Ochrona zamknięcia (poprawka 1).** Delegat aplikacji (`@NSApplicationDelegateAdaptor`) z `applicationShouldTerminate`: `gate.shouldTerminate() ? .terminateNow : .terminateCancel` plus `NSAlert` „Recording in progress. Stop recording and quit?" tylko dla ręcznego ⌘Q; **ścieżka Sparkle (po odroczeniu) nie pokazuje alertu**, bo blok jest wywoływany po końcu nagrania. `AppModel.startRecording` i pozycja menu „Record Meeting" mają `guard gate.canStartRecording` (w trakcie instalacji nowe nagranie zablokowane, komunikat „Update in progress."). `RecordingController` po zakończeniu/zapisie woła `gate.activityDidChange()` (w miejscu, gdzie `isRecording` spada do `false` i kończy się finalizacja — wskaż w kodzie `finish`).
- [ ] **Step 5: Mutacje (Haiku):** (a) `shouldPostpone` zwraca zawsze `false` → `postponesWhileBusy` pada; (b) `activityDidChange` nie czyści bloku po wywołaniu → `releasesBlockExactlyOnceWhenActivityEnds` pada; (c) `shouldTerminate` zwraca `true` → `terminationIsRefusedWhileBusy` pada. `git checkout` po każdej; pełne `scripts/test.sh` = **761/761**.
- [ ] **Step 6: Commit:** `git add Package.swift Package.resolved Sources/YascribeUpdates Sources/YascribeApp Tests/YascribeUpdatesTests && git commit -m "Sparkle: YascribeUpdates, RestartGate, ochrona nagrania"`. Reguła „jeden moduł importuje zewnętrzną bibliotekę" egzekwowana testem w `scripts/check-bundle.sh` (T5, krok 4): `git grep -l 'import Sparkle' Sources` zwraca wyłącznie pliki w `Sources/YascribeUpdates`.

---

### Task 5: Osadzanie frameworka w `bundle.sh`, `Info.plist`, numeracja

**Model:** Sonnet. Gałąź `sparkle`. Spec §3 (`bundle.sh`, `Info.plist`, numeracja), poprawki 7, 10, 11. Kroki wg raportu T0.

**Files:**
- Modify: `scripts/bundle.sh`, `scripts/check-bundle.sh`, `Resources/Info.plist`
- Create: `VERSION` (treść `0.1.0`)

**Interfaces:**
- Consumes: ścieżki artefaktu i kolejność podpisu z T0.
- Produces: `bundle.sh` czyta `VERSION` i `CFBundleVersion` = `git rev-list --count HEAD` (nadpisywalne `YASCRIBE_BUILD`/`YASCRIBE_VERSION` dla testów), wpisuje je do `Info.plist` paczki (`plutil -replace`, nie do pliku źródłowego); klucze w `Resources/Info.plist`: `SUFeedURL` = `https://github.com/sharezz1/yascribe/releases/latest/download/appcast.xml`, `SUPublicEDKey` = `REPLACE_WITH_PUBLIC_KEY` (T8 podmienia), `SUEnableAutomaticChecks` true, `SUAutomaticallyUpdate` false, `SUAllowsAutomaticUpdates` false.

- [ ] **Step 1: Rozszerz `check-bundle.sh` (najpierw, ma paść):** paczka ad-hoc ma `Contents/Frameworks/Sparkle.framework`; `otool -l` pokazuje `@executable_path/../Frameworks`; brak katalogu `XPCServices`; `codesign --verify --strict --deep` przechodzi; `plutil -extract SUFeedURL`, `SUPublicEDKey`, `SUAllowsAutomaticUpdates` (= false) istnieją; `CFBundleVersion` jest liczbą całkowitą ≥ 1; `git grep -l 'import Sparkle' Sources` ⊆ `Sources/YascribeUpdates`. Uruchom `scripts/check-bundle.sh` → pada (brak frameworka).
- [ ] **Step 2: Zaimplementuj w `bundle.sh`** osadzenie (`ditto` frameworka z `.build/artifacts/sparkle/…`, `install_name_tool -add_rpath`, usunięcie XPC), **podpis od środka** (Autoupdate, Updater.app, framework, aplikacja; bez `--deep`; dla ad-hoc `-`) i wpis wersji/builda; ostrzeżenie o ad-hoc zostaje (dev OK).
- [ ] **Step 3: `check-bundle.sh` przechodzi; pełne `scripts/test.sh`** = **761/761** (skrypt wywoływany z `test.sh`).
- [ ] **Step 4: Mutacja (Haiku):** w `bundle.sh` pomiń usunięcie `XPCServices` (lub rpath) → `check-bundle.sh` pada; `git checkout`.
- [ ] **Step 5: Test rozpakowanej kopii (poprawka 8, kontrola w repo):** `ditto` paczki do `$SCRATCH/run-test/`, `mv .build .build.off`, uruchom `YascribeApp` na 3 s (`open -n` lub bezpośrednio z `YASCRIBE_DATA_DIR` w katalogu tymczasowym, `YASCRIBE_SNAPSHOT_DIR` nie ustawiaj), proces ma żyć (`pgrep -x YascribeApp`), potem `pkill -x YascribeApp`; `mv .build.off .build`. Wynik do raportu.
- [ ] **Step 6: Commit:** `git add scripts/bundle.sh scripts/check-bundle.sh Resources/Info.plist VERSION && git commit -m "bundle.sh: osadzanie Sparkle, podpis od środka, wersja z VERSION"`.

---

### Task 6: `scripts/release.sh` i `scripts/check-release.sh`

**Model:** Sonnet, **przegląd Opusa**. Gałąź `sparkle`. Spec §4, poprawki 5, 9, 11.

**Files:**
- Create: `scripts/release.sh`, `scripts/make-appcast.sh`, `scripts/check-release.sh`
- Modify: `scripts/test.sh` (wywołanie `scripts/check-release.sh` po `check-bundle.sh`, kod wyjścia 6)

**Interfaces:**
- Produces: `scripts/release.sh <wersja> [--dry-run]`; zmienne wstrzykiwane dla testów: `YASCRIBE_SIGN_UPDATE` (ścieżka `sign_update`, domyślnie z artefaktu SwiftPM), `YASCRIBE_GH` (domyślnie `gh`), `YASCRIBE_FEED_FILE` (lokalny plik zamiast pobrania feedu), `YASCRIBE_SIGN_IDENTITY`. `make-appcast.sh <zip> <wersja> <build> <podpis> <długość>` → `appcast.xml` na stdout (jeden wpis `<item>` z `sparkle:version`, `sparkle:shortVersionString`, `enclosure url/length/sparkle:edSignature`, `sparkle:minimumSystemVersion` 27.0; URL zasobu `https://github.com/sharezz1/yascribe/releases/download/v<wersja>/Yascribe-<wersja>.zip`).
- Kolejność w `release.sh` (każdy punkt kończy się `exit` ≠ 0 z komunikatem przed jakimkolwiek zapisem poza katalogiem tymczasowym): (1) `git status --porcelain` pusty, gałąź `master`, `<wersja>` = zawartość `VERSION`, tag `v<wersja>` nie istnieje; (2) `scripts/test.sh` zielone; (3) `CONFIG=release scripts/bundle.sh` (zbudowana **podpisem z certyfikatu**, nie ad-hoc); (4) **podpis ad-hoc odrzucony i tożsamość sprawdzona:** `codesign -dr - "$APP"` musi zawierać `certificate leaf` / `identifier "io.github.sharezz1.yascribe"`, a `codesign -dvv` — `Authority=` zgodne z `YASCRIBE_SIGN_IDENTITY` (domyślnie „MeetNotes Dev"); (5) numer builda `git rev-list --count HEAD` **większy** od największego `sparkle:version` w opublikowanym feedzie (404 = pierwsze wydanie); (6) `ditto -c -k --keepParent` → `Yascribe-<wersja>.zip`; `sign_update` → podpis i długość; `make-appcast.sh`; `xmllint --noout`; (7) `gh release create v<wersja> --draft` z zipem i `appcast.xml`; weryfikacja szkicu przez `gh release download` (porównaj długość zipa i XML), **dopiero potem** `gh release edit v<wersja> --draft=false --latest`; (8) po publikacji `curl -fsSL` adresu feedu → ten sam XML, `curl -fsSIL` zasobu zip → 200. Tryb `--dry-run` wykonuje (1)–(6) i wypisuje, czego nie wysłał, **bez `gh`**. Wydanie dopiero na polecenie „wydaj" użytkownika; agent nie wywołuje `release.sh` bez `--dry-run` z własnej inicjatywy.

- [ ] **Step 1: `check-release.sh` — przypadki (każdy jako funkcja z `OK`/`FAIL`, stub `sign_update` zwracający `sparkle:edSignature="test-fake-sig" length="N"`, stub `gh` zapisujący wywołania do pliku, fałszywy feed w `YASCRIBE_FEED_FILE`; repo testowe: tymczasowy klon z jednym commitem na `master`):**
  - `dirty-tree-rejected`, `wrong-branch-rejected`, `version-mismatch-rejected` (argument ≠ `VERSION`).
  - `adhoc-signature-rejected` — `YASCRIBE_SIGN_IDENTITY=-` → odmowa, stub `gh` niewywołany. *(Review Focus 5)*
  - `non-increasing-build-rejected` — feed z `sparkle:version` ≥ bieżącego builda → odmowa. *(Review Focus 5)*
  - `appcast-is-valid-xml-with-signature` — `--dry-run` produkuje `appcast.xml`, `xmllint --noout` OK, zawiera `sparkle:edSignature` i `length` zgodne z rozmiarem zipa.
  - `draft-then-publish-order` — przy pełnym przebiegu stub `gh` widzi `release create … --draft` **przed** `release edit … --draft=false`.
  - `missing-signature-rejected` — `sign_update` zwraca puste → odmowa (anty-cel „wydanie bez podpisu EdDSA").
- [ ] **Step 2: Uruchom → pada** (brak skryptu). **Step 3: Implementuj** `release.sh`, `make-appcast.sh`; `check-release.sh` przechodzi; dopisz do `test.sh`; pełne `scripts/test.sh` = **761/761** (liczba `@Test` bez zmian; skrypt nie jest `@Test`).
- [ ] **Step 4: Mutacje (Haiku):** (a) usuń sprawdzenie ad-hoc → `adhoc-signature-rejected` FAIL; (b) zamień `>` na `>=` w porównaniu builda → `non-increasing-build-rejected` FAIL; (c) wywołaj publikację przed weryfikacją szkicu → `draft-then-publish-order` FAIL. `git checkout` po każdej.
- [ ] **Step 5: Commit:** `git add scripts/release.sh scripts/make-appcast.sh scripts/check-release.sh scripts/test.sh && git commit -m "release.sh: podpis EdDSA, appcast, szkic przed publikacją"`.
- [ ] **Step 6: Przegląd Opusa** (read-only, `docs/superpowers/reports/Y-przeglad-T6.md`): czy któraś ścieżka wypuści wydanie bez podpisu EdDSA lub z ad-hoc; czy klucz/token pojawia się w logu (`set -x` zabroniony); czy `curl -L` nie wyprowadza sekretów. Potem **jeden przegląd całości gałęzi `sparkle`** i PR do `master` po **STOP-U** (`--merge`).

---

### Task 7: Audyt przed upublicznieniem

**Model:** Opus (kroki skanowania Haiku). Spec §5, poprawka 6, O2. Raport: `docs/superpowers/reports/Y-audyt-publiczny.md`. **Nie zmienia widoczności.**

**Files:**
- Create: `docs/superpowers/reports/Y-audyt-publiczny.md`

- [ ] **Step 1: Skan Git.** Na nowym repo (wszystkie gałęzie i tagi): `git log --all -p | grep -E` wzorce kluczy (`sk-[A-Za-z0-9]{20,}`, `or-v1-`, `xi-api-key`, `Bearer [A-Za-z0-9._-]{20,}`, `ghp_`, `-----BEGIN`), adresy e-mail (`grep -rhoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' ` unikalne; dozwolony tylko noreply i `noreply@anthropic.com`), ścieżki `/Users/michalprzytulski` w śledzonych plikach, nazwy firm i klientów (lista od użytkownika; domyślnie „InPost", „yarrl", „Genesys" w `docs/` i fixturach).
- [ ] **Step 2: Fixtury i dokumenty.** Przejrzyj ręcznie `Tests/**/Fixtures`, `scripts/fixtures`, `docs/superpowers/spikes`, `docs/superpowers/reports` i `docs/design/inspiracje` pod kątem prawdziwych fragmentów rozmów, imion i nazwisk rozmówców, nagrań i zrzutów z realnych spotkań (zrzuty `png`: otwórz i sprawdź wzrokowo; lista plików z rozmiarem). Każdy trafiony plik = wiersz w raporcie z propozycją (usunąć/zastąpić/zostawić).
- [ ] **Step 3: Poza Gitem (poprawka 6).** Nowe repo jest prywatne i świeże: `gh api repos/sharezz1/yascribe/actions/runs --jq '.total_count'`, `…/actions/artifacts`, `gh pr list --state all`, `gh issue list --state all`, `gh api repos/sharezz1/yascribe/discussions` (lub informacja „brak") — oczekiwane zera; `gh api repos/sharezz1/yascribe/branches --jq '.[].name'` i `git ls-remote --tags origin` = tylko `master` i 5 tagów.
- [ ] **Step 4: Ustalenia ujęte w raporcie** w trzech częściach: „nic do zrobienia", „do decyzji użytkownika (O2)", „naprawione" (jeśli użytkownik zdecyduje o usunięciu plików: osobny commit **przed** upublicznieniem; pliki z historii usuwa wówczas ponowne przepisanie `git filter-repo --path … --invert-paths` w T1-stylu, więc ta decyzja wraca do użytkownika, nie jest wykonywana sama).
- [ ] **Step 5: Commit raportu:** `git add docs/superpowers/reports/Y-audyt-publiczny.md && git commit -m "Audyt przed upublicznieniem repo"`.
- [ ] **Step 6: STOP-U — O2 i widoczność.** Agent podaje użytkownikowi streszczenie raportu i pyta o osobne „tak". Dopiero po nim: `gh repo edit sharezz1/yascribe --visibility public --accept-visibility-change-consequences`; po zmianie: `gh repo view sharezz1/yascribe --json visibility` = `PUBLIC`; anonimowe `curl -fsSI https://github.com/sharezz1/yascribe` = 200. Bez „tak" repo zostaje prywatne, a T9 nie rusza.

---

### Task 8: Klucz EdDSA

**Model:** Haiku (kroki agenta), użytkownik wykonuje `generate_keys`. Gałąź `sparkle` (lub `master` po scaleniu).

**Files:**
- Modify: `Resources/Info.plist` (`SUPublicEDKey`)

- [ ] **Step 1: [UŻYTKOWNIK]** w swoim terminalu, w katalogu nowego repo, po `swift build --disable-keychain`: `.build/artifacts/sparkle/Sparkle/bin/generate_keys` (klucz prywatny ląduje w jego pęku login; polecenie wypisuje klucz **publiczny**). Użytkownik wkleja agentowi wyłącznie klucz publiczny (agent nie prosi o prywatny i nie czyta pęku).
- [ ] **Step 2: Wpisz klucz publiczny** w `Resources/Info.plist` pod `SUPublicEDKey` (zamiast `REPLACE_WITH_PUBLIC_KEY`); `plutil -lint` OK; `check-bundle.sh` rozszerz o odmowę wartości `REPLACE_WITH_PUBLIC_KEY` **tylko w `release.sh`** (krok 3 przed budową: `plutil -extract SUPublicEDKey raw` ≠ placeholder, odmowa). Commit: `git add Resources/Info.plist scripts/release.sh && git commit -m "SUPublicEDKey: klucz publiczny wydań"`.
- [ ] **Step 3: [UŻYTKOWNIK]** przy pierwszym `sign_update` (T9) wybiera „Always Allow" w oknie dostępu do klucza.

---

### Task 9: Wydanie `v0.1.0`, instalacja, próba aktualizacji do `v0.1.1`

**Model:** Opus. Wymaga **STOP-U** przed każdym wydaniem. Warunek wejścia: T7 zakończone „tak" i repo `PUBLIC`; T8 wykonane; `master` zawiera `rename` i `sparkle`.

**Files:**
- Create: `docs/superpowers/reports/Y-odbior.md`
- Modify: `VERSION` (`0.1.1` w osobnym commicie przed drugim wydaniem)

- [ ] **Step 1: Suchy przebieg.** `scripts/release.sh 0.1.0 --dry-run` na `master` — wszystkie kontrole przechodzą (ścieżka certyfikatu, build, zip, appcast).
- [ ] **Step 2: STOP-U „wydaj v0.1.0".** Po zgodzie: `scripts/release.sh 0.1.0`. Sprawdź: `gh release view v0.1.0 --json isDraft,isLatest,assets`, `curl -fsSIL https://github.com/sharezz1/yascribe/releases/latest/download/appcast.xml` → 200 i `xmllint --noout` na pobranym pliku; pobrany zip ma długość i podpis zgodne z appcastem. Jeżeli adres feedu nie trafia w zasób (spec: decyzja „Przekierowanie"): popraw `SUFeedURL` (appcast w repo pod stałą ścieżką `raw.githubusercontent.com`), skasuj wydanie `v0.1.0` (`gh release delete v0.1.0 --cleanup-tag --yes`, to zatwierdzony zapasowy plan, nie wraca do użytkownika) i zbuduj `v0.1.0` od nowa; zainstalowana aplikacja nigdy nie ma niesprawdzonego adresu.
- [ ] **Step 3: Instalacja lokalnej paczki.** Upewnij się, że stara `MeetNotesApp` nie działa (`pgrep -x MeetNotesApp`; jeśli działa — poproś użytkownika o zamknięcie). `ditto .build/Yascribe.app /Applications/Yascribe.app` z paczki zbudowanej przez `release.sh` (nie z zipa z Releases; bez kwarantanny). Nie usuwaj starego `MeetNotes.app` ani `~/Library/Application Support/MeetNotes` (migracja przeniesie katalog sama).
- [ ] **Step 4: [UŻYTKOWNIK]** otwiera `/Applications/Yascribe.app`, udziela zgód TCC (mikrofon, dźwięk systemowy, kalendarz), odpowiada na ewentualne okno dostępu do starego klucza. Agent weryfikuje po stronie plików, nie pęku: `ls ~/Library/Application\ Support/Yascribe` ma `providers.json`, `sessions/`; `ls ~/Library/Application\ Support/MeetNotes` nie istnieje (przeniesiony); użytkownik potwierdza, że klucze działają albo wpisuje je ponownie (komunikat z T3).
- [ ] **Step 5: Druga wersja.** Commit `VERSION` = `0.1.1` (`git add VERSION && git commit -m "Wersja 0.1.1"`), push na `master` (przez PR, jeśli taka praktyka), `scripts/release.sh 0.1.1 --dry-run`; **STOP-U „wydaj v0.1.1"**; `scripts/release.sh 0.1.1`.
- [ ] **Step 6: Próba aktualizacji [UŻYTKOWNIK].** W Yascribe `0.1.0`: „Check for Updates…" → pojawia się `0.1.1` → „Install"; aplikacja restartuje się; `defaults read /Applications/Yascribe.app/Contents/Info CFBundleShortVersionString` = `0.1.1`; dane i klucze nietknięte (te same sesje, notatki), zgody TCC nie wracają do pytań (ten sam podpis i bundle ID).
- [ ] **Step 7: Test nagrania podczas aktualizacji (anty-cel; wymaga trzeciego wydania lub powtórzenia kroków 5–6 z `0.1.2`).** Użytkownik zaczyna krótkie nagranie w `0.1.1`, agent wydaje `0.1.2` (**STOP-U**), użytkownik klika „Install" w trakcie nagrania: restart ma się **odroczyć** do końca nagrania, a po „Stop" aplikacja się restartuje; sesja z nagrania ma komplet torów (`session-summary`). Drugi sprawdzian: ⌘Q w trakcie nagrania jest odmówione z alertem.
- [ ] **Step 8: Odbiór.** `docs/superpowers/reports/Y-odbior.md` (co zmierzono, czego nie, wynik kroków 2, 4, 6, 7; macierz pęku z T0 vs rzeczywistość); commit `git add docs/superpowers/reports/Y-odbior.md && git commit -m "Odbiór Yascribe: instalacja i aktualizacja przez Sparkle"`. **[UŻYTKOWNIK]** usuwa starą pozycję `meetnotes.provider` w Keychain Access i stary `MeetNotes.app` (jeśli istnieje) — agent nie dotyka pęku.

---

### Task 10: Dokumenty żywe i artefakt

**Model:** Haiku. Po T9.

**Files:**
- Modify: `CLAUDE.md` (sekcja „Stan": Yascribe-rename i Sparkle; „Twarde zasady": Sparkle drugi pin, reguła jednego modułu `YascribeUpdates`; „Uruchamianie": `scripts/release.sh`, instalacja z `/Applications`, uwaga „wydanie na polecenie »wydaj«"), `docs/superpowers/ROADMAP.md`, `docs/superpowers/BACKLOG.md` (odłożone: notaryzacja, delta, nazwa „Yascribe model"), `docs/wymagania.md` (aktualizacje, Developer ID jako przyszłość)
- Artefakt „Mapa faz Yascribe" (`https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz`): faza rename i Sparkle, liczba testów (761), tagi

- [ ] **Step 1: Edycje dokumentów** wg listy; `scripts/check-hashes.sh` → 0; commit jawnymi ścieżkami (`git add CLAUDE.md docs/superpowers/ROADMAP.md docs/superpowers/BACKLOG.md docs/wymagania.md && git commit -m "Dokumenty: stan po rename i Sparkle"`).
- [ ] **Step 2: Artefakt.** `Artifact` read → edycja → publikacja pod tym samym URL (polecenie użytkownika z 2026-10-21, `CLAUDE.md`).
- [ ] **Step 3: Pamięć projektu.** Zaktualizuj lub dopisz wpisy pamięci (lokalizacja checkoutu zmieniona na `/Users/michalprzytulski/yascribe`; archiwum `sharezz1/meetnotes`).

---

## Samoprzegląd (wykonany przy pisaniu)

- **Pokrycie speca:** każda sekcja ma zadanie (tabela „Co robi którą część listy"); poprawki Codexa 1–12 mają miejsca: 1 → T4 kroki 1, 4 i T9 krok 7; 2 → T3 (reguła `.devdata` nieimportowane: T2 krok 4 nie zmienia semantyki, T3 pomija migrację przy `YASCRIBE_DATA_DIR`); 3 → T0 B, T3; 4 → T3 krok 5; 5 → T6; 6 → T7; 7 → T0, T5; 8 → T0 krok 7, T5 krok 5; 9 → T6 (7)–(8); 10 → T5; 11 → T5, T6; 12 → T1 przed T2.
- **Liczby testów:** 744 (T2) → 756 (T3, +12) → 761 (T4, +5); T5 i T6 bez nowych `@Test`.
- **Spójność nazw:** `DataDirectoryMigration`, `KeyMigration`, `KeyMigrationMarker`, `RestartGate`, `RecordingActivity`, `UpdateController` używane jednolicie w T3–T4.
- **Odstępstwo od speca (do wiadomości użytkownika):** spec mówi „publiczne repo, potem wydanie"; plan dodaje wprost, że wydania ze szkicem weryfikuje `gh release download` (szkic nie jest publiczny), a pierwsza publikacja jest po T7 — bo Sparkle nie pobierze zasobu z prywatnego repo.
