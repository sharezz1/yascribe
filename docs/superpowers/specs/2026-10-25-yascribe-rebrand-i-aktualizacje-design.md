# Yascribe: pełny rename i aktualizacje przez Sparkle — projekt

Data: 2026-10-25. Punkt startowy: `master` po scaleniu Fazy 2.1 (`fb6477a`).

## Po co

Użytkownik uruchamia dziś aplikację tylko przez agenta (`scripts/run.sh`). Chce mieć ją **zainstalowaną** w `/Applications`
i **przycisk aktualizacji**: agent buduje i wypycha wydanie, użytkownik klika „Download" i ma nową wersję. Przy okazji produkt
dostaje docelową nazwę **Yascribe** (w interfejsie już jest; reszta mówi jeszcze MeetNotes), żeby instalować raz, pod nazwą ostateczną.

## Cele

- `Yascribe.app` instalowana raz, aktualizowana z poziomu aplikacji (Sparkle 2).
- Agent wydaje wersję jednym poleceniem (`scripts/release.sh`); użytkownik niczego nie buduje.
- Pełny rename: moduły i produkty SwiftPM, nazwa aplikacji, bundle ID, katalog danych, usługa pęku kluczy, zmienne środowiskowe, repo GitHub.
- Istniejące dane i klucze API użytkownika przechodzą na nową nazwę bez ręcznej pracy.
- Repo staje się publiczne, a wydania i `appcast.xml` leżą w jego GitHub Releases.

## Poza zakresem

- Notaryzacja i Developer ID (podpis zostaje samopodpisany; Sparkle chroni paczkę podpisem EdDSA).
- Aktualizacje różnicowe (delta), kanały beta, wymuszone aktualizacje, automatyczna instalacja bez kliknięcia.
- Przepisywanie historycznych dokumentów (`docs/superpowers/specs|plans|reports|spikes`): zostają ze starą nazwą jako zapis z epoki.
  Dotyczy też `docs/design/inspiracje/`. Zmieniamy tylko dokumenty żywe: `CLAUDE.md`, `ROADMAP.md`, `BACKLOG.md`, `docs/design/macos.md`, `docs/wymagania.md`.
- Nowe funkcje aplikacji. Jedyna zmiana w UI: pozycja „Check for Updates…" i przycisk w Settings.

## Anty-cele (porażka, nawet jeśli „działa")

- Aktualizacja przerywa trwające nagranie. Restart po aktualizacji musi czekać na koniec nagrania.
- Utrata danych lub kluczy API przy pierwszym starcie pod nową nazwą.
- Klucz prywatny EdDSA lub token GitHub w repo, w logu albo w czacie.
- Wydanie bez podpisu EdDSA, które aplikacja mimo to przyjmie.

## Ograniczenia

- Toolchain: Swift 6.4, tylko Command Line Tools, bez Xcode; `swift-testing`; testy wyłącznie `scripts/test.sh` (po rename liczba testów ma pozostać **744**).
- SwiftPM pobiera `binaryTarget` tylko z `--disable-keychain`; skrypty już to robią.
- SwiftUI bez `@State`/`@Entry`/`#Preview`; nowe pola w zapisywanych typach tylko opcjonalne.
- Klucze API wpisuje wyłącznie użytkownik. Klucz EdDSA generuje użytkownik własnym poleceniem (`generate_keys` ląduje w jego pęku login).
- Nie zmieniamy Ustawień systemowych ani TCC. Zmiana bundle ID **resetuje zgody** (mikrofon, dźwięk systemowy, kalendarz) — użytkownik udziela ich raz po pierwszej instalacji.
- CLAUDE.md: Sparkle będzie drugim zewnętrznym pinem (obok FluidAudio); reguła „importuje wyłącznie jeden moduł" dotyczy też Sparkle (jeden moduł `YascribeUpdates`).

## Podejścia (rozważone)

**A. Sparkle 2 + Releases w tym samym (publicznym) repo — wybrane przez użytkownika.** Menu i okno aktualizacji gotowe, podmiana aplikacji
sprawdzona w boju, podpis EdDSA. Koszt: zależność i osadzenie `Sparkle.framework` w `bundle.sh` przy samych CLT — to jedyne ryzyko, stąd spike S0 na początku.
**B. Własny updater** (`releases/latest` z API, zip, suma, podmiana skryptem). Odrzucony: sami piszemy krytyczną, łatwą do zepsucia część.
**C. Prywatne repo + token w aplikacji.** Odrzucony: użytkownik zgodził się na publiczne repo, a token to ciągła obsługa.
Gdyby S0 dał NO-GO, wracamy do użytkownika z wariantem B; nie przechodzimy na niego sami.

## Decyzje użytkownika

- Publiczne repo; wydania i appcast w nim. Pełny rename (nie tylko nazwa widoczna). Sparkle (wariant A).
- Nazwa produktu: **Yascribe**. Repo: nowe `sharezz1/yascribe` (nie zmiana nazwy obecnego; patrz O1). Faza 2.1 scalona przed rename.

## Projekt (część moja; użytkownik zatwierdza razem z dokumentem)

### 1. Rename (zadanie osobne, przed aktualizacjami)

Jeden mechaniczny commit na gałęzi, potem poprawki. Zakres (158 plików z `MeetNotes` w `Sources`/`Tests`):

| Było | Jest |
|---|---|
| moduły/targety `MeetNotes*` (Recording, SessionFormat, Providers, LocalASR, Transcription, Notes, Meetings, App) | `Yascribe*` |
| `meetnotes-cli` | `yascribe-cli` |
| plik wykonywalny `MeetNotesApp`, `CFBundleExecutable` | `YascribeApp` |
| `MeetNotes.app`, `CFBundleName/DisplayName` | `Yascribe.app`, „Yascribe" |
| bundle ID `io.github.sharezz1.meetnotes` | `io.github.sharezz1.yascribe` |
| `~/Library/Application Support/MeetNotes` | `…/Yascribe` |
| `MEETNOTES_DATA_DIR`, `MEETNOTES_MODEL_STORE`, `MEETNOTES_APP`, `MEETNOTES_SIGN_IDENTITY` | `YASCRIBE_*` |
| usługa pęku `meetnotes.provider` | `yascribe.provider` |
| teksty zgód w `Info.plist` | „Yascribe …" |

Moje decyzje (do sprawdzenia):
- **Certyfikat podpisu zostaje „MeetNotes Dev"** (nazwa wewnętrzna, niewidoczna; nowy certyfikat wymagałby ruchu w pęku użytkownika). `bundle.sh` przyjmuje `YASCRIBE_SIGN_IDENTITY` z domyślną starą nazwą.
- Zmiennych `MEETNOTES_*` nie zostawiamy jako aliasów: skrypty i dokumenty żywe zmieniamy razem.
- `scripts/check-hashes.allow` i hook pre-commit zostają działające; hashe w historycznych raportach się nie zmieniają, bo ich nie edytujemy.
- Nazwy plików/typów `MeetNotesPaths` → `YascribePaths` itd. w jednym przebiegu; po rename `scripts/test.sh` = 744/744 jest warunkiem zakończenia.

### 2. Migracja przy pierwszym starcie (kod aplikacji)

- **Dane:** jeśli `Yascribe/` nie istnieje, a `MeetNotes/` istnieje — przenieś katalog (`FileManager.moveItem`, ten sam wolumin, atomowo). Nie uruchamiaj przy ustawionym `YASCRIBE_DATA_DIR`. Brak kopii: to zmiana nazwy katalogu, nic nie jest kasowane ani przepisywane. Błąd przeniesienia = jawny komunikat, aplikacja nie startuje na pustym katalogu.
- **Klucze API:** dla każdego dostawcy, jeśli nowa usługa `yascribe.provider` nie ma klucza, a stara `meetnotes.provider` ma — skopiuj do nowej. Starej pozycji **nie usuwamy** (użytkownik usunie ją sam w Keychain Access). Odczyt starej działa, bo podpis jest ten sam.
- Testy z fałszywym katalogiem i fałszywym magazynem kluczy (literały `test-fake-…`); mutacja każdej bramki.

### 3. Sparkle

- Zależność `Sparkle` (`from`/`exact` na wersji z maja 2026 lub starszej, jak przy FluidAudio — pin dokładny), jeden moduł `YascribeUpdates` ją importuje; reszta aplikacji widzi tylko `UpdateController` (`checkForUpdates()`, `canCheck`, `postponeRestart`).
- `bundle.sh`: osadza `Sparkle.framework` w `Contents/Frameworks`, podpisuje od środka (framework, potem aplikacja; bez `--deep`), `rpath` `@executable_path/../Frameworks`. Aplikacja nie jest w sandboxie, więc usługi XPC Sparkle można pominąć.
- `Info.plist`: `SUFeedURL` = `https://github.com/sharezz1/yascribe/releases/latest/download/appcast.xml` (stały adres, przekierowuje na zasób ostatniego wydania, więc appcast nie leży w repo), `SUPublicEDKey`, `SUEnableAutomaticChecks` = true (sprawdza w tle raz dziennie), `SUAutomaticallyUpdate` = false (instalacja po kliknięciu).
- UI: „Check for Updates…" w menu aplikacji oraz przycisk i wersja w Settings. Anglojęzyczne, zgodnie z regułą języka interfejsu.
- **Nagrywanie:** delegat Sparkle odracza restart (`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`), dopóki `RecordingController` nagrywa lub zapisuje; po zakończeniu wywołuje blok.
- Numeracja: `CFBundleShortVersionString` semver (`0.1.0`…), `CFBundleVersion` = liczba commitów (`git rev-list --count HEAD`), rosnąca.

### 4. `scripts/release.sh <wersja>`

1. `git status` czysty, na `master`, testy zielone (`scripts/test.sh`).
2. `CONFIG=release scripts/bundle.sh` z wersją i buildem wpisanymi do `Info.plist`.
3. `ditto -c -k --keepParent` → `Yascribe-<wersja>.zip`.
4. Podpis EdDSA (`sign_update`, klucz z pęku użytkownika), zbudowanie `appcast.xml` z jednym wpisem (długość, podpis, wersje, minimalny system).
5. `gh release create v<wersja>` z zipem i `appcast.xml`; tag na bieżącym commicie.
Wydanie to działanie publiczne: agent wykonuje je na polecenie użytkownika („wydaj"), nie z własnej inicjatywy. Pierwszy `sign_update` pyta o dostęp do klucza w pęku — użytkownik wybiera „Always Allow".

### 5. Upublicznienie repo

Nowe repo zakładamy jako prywatne (`gh repo create sharezz1/yascribe --private`), wypychamy przepisaną historię (O1), a po audycie `gh repo edit --visibility public`. Przed zmianą widoczności agent skanuje historię i `docs/` pod kątem prawdziwych
fragmentów rozmów, kluczy i danych osobowych (stan na 2026-10-25: prawdziwych kluczy nie ma, tylko literały testowe; w commitach jest służbowy adres `[adres służbowy]`;
fixtury i raporty nieprzejrzane). Zmiana widoczności wymaga osobnego „tak" użytkownika.

### Spike S0 (pierwszy krok, wyrzucany)

Na kopii bieżącego kodu, bez rename: Sparkle w `bundle.sh` przy samych CLT, build + podpis „MeetNotes Dev", wersja `0.1.0` → `0.1.1` przez lokalny `appcast.xml`
(localhost). GO = aplikacja `0.1.0` widzi `0.1.1`, pobiera, weryfikuje EdDSA, podmienia się i startuje. NO-GO = wracamy do użytkownika z wariantem B. Wynik w `docs/superpowers/spikes/`.

## Kolejność

Faza 2.1 jest scalona i odebrana (PR #26, #28, #29; `master` = `fb6477a` w dniu decyzji), więc rename nie rozjeżdża żadnych gałęzi.

0. S0 (spike Sparkle + test pęku kluczy). 1. Przepisanie historii (usunięcie adresu służbowego) i **nowe repo** `sharezz1/yascribe`. 2. Rename + migracja. 3. Sparkle w aplikacji i `release.sh`. 4. Upublicznienie nowego repo. 5. Wydanie `v0.1.0`, instalacja w `/Applications`, drugie wydanie `v0.1.1` jako próba aktualizacji.

## Otwarte do użytkownika

- **O1 — historia a adres e-mail: ROZSTRZYGNIĘTE (2026-10-25).** Adres `[adres służbowy]` nie może trafić do publicznego repo (477 z 505 commitów).
  Decyzja użytkownika: przepisać historię i opublikować jako **nowe repo** `sharezz1/yascribe`; stare `sharezz1/meetnotes` zostaje prywatnym archiwum.
  Powód: referencje `refs/pull/N/head` 28 PR-ów w obecnym repo trzymają stare commity, więc przepisanie w miejscu nie usunęłoby adresu z GitHuba.
  Wykonanie: `git bundle` jako kopia zapasowa; `git filter-repo` (do doinstalowania: `brew install git-filter-repo`) z mapą autorów → `166069997+sharezz1@users.noreply.github.com`
  (imię i nazwisko autora zostaje, chyba że użytkownik zdecyduje inaczej); podmiana 202 cytowanych hashy w 84 plikach `.md` wg mapy stary→nowy w jednym commicie na wierzchu
  (to jedyny wyjątek od zakazu edycji dokumentów historycznych) i uzupełnienie `check-hashes.allow`; przepięcie 5 tagów; push do nowego repo tylko wybranych gałęzi (`master` i tagi);
  `git config user.email` w tym repo na noreply (globalny adres służbowy zostaje poza repo); usunięcie lub ponowny klon worktree `meetnotes-codex` i innych lokalnych kopii;
  ustawienie na GitHubie „Keep my email addresses private" i „Block command line pushes that expose my email".
- **O2 — po skanie** (§5): ewentualne fragmenty prawdziwych rozmów w fixturach/dokumentach.

## Moje decyzje po przeglądzie projektu (do sprawdzenia)

- **Klucze API nieczytelne po rename:** aplikacja nie pada; użytkownik wpisuje klucz ponownie (szczegóły i komunikat: poprawka 3 niżej). Test na fałszywym magazynie.
- **Oba katalogi mają dane:** blokujący alert (poprawka 4 niżej). Jeśli działa proces `MeetNotesApp`, migracja nie rusza katalogu (komunikat „quit the old MeetNotes first"). `.devdata/` i `run.sh` zostają, zmienia się tylko nazwa zmiennej na `YASCRIBE_DATA_DIR`.
- **Pierwsza instalacja:** agent kopiuje lokalnie zbudowane `Yascribe.app` do `/Applications` (bez kwarantanny, bez ostrzeżenia Gatekeepera). Aktualizacje Sparkle też nie dostają kwarantanny. Zip z Releases nie jest drogą pierwszej instalacji.
- **Przekierowanie `releases/latest/download`:** po opublikowaniu `v0.1.0`, **przed** instalacją, agent sprawdza `curl -IL` na adres feedu. Jeśli nie trafia w zasób, poprawia `SUFeedURL` (np. appcast w repo pod stałą ścieżką `raw.githubusercontent.com`), usuwa wydanie i buduje `v0.1.0` od nowa. Zainstalowana aplikacja nigdy nie ma więc niesprawdzonego adresu. To zatwierdzony zapasowy plan; nie wraca do użytkownika.
- **Klucz EdDSA:** użytkownik uruchamia `generate_keys` z artefaktu Sparkle pobranego przez SwiftPM (`.build/artifacts/sparkle/Sparkle/bin/`; S0 to potwierdza) i podaje agentowi klucz **publiczny** do `SUPublicEDKey`. `release.sh` woła `sign_update` z tego samego artefaktu; klucz prywatny zostaje w pęku użytkownika.
- **Testy:** 744 dotyczy tylko commitu z rename. Migracja i `UpdateController` dodają testy. Delegat odroczenia restartu jest testowany bez Sparkle, przez protokół w `YascribeUpdates`, który `RecordingController` podaje jako „czy trwa nagranie".
- **O1 rozstrzygamy przed rename** (poprawione po recenzji Codexa, pkt 12). Spike S0 i Sparkle w kodzie mogą iść wcześniej, ale rename i upublicznienie czekają na decyzję.
  Jeśli użytkownik wybierze przepisanie historii, robimy je przed rename, a migracja cytowanych hashy jest **jedynym wyjątkiem** od zakazu edycji dokumentów historycznych.
  O2 blokuje tylko krok 3 (upublicznienie).

## Poprawki po recenzji Codexa (`gpt-6.1-sol`, 2026-10-25)

Przyjęte w całości, o ile niżej nie zaznaczono inaczej:

1. **Restart:** poza odroczeniem w delegacie Sparkle wymagamy ochrony w `applicationShouldTerminate` (odmowa zamknięcia, gdy trwa nagranie lub zapis), blokady nowych nagrań w trakcie instalacji i testu rzeczywistego restartu (nie tylko protokołu).
2. **`.devdata`:** zostaje dev-only i nie jest importowane. Prawdziwe dane użytkownika leżą w `~/Library/Application Support/MeetNotes`; to je migrujemy. Jeśli użytkownik chce nagrania z `.devdata`, robi to osobnym, jawnym poleceniem (poza zakresem). Migracja zachowuje UUID dostawców, bo przenosi pliki bez zmian.
3. **Pęk kluczy:** przed rename (część S0) sprawdzamy na sprzęcie odczyt **prawdziwego testowego wpisu** `meetnotes.provider` z aplikacji o nowym bundle ID i tym samym certyfikacie. Brak dostępu pokazujemy jako „couldn't read the old key (access denied)", nie jako „no key"; wpisujemy klucz ponownie. Mój wcześniejszy zapis „no key" w sekcji decyzji jest tym zastąpiony.
4. **Migracja katalogu:** działa **przed** `AppModel.load()` i przed zapisem jakichkolwiek domyślnych plików. Pusty `Yascribe/` (bez znanych plików) traktujemy jak nieistniejący. Gdy oba katalogi mają dane — blokujący alert „Use Yascribe data / Quit"; nie wybieramy po cichu. To zastępuje mój wcześniejszy zapis „używa `Yascribe/` i pokazuje notkę".
5. **`release.sh` odrzuca podpis ad-hoc** i sprawdza tożsamość podpisu (`codesign -dr -`, oczekiwany certyfikat). `bundle.sh` ostrzegający i podpisujący ad-hoc jest OK dla dev, nie dla wydania.
6. **Audyt przed upublicznieniem** obejmuje też logi Actions, artefakty, dyskusje i PR-y, wszystkie gałęzie i tagi (nie tylko historię Git). Upublicznienie nie jest odwracalne w sensie kopii — dlatego osobne „tak" użytkownika.
7. **Podpisywanie Sparkle:** od środka — `Autoupdate`, `Updater.app`, ewentualne XPC (usuwamy, bo brak sandboxa), framework, aplikacja; na końcu `codesign --verify --strict --deep` całej struktury.
8. **S0 bez fałszywego GO:** test rozpakowanej kopii `.app` w innym katalogu, przy niedostępnym `.build`; sprawdzenie `otool -L` / `otool -l` (rpath), symlinków i praw wykonywania frameworka.
9. **Feed:** `release.sh` tworzy wydanie jako **draft** z kompletnym `appcast.xml`, sprawdza GET i poprawność XML, dopiero potem publikuje (zmienia „latest"); pełną kontrolę robi Sparkle w próbie `v0.1.0` → `v0.1.1`. Zastępuje to samo `curl -IL`.
10. **`SUAllowsAutomaticUpdates` = false** obok `SUAutomaticallyUpdate` = false, żeby UI Sparkle nie oferowało instalacji bez kliknięcia.
11. **Numer builda:** `CFBundleVersion` = liczba commitów, ale `release.sh` wymaga, by była **większa** od numeru ostatniego opublikowanego wydania (czytanego z feedu); wersja leży w pliku `VERSION` i jest podbijana własnym commitem, więc dwa wydania nigdy nie mają tego samego HEAD.
12. **Kolejność O1:** patrz wyżej.

## Zostawione wykonawcy

Wersja Sparkle (pin); szczegóły osadzania frameworka i podpisu; format `appcast.xml`; nazwy plików pomocniczych; treść komunikatów błędów migracji; układ przycisku w Settings.

## Niezmierzone / ryzyka

Osadzanie Sparkle przy CLT i samopodpisanym certyfikacie (S0); zachowanie przekierowania `releases/latest/download` w Sparkle (S0 sprawdza na localhost, nie na GitHubie — pełny test dopiero przy `v0.1.0` → `v0.1.1`);
dostęp starej pozycji pęku kluczy po zmianie bundle ID (ten sam certyfikat — do potwierdzenia na sprzęcie przy pierwszym starcie).
