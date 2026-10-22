# Zmiana modelu w widoku spotkania (podsumowanie i korekta): krótka specyfikacja

Status: **zaakceptowany 2026-10-22** (decyzje 1 i 3 potwierdzone, faza **2.0.1**), bez kodu. Prośba użytkownika z 2026-10-21/22, wpis w `BACKLOG.md`, kontekst w
`reports/HANDOVER-2026-10-22-nagrywanie-i-modele.md` (zadanie 2). Faza 2.0.1 (decyzja użytkownika); pozycja mała i niezależna od rdzenia nagrywania.

## Cel

Porównywać jakość (oMLX kontra API, myślenie włączone i wyłączone) bez wychodzenia do Settings. **Preset zostaje wartością domyślną**;
w widoku spotkania można dla tej jednej sesji wybrać inny model **podsumowania** (zakładka Summary) i inny model **korekty**
(sekcja Transcript, „Improve transcript"). Wybór **zapisuje się przy sesji** (decyzja użytkownika), nie jest jednorazowy.

## Decyzje (z rekomendacją; do potwierdzenia)

1. **Gdzie leży nadpisanie:** `notes/meta.json` (`NoteMeta`), nowe pole **opcjonalne** `modelOverrides: ModelOverrides?`
   z `summary` i `correction` (`RoleOverride`: `providerID`, `model`, `thinking: Bool?`, tylko przy podsumowaniu).
   Powód: `meta.json` to już per-sesyjne metadane notatki z opcjonalnymi polami (`calendarEvent`) i gotowym `updateMeta`;
   stary plik czyta się bez zmian. Alternatywa (osobny `notes/models.json`) nic nie daje poza kolejnym plikiem.
   **Nie ruszamy `Preset` ani `RunSnapshot`:** snapshot opisuje przebieg transkrypcji, a nadpisanie dotyczy ról po niej.
2. **Kolejność wyboru modelu:** nadpisanie sesji → rola zamrożonego presetu nagrania → dotychczasowe zastępstwo
   (`SummaryModel.resolve`). `SummaryChoice` dostaje źródło (`override` / `preset` / `fallback`); korekta analogicznie
   (dziś `presetFor(url)?.correction`).
3. **Kiedy działa:** przy **następnym** „Generate"/„Regenerate" i „Improve transcript". Zmiana wyboru niczego sama nie uruchamia
   i nie kasuje istniejącej notatki ani `corrected.json`.
4. **Thinking idzie razem z modelem podsumowania** (ta sama droga, rekomendacja z przekazania): `thinking: Bool?` w nadpisaniu;
   `nil` = `GlobalSettings.summaryThinking`. Korekta zawsze bez myślenia (bez zmian), lokalne serwery zawsze bez myślenia (bez zmian).
5. **Powrót do presetu:** pozycja „Use preset (<model>)" na górze menu usuwa nadpisanie roli; chip wraca do stanu domyślnego.
6. **Pokazywanie źródła:** chip „Model: <model>" z ikoną „On this Mac" dla dostawców lokalnych (istniejący znacznik), a przy
   nadpisaniu dopisek „changed from preset". Wynik już niesie `model` w `summary.json`; zakładka Summary pokazuje „Made with <model>",
   z dopiskiem, gdy różni się od modelu presetu. Korekta: ten sam dopisek przy przycisku (jeśli `corrected.json` nie ma modelu, pole
   opcjonalne dochodzi tam, nie w nowym pliku).
7. **Lista modeli:** ta sama co w Presets (`ModelPickerState`), tylko dostawcy z czatem (`Provider.supports(.chat)`, poprawka P4:
   bez ElevenLabs i Yascribe). Nadpisanie wskazujące usuniętego dostawcę: wraca do presetu z jednorazowym komunikatem, plik nie jest kasowany po cichu.
8. **„Fully local":** plakietka dotyczy presetu i zostaje bez zmian. Nadpisanie chmurowym modelem w presecie lokalnym jest widoczne
   tylko jako brak znacznika „On this Mac" przy chipie. Nie dodajemy ostrzeżenia o wysyłce do chmury (ten sam użytkownik świadomie wybiera model).

## Poza zakresem

Zmiana modelu ASR (wymaga ponownej transkrypcji), model per szablon, porównanie obok siebie dwóch wyników, zmiana domyślnego `summaryThinking`
(użytkownik: zostaje włączone).

## Testy (plan)

- `SummaryModel`: nadpisanie wygrywa z presetem i zastępstwem; nadpisanie z nieznanym dostawcą → preset.
- `NoteMeta`: stary `meta.json` bez `modelOverrides` czyta się; zapis i odczyt `RoleOverride`; reset usuwa pole (mutacja bramki).
- `NotesModel`: `generate`/`retryCorrection` biorą model z nadpisania; zmiana wyboru nie uruchamia pracy.
- Migawki: chip w Summary i Transcript (domyślny, zmieniony, lokalny).
