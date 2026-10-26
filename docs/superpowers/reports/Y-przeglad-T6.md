# Y-T6: przegląd skryptów wydania (T4–T6, gałąź `sparkle`)

Data: 2026-10-26. Zakres: `YascribeUpdates` + `RestartGate` (T4), osadzanie Sparkle w `bundle.sh` (T5), `release.sh`, `release-lib.sh`, `make-appcast.sh`, `check-release.sh` (T6). 766/766, `check-bundle` OK, `check-release` 13 przypadków. Przegląd read-only wykonał advisor; poprawki wprowadził agent.

## Pytania planu

| Pytanie | Odpowiedź |
|---|---|
| Czy któraś ścieżka wypuści wydanie bez podpisu EdDSA lub z ad-hoc? | Nie, przy zastrzeżeniu niżej. Pusty podpis albo długość z `sign_update` kończy się odmową (przypadek `missing-signature-rejected`); podpis ad-hoc też (`adhoc-signature-rejected`, mutacja a). Znaleziona luka: kod HTTP 22 (404 feedu) traktowany jako „pierwsze wydanie" razem z pustym `MAXV` wyłączał bramkę rosnącego builda; przy prywatnym repo anonimowy `releases/latest/download/appcast.xml` zwraca 404 zawsze. **Poprawione:** przy pustym feedzie `release.sh` odmawia, jeśli zdalnie są już tagi `v*` (przypadek `empty-feed-with-existing-releases-rejected`, mutacja reguły go zabija). Pierwsze wydanie (brak tagów `v*`) przechodzi. |
| Czy klucz lub token trafia do logu? | Nie. Brak `set -x`; `sign_update` drukuje tylko publiczny podpis i długość; `gh` pisze URL-e na stderr; skrypt niczego nie wypisuje poza komunikatami `release:`. |
| Czy test skryptu może dotknąć sieci, kluczy lub rekurencyjnie `test.sh`? | Nie. Wszystkie sześć wykonawców jest podstawionych (`YASCRIBE_TEST_CMD` = atrapa, więc łańcuch `test.sh → check-release.sh → release.sh → test.sh` nie istnieje); `git ls-remote` i `push` idą do lokalnego bare „origin" w katalogu `mn-relcheck.*`; `curl`, `gh`, `sign_update`, `codesign`, `security` nie są wołane. |

## Mutacje

- T4 (`RestartGate`): (a), (c), (d), (e) padają jak w planie. **(b) jest mutantem równoważnym:** `activityDidChange` ma dwie niezależne ochrony przed podwójnym wywołaniem bloku (`phase == .restartPostponed` i `held = nil`); usunięcie jednej nie zmienia zachowania. Zabija ją dopiero usunięcie obu naraz (sprawdzone: `releasesBlockExactlyOnceWhenActivityEnds` pada).
- T5 (`bundle.sh`): bez usunięcia `XPCServices` i bez rpath → `check-bundle.sh` pada.
- T6 (`release-lib.sh`): (a) bez kontroli ad-hoc, (c) `release edit` przed porównaniem sum, (d) bez `--target`, (e) bez porównania wersji z paczki → padają. **(b) `>` → `>=` przeżyła** (feed testowy miał 999, a build testowy 1, więc obie wersje odmawiały); dodano przypadek granicy (feed = bieżący build) i teraz pada.
- Pułapka testowa: po mutacji skryptu budującego trzeba przebudować paczkę. Pierwsza próba kroku 5 T5 użyła paczki zostawionej przez mutację „bez rpath" i poprawnie się wywróciła (`dyld: Library not loaded`); po przebudowie przeszła.

## T5 krok 5: rozpakowana kopia

Paczka ad-hoc zbudowana przez `check-bundle.sh` rozpakowana (`ditto`) do scratchpada, `.build` odsunięty, uruchomiony bezpośrednio plik wykonywalny z `YASCRIBE_DATA_DIR` i `YASCRIBE_MODEL_STORE` w pustych katalogach: `otool -L` wskazuje `@rpath/Sparkle.framework/Versions/B/Sparkle` (2.9.2), rpath `@executable_path/../Frameworks` jest, proces żył po 4 s i został zamknięty po PID (`kill`, nie `pkill`). Sparkle w tym uruchomieniu nie startuje (tryb deweloperski), więc sprawdzono ładowanie biblioteki, nie sam updater; samoczynny restart po aktualizacji sprawdza T9.

## Uwagi i decyzje

1. **Klucz publiczny a prywatny (T8).** Nic nie sprawdza, że `SUPublicEDKey` z `Info.plist` pasuje do klucza, którym podpisuje `sign_update`. Przy niezgodności v0.1.0 opublikuje się bez błędu, a każda zainstalowana kopia odrzuci każdą późniejszą aktualizację (naprawa tylko ręczną reinstalacją). `generate_keys -p` drukuje istniejący klucz publiczny; T8 powinno porównać go z `Info.plist` przed pierwszym wydaniem.
2. **Placeholder klucza przy starcie.** Aplikacja nie startuje Sparkle, dopóki `SUPublicEDKey` jest `REPLACE_WITH_PUBLIC_KEY` (warunek w `AppModel.init`); w przeciwnym razie połączone `sparkle` pokazywałoby błąd przy każdym prawdziwym uruchomieniu do czasu T8.
3. **`gh release download` szkicu.** Nieudowodnione offline, czy `gh release download v…` znajduje szkic, którego tag jeszcze nie istnieje. Zawodzi bezpiecznie (odmowa przed publikacją, szkic zostaje); do sprawdzenia w T9.
4. **Zacieśnienie testów (opcjonalne).** Przypadki „odmowa" przechodzą przy dowolnym kodzie ≠ 0; mogłyby dodatkowo grepować oczekiwany komunikat `release:`. Mutacje pokrywają bramki, więc zostawione.
5. Gałąź `sparkle` założona od `rename` (nie od `master`, bo `rename` nie jest scalony). Po scaleniu `rename` PR `sparkle` pokaże tylko swoje commity.
