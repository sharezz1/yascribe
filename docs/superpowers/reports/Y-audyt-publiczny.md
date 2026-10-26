# Y-T7: audyt przed upublicznieniem `sharezz1/yascribe`

Data: 2026-10-26. Stan: `master` (`c4bb973`, 528 commitów), repo **prywatne** (`PRIVATE`), 3 gałęzie (`master`, `rename`, `sparkle`), 5 tagów `faza-*`, 2 PR-y (oba scalone). Ten audyt **nie zmienia widoczności**; zmiana wymaga osobnego „tak" użytkownika (decyzja O2 niżej).

## Nic do zrobienia

| Obszar | Wynik |
|---|---|
| Klucze i tokeny w całej historii (`sk-…`, `or-v1-…`, `Bearer`, `ghp_`, `gho_`, `github_pat_`, `-----BEGIN … PRIVATE`, `AKIA…`) | Tylko literały testowe (`sk-or-v1-SECRET123`, `sk-or-v1-abcdef1234`) i same wzorce w tekście planów. Prawdziwych kluczy brak. |
| Adresy e-mail w całej historii (wszystkie gałęzie i tagi) | `166069997+sharezz1@users.noreply.github.com`, `noreply@anthropic.com` (trailer współautora), `noreply@deepseek.com`, `noreply@github.com`, `git@github.com` (adres zdalny), atrapy z testów (`example.com`, `example.invalid`, `domena.tld`, `a@b.pl`). Adresu służbowego i prywatnego Gmaila nie ma w treści ani w autorach. |
| Autorzy, committerzy, taggerzy | Wyłącznie noreply (sprawdzone na świeżym klonie po T1 i na `master..sparkle` przed pushem). |
| Zrzuty `docs/design/inspiracje/` | Usunięte w T1 (Granola, Wispr); zostały 9 plików Meetily (anonimowe fragmenty mowy, ustawienia, bez nazwisk i adresów). |
| PR-y (`#1`, `#2`) | Treść bez adresów, kluczy i nazw; brak komentarzy i recenzji. |
| Actions, artefakty, issues, wiki, discussions | 0 uruchomień, 0 artefaktów, 0 issues; wiki i discussions wyłączone. |
| Referencje | `refs/pull/1/head`, `refs/pull/2/head` wskazują commity z `rename` i `sparkle` (już sprawdzone, czyste). |
| Fixtury testowe | `Tests/**/Fixtures`, `scripts/fixtures/dictionary-62de.tsv`: dane syntetyczne i lista poprawek nazw własnych (Zowie, Jarek, Zoom), bez fragmentów rozmów. |
| `.claude/settings.json` | Tylko `model` i `advisorModel`. |
| `Co-Authored-By: noreply@anthropic.com` (470 commitów) | Zwykły trailer, nie dane osobowe. |

## Do decyzji użytkownika (O2)

Po upublicznieniu **żadnej** z tych treści nie da się usunąć z historii bez nowego repo (referencje `refs/pull/N/head` zachowują stare commity). Decyzje należy podjąć przed zmianą widoczności.

1. **Licencja i README: brak obu.** Publiczne repo bez licencji oznacza „wszystkie prawa zastrzeżone": inni mogą je oglądać i forkować na zasadach GitHuba, ale nie używać. Propozycja: wybór licencji (np. MIT) przez użytkownika oraz krótki README. To nie jest zmiana w historii, można dodać po upublicznieniu.
2. **Ścieżki `/Users/michalprzytulski/…` w 13 plikach** (`/Users/michalprzytulski/meetnotes`, `…/yascribe`, `…/meetnotes/.devdata`, jedna do roboczego repo `GCX/docs/superpowers/logs/…`). Ujawniają nazwę konta systemowego i układ katalogów. Opcje: zostawić; zamienić na `~` w kolejnym commicie (historia nadal je zawiera).
3. **Nazwy firm i klientów.** `InPost` (14 trafień: przykład słownika w kodzie migawek, testach Replacement, makietach HTML, tytuł wydarzenia kalendarza „The real InPost daily" w `F16-odbior.md`), `Genesys` (19 plików; nazwa produktu), `GCX` (6 odwołań: nazwa roboczego repo i słownika `GCX/dictation`, w tym „nagrania służbowe z `~/GCX`"). `yarrl` zostaje wyłącznie w tekstach planu T1/T7 jako polecenie skanu; `BNP` usunięty w T1. Opcje: zostawić (to nazwy firm, nie dane osobowe), albo zamienić w nowej historii.
4. **Identyfikatory urządzenia i sesji.** Adres sprzętowy słuchawek Bluetooth `00-02-3C-8D-E0-50` (21 wystąpień w 8 plikach: kod testów, BACKLOG, spike S0 słuchawek) i nazwa „Sound Blaster JAM V2"; 36 identyfikatorów sesji nagrań (`2026-…Z-xxxx`). Adres MAC identyfikuje konkretny sprzęt użytkownika. Opcje: zostawić; zamienić na atrapę w kodzie i dokumentach.
5. **Imiona.** `Piotr`, `Adrian`, `Jarek`, `Zowie`, `Serafima` i podobne występują w fixturach, makietach i dokumentach (same imiona, bez nazwisk; część to atrapy w makietach). Opcja: zostawić.
6. **Zrzuty makiet (uzupełnienie 2026-10-26, po recenzji Codexa):** obejrzano wzrokowo 18 z 22 `docs/design/makiety/*.png` (strona główna, spotkanie, transkrypt, Settings, pigułka, Presets, Templates, Coming up, Dictionary). Zawierają wyłącznie atrapy: same imiona (Piotr, Wojciech, Adrian, Michał, Jarek, Zowie), nazwy produktów (Genesys, WFM, InPost, PUDO) i liczby importu słownika (166 terminów, 223 aliasy, jak w dokumentach); bez nazwisk, adresów i danych z prawdziwych spotkań. Nieobejrzane: `kierunek-a/b/c.png` (kierunki stylu) i 3 pliki `docs/design/marka/*.png` (grafika znaku). Ryzyko niskie.
7. **Zrzuty cudzych produktów** (Meetily, 9 plików): materiał inspiracyjny z cudzego UI; ryzyko praw autorskich jest niewielkie, ale to decyzja użytkownika, czy zostają.

## Naprawione

Nic nie zmieniano w ramach T7. Ewentualne usunięcie treści z historii (punkty 2–5) jest możliwe wyłącznie przez nowe repo i powtórkę T1 od kroku 3; plan tego nie wykonuje sam.

## Następny krok

Użytkownik rozstrzyga punkty 1–7, potem osobne „tak" na `gh repo edit sharezz1/yascribe --visibility public --accept-visibility-change-consequences`. Bez „tak" repo zostaje prywatne, a wydania T9 nie ruszają.
