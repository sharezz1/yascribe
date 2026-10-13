# S17 (D3) — uwagi użytkownika z odbioru ręcznego (2026-10-13)

Zbiera autor planu. Poprawki: jedno zadanie po odbiorze i wątku designu (wygląd robimy raz, nie dwa).

## Funkcjonalne

1. **Presets: brak Cancel** przy tworzeniu/edycji presetu. Nowy preset nie pojawia się na liście w trakcie edycji — nie widać, że coś się tworzy.
2. **Wybór modelu (Presets i Settings → Embeddings), wspólny komponent `PresetsView.swift:~100`:**
   - brak wyszukiwarki (wymaganie użytkownika od początku: „dropdown z wyszukiwaniem");
   - jedna lista dla wszystkich ról. Dla STT filtr `inputModalities contains "audio"` daje 45 modeli czatowych z audio, a **prawdziwych modeli transkrypcji nie ma** (OpenRouter nie zwraca ich w domyślnym `/models`). Publiczne API: `GET /models?output_modalities=transcription` → 25 (m.in. `microsoft/mai-transcribe-2`, `nvidia/parakeet-tdt-0.6b-v3`, `elevenlabs/scribe-v2`), `?output_modalities=embeddings` → 37. Lista per rola: STT → transcription, embedding → embeddings, korekta/podsumowanie → tekstowe;
   - `list.prefix(300)` ucina listę, a etykieta mówi „459 models";
   - długie natywne menu rośnie przy przewijaniu — zniknie razem z zamianą na listę z wyszukiwarką.
3. **Pola promptu** pod Correction i Summary bez etykiety i podpowiedzi — użytkownik nie wie, co wpisać (to opcjonalne własne instrukcje dla modelu).
4. **Settings:** brak informacji, że modele STT/korekty/podsumowania wybiera się w presecie (w Settings jest tylko embedding globalny).
5. **Settings: brak Save** — zapis jest natychmiastowy, ale niesygnalizowany. Decyzja użytkownika: autozapis + „Saved ✓" albo Save/Cancel. *(otwarte)*
6. **Lista presetów:** pusta i pełna lista rysuje się jako biały blok w połowie wysokości kolumny, a panel szczegółów „Choose a preset" jest ściśnięty.

## Wygląd

7. Presets i Settings „masakrycznie brzydkie" — przeprojektowanie w osobnym wątku designu (`docs/design/macos.md`), potem wdrożenie razem z punktami 1–6.

## Usprawnienia (faza 2)

- Odzyskiwanie odmówionej zgody TCC → `docs/superpowers/BACKLOG.md`.
- ElevenLabs Scribe v2 dostępny przez OpenRouter (`elevenlabs/scribe-v2`) — osobny klient niepotrzebny.
