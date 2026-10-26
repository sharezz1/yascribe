# F15-T13 — uwagi użytkownika z odbioru (2026-10-15)

Zebrał autor planu z odbioru na żywo (aplikacja z `scripts/run.sh`, stan `6122288`, 183/183).
Sesja testowa: `.devdata/sessions/2026-10-15T13-07-49Z-f184` (YouTube z głośników + mikrofon).

## A. Funkcjonalne — partia poprawek

| # | Uwaga | Dowód | Kierunek poprawki |
|---|---|---|---|
| 2 | **Echo z głośników jako „Me", tekst dwa razy.** Mikrofon łapie YouTube z głośników; ta sama wypowiedź jest jako Them i Me (0:00:00, 0:00:21). `CrosstalkFilter` (E3, korelacja obwiedni ≥ 0,8) tego nie złapał. Skutek dla notatki: model przypisuje użytkownikowi cudze słowa (właściciele w Next Steps). | zrzut: dwa identyczne wiersze Me/Them | Odsiew **tekstowy** po transkrypcji: wypowiedź Me, która w oknie ±kilka s prawie słowo w słowo powtarza wypowiedź Them (np. podobieństwo tokenów ≥ 0,8), wypada / oznaczona jako echo i poza notatką. Test + mutacja. Filtr akustyczny zostaje. AEC offline dalej faza 2. |
| 3 | **Korekta nie wykonała się, a status wisi bez końca.** Baner „After the meeting, we improve the transcript with deepseek/deepseek-v4.1-flash…" i wiersz listy „Improving transcript…" trwają; `runs/2026-10-15T13-09-30Z-c62c/corrected.json` **nie istnieje** (transkrypt 15:09, notatka 15:13 z niepoprawionego). | pliki sesji | Znaleźć przyczynę (nie ruszyła / padła po cichu). Stan korekty musi się kończyć: sukces → baner znika; błąd → „Correction failed" + Retry, w wierszu i w banerze. Test na przejście stanu po błędzie. |
| 4 | **W notatce da się zaznaczyć tylko jeden akapit.** Bloki (`MarkdownBlocks`) to osobne `Text` — zaznaczenie nie przechodzi między nimi. | zrzut Summary | Cała notatka jako jeden zaznaczalny tekst (np. jeden `AttributedString` w jednym widoku tekstu albo `NSTextView`), układ bloków zachowany. |
| 5 | **Tytuł za długi i z przedrostkiem** („Notatki z rozmowy: presja na wygląd, kulturowe przypisanie zachowań i komentowanie sportsmenek"). | zrzut listy | Prompt tytułu (autotytuł i `# ` notatki): krótki, do ~8 słów, bez przedrostków typu „Notatki z rozmowy", „Meeting notes". Test na regułę w prompcie. |
| 6a | **ModelPicker: zawijanie długich nazw** (druga linia wyrównana do prawej, np. `nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b`), pole szukania z tekstem wyrównanym do prawej, wąski popover. Funkcjonalnie OK (26 modeli transkrypcji, MAI na liście). | zrzut popovera | Jedna linia, skracanie w środku, pełna nazwa w podpowiedzi; szukanie wyrównane do lewej; szerszy popover. |
| 7 | **Dostawcy w Settings: szybkie dodawanie + weryfikacja.** Modele zostają w presetach, dostawcy w Settings. Kafelki **OpenRouter**, **Ollama**, **Custom** → okno z gotowym adresem, użytkownik wkleja tylko klucz (Ollama bez klucza; informacja „tylko korekta i podsumowanie, nie transkrypcja"). Po zapisie test połączenia (`listModels`) → **„✓ Verified"** albo „✗ <powód>" (zły klucz, guardrail). | zrzut sekcji „Models for meetings" | Jak obok. **ElevenLabs bezpośrednio → faza 2** (inne API: `xi-api-key`, multipart); Scribe v2 dostępny już teraz przez OpenRouter (`elevenlabs/scribe-v2`). |

✏️ **Uwaga 7 — forma zmieniona 2026-10-15** (sesja designu, `docs/design/macos.md` §11.5): kafelki
i okno (arkusz) zastępuje wiersz **„Add: OpenRouter · Ollama · Custom…”** na dole karty Providers,
z formularzem rozwijanym w miejscu (gotowy adres, klucz, wynik weryfikacji w tej samej linii,
Cancel / Save & verify). Treść uwagi (gotowy adres, tylko klucz, Ollama bez klucza i bez
transkrypcji, „✓ Verified" / „✗ powód") obowiązuje bez zmian. Zatwierdził użytkownik.

## B. Wygląd — osobny krok przed poprawkami widoków

**1. „Brzydko, szaro, w niczym nie przypomina nowoczesnych aplikacji; jak Windows 98 z zaokrąglonymi rogami."**
Cel fazy 1.5 („Presets i Settings przestają być masakrycznie brzydkie", spec §1) **nie jest
osiągnięty**. Spec i plan ustaliły układ i przepływy, ale nie **język wizualny** — widoki
zostały na domyślnych szarych `Form`/`GroupBox` SwiftUI.

Potrzebne, zanim wykonawca dotknie widoków:
1. **Mały system wizualny** zapisany w `docs/design/macos.md` (nowa sekcja): kolory tła i
   powierzchni (jasny i ciemny), jeden kolor akcentu, typografia (np. szeryfowy krój tytułów
   jak w Granoli/Wispr Flow, rozmiary), odstępy, promienie, karty zamiast szarych grup,
   przyciski-pigułki. Wzorce: `docs/design/inspiracje/` (Granola: ciepłe tło, szeryfowe tytuły,
   dużo powietrza, pigułki; Wispr Flow: zakładki, karty).
2. **Makiety wysokiej wierności** (nie szkielety) dla: strony głównej, widoku spotkania
   (Summary), Presets, Settings, pigułki — w jasnym i ciemnym motywie. **Akceptacja użytkownika
   przed kodem.**
3. Wdrożenie przez wspólne komponenty (karta, przycisk-pigułka, nagłówek sekcji, styl tytułu),
   nie poprawki widok po widoku; migawki T0 przed/po do porównania z makietami.

## C. Nieprzetestowane w tym odbiorze (zostaje na odbiór po poprawkach)

Review Focus #9 (przełączanie sesji w trakcie nagrania), #10 (notatka dla presetu „English"
bez summary), D2 (nazwa mikrofonu po zmianie wejścia), potwierdzenie zmiany embeddingu,
dodawanie dostawcy (dawniej arkusz Add Provider, teraz w miejscu — §11.5), punkt 11 (nieczytelny plik notatek). T11 (pomiar Auto/PL+EN) czeka na
nagranie mieszane i klucz w terminalu użytkownika.

## D. Drobne poza listą

- `Sources/MeetNotesRecording/ruvector.db` — plik-śmieć po wtyczce (ostrzeżenie SwiftPM
  „unhandled file" przy każdym buildzie); usunąć z katalogu i dopisać `ruvector.db` do `.gitignore`.
