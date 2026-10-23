# MeetNotes

Natywna aplikacja macOS do notatek ze spotkań. Ten słownik obejmuje na razie pojęcia fazy 2.1 „Słownik" (w tym przebiegi transkrypcji); reszta projektu dopisywana, gdy będzie rozstrzygana.

## Słownik (faza 2.1)

**Dictionary**:
Jeden globalny zbiór terminów użytkownika, wspólny dla wszystkich presetów i spotkań. W interfejsie osobna zakładka, nie sekcja ustawień.
_Unikaj_: słownik per preset, lista słów

**Term**:
Poprawny zapis nazwy lub wyrazu domenowego (np. `Zowie`, `Genesys`, `PUDO`). Może istnieć bez aliasów — wtedy jest tylko podpowiedzią dla modelu.
_Unikaj_: słowo kluczowe, fraza, wpis

**Alias**:
Błędne rozpoznanie przypisane do dokładnie jednego terminu (np. `Zoey`, `Zoim` → `Zowie`). Na jego podstawie działa podmiana.
_Unikaj_: wariant, synonim, zamiennik

**Risky alias**:
Alias, który jest też zwykłym słowem (np. `Pudo`, `impost`), więc podmiana mogłaby zepsuć poprawne zdania. Importowany jako wyłączony (sekcje `#!` w `replacements.tsv`), użytkownik włącza go świadomie.
_Unikaj_: niebezpieczny alias

**Priority** (terminu):
Ranga decydująca, które terminy wypadają z polecenia dla modelu, gdy lista nie mieści się w budżecie kontekstu. Pochodzi z tierów T1/T2/T3 w `vocab_core.txt`.
_Unikaj_: tier (to nazwa w pliku źródłowym, nie w aplikacji)

**Replacement**:
Deterministyczna podmiana aliasów na terminy w tekście transkryptu, bez udziału modelu. Całe frazy na granicach słów, bez rozróżniania wielkości liter, najdłuższy alias pierwszy.
_Unikaj_: korekta (to krok modelu), poprawka

**Attendee hint**:
Imiona i nazwiska uczestników powiązanego wydarzenia z kalendarza, wstrzyknięte do polecenia korektora i podsumowania tylko na czas jednego przebiegu. Nie trafiają do Dictionary.
_Unikaj_: słownik uczestników

**Run** (przebieg):
Jedna transkrypcja nagrania, katalog `runs/<runID>/` z `transcript.json`, ewentualnie `corrected.json`, `run.json` i migawką modelu, języka i dostawcy. „Transcribe again…" dodaje kolejny przebieg, nie nadpisuje poprzedniego.
_Unikaj_: sesja (to całe nagranie), podejście

**Current run** (bieżący przebieg):
Przebieg, z którego aplikacja czyta transkrypt, korektę, wyszukiwanie i notatkę: najnowszy ukończony, niepusty i bez luk (`RunSelection`). Nieudana albo niepełna nowa próba nie zasłania go; najnowsza próba pozostaje celem wznowienia.
_Unikaj_: ostatni przebieg (najnowszy nie zawsze jest bieżący)
