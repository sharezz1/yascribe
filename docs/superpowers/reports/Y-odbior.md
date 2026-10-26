# Y-T9: odbiór Yascribe (instalacja i aktualizacja przez Sparkle)

Data: 2026-10-26. Repo `sharezz1/yascribe` (publiczne), `master` po PR #1–#8. Wydania: `v0.1.0` (build 536, commit `7c0f7e4`) i `v0.1.1` (build 540, commit `918183e`).

## Co zmierzono

| Krok | Wynik |
|---|---|
| 1. Suchy przebieg `release.sh 0.1.0 --dry-run` | Najpierw padł na realnym błędzie: `curl` zwraca kod 56 (nie 22) dla 404 po przekierowaniu (feed jeszcze nie istnieje), więc „pierwsze wydanie" brane było za awarię sieci. Poprawione (PR #5, `fetch_feed` czyta kod HTTP). Drugi przebieg: kroki (1)–(7) przeszły, `sign_update` podpisał bez okna dostępu do klucza. |
| 2. Wydanie `v0.1.0` | Opublikowane (szkic → pobranie → sumy zgodne → publikacja). Zasoby zip (13 137 431 B) i `appcast.xml` odpowiadają 200. Feed `releases/latest/download/appcast.xml` dał 404 tuż po publikacji i skrypt zakończył z błędem, choć wydanie było poprawne; po kilkunastu sekundach 200. Appcast to poprawny XML, build 536, `length` zgodne z zipem; podpis EdDSA przechodzi `sign_update --verify` (zepsuty daje kod 1). Plan T9 przewidywał na 404 kasowanie i budowę od nowa; niepotrzebne, bo to opóźnienie propagacji. |
| 3. Instalacja | `ditto .build/Yascribe.app /Applications/Yascribe.app` z paczki zbudowanej przez `release.sh`; `codesign --verify --strict --deep` OK. Kopii zapasowej nie robiono (użytkownik nie potrzebuje starych danych; `MeetNotes` miał 8 KB). |
| 4. Pierwszy start (użytkownik) | Aplikacja wystartowała bez błędów i alertów. Po stronie plików: `~/Library/Application Support/MeetNotes` nie istnieje (przeniesiony), `…/Yascribe` ma `providers.json` (zachowana data sprzed migracji) i `legacy-migration.json` (jeden dostawca rozstrzygnięty). Migracja T3 zadziałała na prawdziwych danych. Ścieżek alertów `bothHaveData` i `oldAppRunning` nie wywoływano (wymagałoby zmiany prawdziwych danych): niezmierzone. |
| 5. Wydanie `v0.1.1` | `VERSION` = `0.1.1` osobnym commitem (PR #8), dry-run OK, wydanie opublikowane. Feed serwował stary appcast `0.1.0` jeszcze ponad minutę po publikacji (60 s ponawiania nie wystarczyło, skrypt zakończył z błędem po publikacji); po ok. 70–120 s feed pokazał `0.1.1` (build 540). Zip 13 137 449 B zgodny z appcastem, podpis EdDSA przechodzi `--verify`. Limit ponawiania podniesiony do 36 × 5 s. |
| 6. Próba aktualizacji (użytkownik) | W zainstalowanym `0.1.0`: „Check for Updates…" znalazło `0.1.1`, instalacja i „Install and Relaunch" przeszły, aplikacja zrestartowała się sama. Po stronie plików: `CFBundleShortVersionString` = `0.1.1`, `CFBundleVersion` = 540, `codesign --verify --strict --deep` OK, to samo designated requirement (identifier i odcisk certyfikatu), więc zgody TCC zostają. Dane (`providers.json`, `presets.json`, `settings.json`) są. Dowodzi też, że klucz publiczny w aplikacji pasuje do klucza prywatnego (Sparkle przyjął podpis). |

## Czego nie zmierzono

- **Krok 7 (aktualizacja w trakcie nagrania, ⌘Q w trakcie nagrania):** wymaga trzeciego wydania (`0.1.2`) i osobnego „wydaj"; nie wykonane. Testy jednostkowe `RestartGate` i poprawka zamknięcia po finalizacji (PR #6) pokrywają logikę, ale nie przepływ na żywo.
- Alerty migracji `bothHaveData` i `oldAppRunning` oraz okno odmowy dostępu do klucza („Deny", kod `OSStatus` nadal umowny).
- Samoczynny restart sprawdzono raz (jedno uruchomienie, natychmiastowy); niewyjaśnione z S0 zachowanie bez delegata aplikacji nie wystąpiło.

## Macierz pęku (T0) a rzeczywistość

T0: odczyt klucza starej usługi z nowego bundle ID wymaga zgody w oknie macOS. Rzeczywistość: katalog danych starej aplikacji miał tylko rekord modelu lokalnego (bez kluczy API), więc przy pierwszym starcie nie było czego odczytywać i okno się nie pojawiło. Ścieżka kopiowania kluczy z pęku na prawdziwych kluczach nie była więc wykonana w T9.

## Po stronie użytkownika

Usunięcie starej pozycji `meetnotes.provider` w Keychain Access i starego `~/Applications/MeetNotes.app`, dopiero po sprawdzeniu, że każdy używany dostawca działa z kluczem w nowej usłudze (stara usługa może zawierać klucze spoza `providers.json`). Agent pęku nie rusza.

## Uwagi do `release.sh`

Propagacja feedu po publikacji trwa 1–2 minuty (nie kilkanaście sekund); skrypt kończy wtedy z błędem po poprawnej publikacji. Zalecenie dla kolejnych wydań: nie traktować błędu kroku (9) jako błędu wydania bez sprawdzenia `gh api repos/sharezz1/yascribe/releases/latest` i feedu po kilku minutach.
