# Y-T1: przepisanie historii do nowego repo `sharezz1/yascribe`

Data: 2026-10-26. Plan: `docs/superpowers/plans/2026-10-25-yascribe-rebrand-i-aktualizacje.md` (T1). Stare repo (`/Users/michalprzytulski/meetnotes`) nietknięte.

## Co zrobiono

| Krok | Wynik |
|---|---|
| Kopia zapasowa | `meetnotes-przed-przepisaniem.bundle` (20,3 MB, `git bundle verify`: „is okay", 77 referencji) w scratchpadzie sesji `eddafc7d…/scratchpad/` |
| Klon do przepisania | `git clone --no-local` → `…/scratchpad/rewrite` (po pierwszej próbie `rewrite-v1`, odrzuconej po decyzji O2) |
| Mailmap | `Michał Przytulski <166069997+sharezz1@users.noreply.github.com> <[adres służbowy]>` (imię zostaje) |
| Zamiana tekstu (`--replace-text`) | adres służbowy → `[adres służbowy]` (tylko w plan/spec Yascribe, które go cytowały); `[Audio] yarrl & BNP synch` → `[spotkanie testowe]`; `Daily BNP - Voice` → `[spotkanie dzienne]`; `jak Yarrl` → `jak [firma]` |
| Usunięcie plików (`--invert-paths`) | 12 × `docs/design/inspiracje/granola-*.png`, 3 × `docs/design/inspiracje/wispr-flow-*.png` (decyzja O2, patrz niżej); `git log --all -- <te ścieżki>` = 0 |
| Scalenie planu | `docs/yascribe-rebrand-plan` → `master` (`--ff-only`) |
| Podmiana hashy | `scripts/rewrite-hashes.py`: 193 tokeny w 76 plikach, 0 niejednoznacznych; commit „Hashe po przepisaniu historii (stary → nowy wg mapy)" |
| Notka o zrzutach | `granola.md`, `wispr-flow.md`: informacja, że zrzuty usunięto; osobny commit |

## Liczby

| | przed | po |
|---|---|---|
| commity `--all` (klon, wszystkie gałęzie) | 512 | 514 (+ commit podmiany hashy i notki) |
| commity `master` | 507 w starym `master`; 512 po scaleniu planu | 514 |
| e-mail autora/committera `[adres służbowy]` | 483 commity (966 wpisów) | 0 |
| autor/committer | 29 × noreply, 29 × `noreply@github.com` (scalenia GitHuba) | 485 × `166069997+sharezz1@users.noreply.github.com`, 29 × committer `noreply@github.com` |
| tagger tagów | `<[adres służbowy]>` | `<166069997+sharezz1@users.noreply.github.com>` |
| treść commitów z domeną służbową | 0 | 0 |
| bloby z adresem służbowym | plan i spec Yascribe | 0 |

`commit-map` (stary → nowy, 513 wierszy z nagłówkiem): `…/scratchpad/commit-map`. Zrzut wyjścia podmiany hashy: `…/scratchpad/rewrite-hashes.out`.

Tagi (5): `faza-1.5`, `faza-1.5a`, `faza-1.5b-wyciszanie`, `faza-1.6`, `faza-2.0` wskazują commity o tych samych tematach co w starym repo (sprawdzone `git log -1 --format=%s`). Polecenie cofnięcia w `CLAUDE.md` wskazuje istniejący commit.

W klonie zostają lokalne gałęzie ze starego repo (ok. 40); **do nowego repo idą wyłącznie `master` i 5 tagów** (krok 9).

## Audyt treści przed pierwszym pushem (T7 kroki 1–2)

**Skan Git (master + tagi):**
- klucze (`sk-…`, `or-v1-`, `xi-api-key`, `Bearer`, `ghp_`, `-----BEGIN`): tylko literały testowe (`sk-or-v1-SECRET123`, `sk-or-v1-abcdef1234`) i same wzorce w tekście planów; prawdziwych kluczy brak;
- adresy e-mail: `166069997+sharezz1@users.noreply.github.com`, `noreply@anthropic.com`, `noreply@deepseek.com`, `git@github.com`, adresy `example.com` i inne atrapy z testów;
- `/Users/michalprzytulski` w śledzonych plikach: 10 plików (`docs/superpowers/plans`, `reports`, `specs`, `docs/wymagania.md`): ścieżki katalogu domowego, bez innych danych; do decyzji w T7 (zostawić czy zamienić na `~`);
- nazwy: `InPost` w 6 plikach (przykłady słownika, fixtury migawek, tytuł wydarzenia „The real InPost daily" w `F16-odbior.md`), `Genesys` w 19 plikach (nazwa produktu); `yarrl` pozostaje tylko w tekście plan T1/T7 (polecenia skanu i lista domyślnych nazw), `BNP` w plikach tekstowych: 0. Nie zmieniano.

**Zrzuty (`docs/design/inspiracje/` i `makiety/`):** obejrzano wzrokowo 24 pliki z `inspiracje/`:
- **trafione, usunięte z historii (O2):** `granola-menu-i-pigulka.png` (prywatny Gmail, zdjęcie profilowe), `granola-notatka.png`, `granola-szablony.png`, `granola-wybor-jezyka.png` (pełne nazwisko osoby trzeciej), `wispr-flow-podsumowanie-1.png` (nazwisko pracownika), `wispr-flow-podsumowanie-2.png`, `wispr-flow-spotkanie.png`, pozostałe `granola-*.png` (treść prawdziwej rozmowy służbowej, imiona, adresy URL notatek Granoli, zdjęcie profilowe);
- **czyste, zostają:** 8 × `meetily-*.png` i `meetily-generowanie-szablon-kontekst.webp` (anonimowe fragmenty wypowiedzi, ustawienia; bez nazwisk, adresów i ścieżek);
- **nieobejrzane:** `docs/design/makiety/*.png` (makiety własne z danymi testowymi: „Jarek", „Jarosław", „Piotr Nowak"; nie sprawdzane piksel po pikselu), `docs/design/marka/*.png`.

**Otwarte dla T7:** zrzuty z `makiety/`; imiona „Piotr", „Adrian" w fixturach migawek i testach (same imiona, bez nazwisk; zostawione); kod `ProbeClips+Data.swift` (dane audio w base64, nie przeglądane pod kątem treści nagrań); PR-y, komentarze, Actions i zasoby poza Gitem (T7 krok 3) dopiero po utworzeniu repo.

## Hashe bez mapowania

Tokeny hex w tekście (bez backticków, bo `scripts/check-hashes.sh` traktuje je jako cytaty commitów), które nie są commitami starego repo (zostają bez zmian): numery (np. 12345678, 20261014), 7c8ca11f… (odcisk certyfikatu), ed25519, wpisy `scripts/check-hashes.allow` (hashe przed-amendowe: 006e69b, 823dc51, 88c0bd4, f0c637c, 2d1b719, af362d1, 54f449d, a992f01, fceb10a, 08892c4, bd17a1d) oraz cytowane w recenzjach hashe obiektów, których nie ma w starym repo (2ab53af4, 59e4611e, 68450f74, f0a88b31 w `S18-runda.md`; 4af6b502, d3c35826 w `F20-recenzja-planu.md`; 503b4bd1 w raportach F20; 568354e7, b92290ab, 01f6d215, 7664a03e80d7, ea8b6e71e2a0). Pełna lista: `rewrite-hashes.out`, sekcja „bez mapowania".

## Weryfikacja

- `scripts/check-hashes.sh` → 0 (hook `core.hooksPath scripts/hooks`);
- 5 tagów: tematy zgodne ze starym repo;
- `scripts/test.sh` → **744/744** (na przepisanym klonie, po podmianie hashy), `check-bundle: OK`;
- autorzy/committerzy/taggerzy wszystkich wysyłanych referencji (`master` + tagi): tylko noreply.

## Zostaje do zrobienia (STOP-U)

Krok 9 (utworzenie `sharezz1/yascribe` jako prywatnego i push `master` + 5 tagów), 10 (checkout `/Users/michalprzytulski/yascribe`, klon kontrolny), 11 (ustawienia konta GitHub), commit tego raportu w nowym checkoucie. Nic nie wysłano.
