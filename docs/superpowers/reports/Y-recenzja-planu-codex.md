# Recenzja planu Yascribe (Codex `gpt-6.1-sol`, 2026-10-25) — uwagi i decyzje

Plan: `docs/superpowers/plans/2026-10-25-yascribe-rebrand-i-aktualizacje.md`. Polecenie: `codex exec -m gpt-6.1-sol -s read-only --skip-git-repo-check`. Codex potwierdził arytmetykę testów (744 → 756 → 761 była poprawna dla pierwotnych list) i znalazł 15 uwag. **Wszystkie przyjęte** i wprowadzone; liczby testów zmieniły się przez nowe przypadki (patrz 14): 744 → 759 → 766.

| # | Uwaga (skrót) | Co zrobiono |
|---|---|---|
| 1 | Nowe commity w T1 powstają, zanim ustawiony jest noreply (globalny adres służbowy) | T1 krok 3: lokalny `user.email`/`user.name` w klonie przed pierwszym commitem; krok 9: kontrola wszystkich wysyłanych referencji |
| 2 | T7 zakłada „świeże repo"; po PR-ach z T3/T6 referencje PR zachowają stare commity, gdyby O2 wymusił przepisanie | T1 krok 8: audyt treści **przed pierwszym pushem**; T7 krok 3 przepisany (PR-y, gałęzie), konsekwencja O2 = kolejne nowe repo |
| 3 | Rekurencja `test.sh → check-release.sh → release.sh → test.sh`; atrapy niepełne | T6: `release-lib.sh` z podstawialnymi wykonawcami (test, bundle, sign_update, gh, fetch, tożsamość, zdalny HEAD); test skryptu używa atrap, w tym `YASCRIBE_TEST_CMD=true` |
| 4 | T0/T5 mogą dotknąć prawdziwych danych; `pkill -x` zabije cudze nagranie; T0 jeszcze na `MEETNOTES_*` | T0 krok 4 i T5 krok 5: izolowane katalogi danych i modelu, start pliku wykonywalnego z PID i `kill <pid>`; `pkill` zabroniony |
| 5 | `markDone` po odmowie utrwala niedokończoną migrację; brak rozróżnienia błędu zapisu nowej usługi; kasowanie starej usługi | T3: rejestr per UUID (`KeyMigrationLedger`), `unreadable`/`newStoreFailed` ponawiane, nowy wynik `newStoreFailed`; T9: usuwanie starej pozycji tylko po weryfikacji, stara usługa może mieć klucze spoza `providers.json` |
| 6 | `Authority=` bywa `(unavailable)` dla certyfikatu samopodpisanego | T0 krok 11 potwierdza metodę; T6 punkt 5: `codesign -dr -` (odcisk certyfikatu = SHA-1 z `security find-identity`, bundle ID), brak `Signature=adhoc` |
| 7 | Niepełny cykl blokady nagrywania, brak odblokowania po błędzie, callback odroczenia może nie nadejść | T4: `UpdatePhase` (`idle/installing/restartPostponed`), `installationEnded()` po błędzie/anulowaniu, wspólne `canBeginRecording()`, `applicationShouldTerminate` jako druga bariera; nowe testy |
| 8 | Kontrakty współbieżności Swift 6 nieuzgodnione, `NSLock` | T4: wszystko `@MainActor`, bez `NSLock`; T0 krok 4 sprawdza kompilację wzoru |
| 9 | Tag może wskazywać inny kod niż paczka; wersje z odziedziczonych zmiennych | T6: lokalny HEAD = zdalny `master`, `--target <SHA>`, wersje czytane z gotowej paczki, `release.sh` czyści `YASCRIBE_BUILD/VERSION` |
| 10 | Test kolejności nie wykryje mutacji; długość ≠ zgodność bajtów; `isLatest` nie istnieje w `gh release view` | T6: kolejność create → download → porównanie `sha256` → publish, test `publish-refused-when-draft-bytes-differ`; „latest" przez `gh api …/releases/latest`; T9 poprawiony |
| 11 | Podmiana hashy pomija `CLAUDE.md`, hashe w poleceniach i URL-ach; UUID sesji | T1 krok 6: inwentarz wszystkich referencji (także `CLAUDE.md`, URL-e), pomijanie tokenów niebędących commitami (`git cat-file`), weryfikacja polecenia cofnięcia |
| 12 | Sprzeczna kolejność kroków T1, brak przeniesienia narzędzia | T1 krok 7: jawna kolejność (master → merge planu → narzędzie → mapowanie → jeden commit → weryfikacja z nową liczbą commitów); liczba commitów liczona z różnicą |
| 13 | Sonda pęku używa usługi `meetnotes.s0test`, nie prawdziwej `meetnotes.provider` | T0 kroki 9–10: wpis tworzy prawdziwa stara aplikacja (dostawca „S0 test" w izolowanym katalogu danych), nowa paczka czyta ten UUID, użytkownik usuwa wyłącznie ten wpis |
| 14 | Brakujące przypadki testów i mutacji; sztywne 761 | T3: +`dataDirOverrideIsDetected`, `newKeyWriteFailureIsReportedSeparately`, `resolvedKeysAreNotRechecked`, `unresolvedKeysAreRetriedOnNextRun` (15 testów); T4: +`installFailureReleasesRecordingBlock`, `recordingStartBlockedDuringPostponedRestart` (7); mutacje (d), (e); wartości końcowe przeliczane greppem; odbiór alertów w T9 jawnie oznaczony jako niezmierzony tam, gdzie nie da się go wywołać bez zmiany danych |
| 15 | Artefakt aktualizowany dopiero w T10 wbrew `CLAUDE.md` | Aktualizacja artefaktu po zamknięciu T3, T6, T9 i po merge `rename`; T10 to kontrola spójności |

**Niezweryfikowane przez Codexa ani mnie:** kroki T0 (zachowanie Sparkle bez Xcode, odczyt pęku po zmianie bundle ID) i `git filter-repo` — dopiero wykonanie.
