# Sondy na żywo — bramka G3 (sesja S9, 2026-10-11)

Zadanie: B5 (plan 02). Sesja „Ty? tak" — prowadzona z użytkownikiem; klucz OpenRoutera
wpisany w terminalu użytkownika (`export MEETNOTES_API_KEY`), nigdzie nie zapisany.
Binarka: `.build/out/Products/Debug/meetnotes-cli` (build debug, jak w planie).

## Krok 1 — katalog kłamie przez przemilczenie

```
$B models https://openrouter.ai/api/v1 | wc -l                   → 458
$B models https://openrouter.ai/api/v1 | grep -c mai-transcribe  → 0
```

Uwaga orkiestratora: modele transkrypcyjne nie są na domyślnej liście katalogu (domyślnie
zwracane są modele z wyjściem tekstowym). Z `output_modalities=transcription` publiczny
katalog zwraca 25 modeli i **oba nasze są na liście** (`microsoft/mai-transcribe-2`,
`nvidia/parakeet-tdt-0.6b-v3`) — „przemilczenie" to filtr modalności, nie brak modelu.

## Krok 2 — P2: mai-transcribe-2 (wpisany z ręki)

```
$B probe https://openrouter.ai/api/v1 microsoft/mai-transcribe-2 asr --language pl
→ DZIAŁA audioTranscriptions enforced
```

**Zgodne z oczekiwanym.** Ciało JSON z rozdz. 11 przechodzi — **warunek STOP (przejście na
`multipart/form-data`) NIE zachodzi**; bramka G3 rozstrzygnięta na korzyść planu.
Endpoint: `Azure | microsoft/mai-transcribe-2-20260903` (0,10 USD/h; na liście ZDR).

## Krok 3 — P10: parakeet przez API

```
$B probe https://openrouter.ai/api/v1 nvidia/parakeet-tdt-0.6b-v3 asr --language pl
→ DZIAŁA audioTranscriptions automatic
```

**Hipoteza ze speca potwierdzona** (automatic = automatyczne wykrywanie języka).
Endpoint: `Together | nvidia/parakeet-tdt-0.6b-v3` (0,000025; na liście ZDR).

## Krok 4 — P3: model tylko czatowy

```
$B probe https://openrouter.ai/api/v1 google/gemini-3.8-flash asr --language pl
→ DZIAŁA chatAudio unknown
```

**Zgodne z oczekiwanym** (model nie obsługuje audio → sonda klasyfikuje jako chatAudio/unknown).

## Krok 5 — P1: Ollama

**Pominięty** — Ollama nie jest zainstalowana na tej maszynie (`which ollama` → brak).

## Krok 6 — P8: klucz nie wycieka do plików

```
grep -rlF -- "$MEETNOTES_API_KEY" . ~/Library/Application\ Support/MeetNotes 2>/dev/null | grep -v '^./.build'
→ pusto
```

**Pusto = OK** (polecenie wypisuje tylko nazwy plików, nigdy klucz). Zapis i odczyt z pęku
kluczy sprawdza D3 przez aplikację.

## Przeszkody po drodze (rozwiązane)

1. Pierwsze podejście: 401 `User not found` — klucz nieustawiony w sesji terminala.
2. Drugie podejście: 404 `Provider not allowed by guardrail` dla obu modeli — guardrails
   privacy na koncie wykluczały providerów (Azure, Together). Użytkownik odblokował;
   po odblokowaniu sondy przeszły bez zmian w kodzie.
3. Dopiero po odblokowaniu dało się zweryfikować ciało JSON — dlatego ważne, że przeszło
   **bez błędu formatu**.

## Wnioski dla speca

- Ciało `input_audio` (rozdz. 11) działa z OpenRouterem dla obu modeli — bez multipartu.
- `mai-transcribe-2`: obsługa języka `enforced`; `parakeet`: `automatic`; modele czatowe: `chatAudio unknown`.
- Oba modele transkrypcyjne są ZDR i poza domyślną listą katalogu (filtr modalności).

---

## Aneks (2026-10-12, poza planem): ElevenLabs Scribe v2 — test bezpośredni

Rozszerzenie po sesji S9, na życzenie użytkownika (klucz ElevenLabs użytkownika, wpisany
w jego terminalu; nigdzie nie zapisany). Cel: sprawdzić klucz, jakość polską i kształt API
(pod ewentualny adapter bezpośredni w przyszłości).

Próbka: `say -v Zosia -o /tmp/el-probka.aiff "Sprawdzam nagrywanie, raz, dwa, trzy, cztery, pięć"`
→ `afconvert -f WAVE -d LEI16@16000` → WAV 16 kHz mono.

```
POST https://api.elevenlabs.io/v1/speech-to-text
Header: xi-api-key: … (klucz użytkownika)
multipart: file=@el-probka.wav, model_id=scribe_v2, language_code=pl
→ HTTP 200
language: pol
text: Sprawdzam nagrywanie. Raz, dwa, trzy, cztery, pięć
```

**Transkrypcja idealna** (jedyna różnica: kropka po „nagrywanie" zamiast przecinka —
normalizacja interpunkcji). Pola odpowiedzi: `audio_duration_secs`, `language_code`,
`language_probability`, `text`, `transcription_id`, `words` (timestampy słów).

Uwagi:
- Direct API ElevenLabs **nie jest OpenAI-compatible** (`xi-api-key` + multipart) — adapter
  bezpośredni w aplikacji byłby zmianą architektury/planu (decyzja właściciela planu).
- Ścieżka bez zmian: przez OpenRouter jako `elevenlabs/scribe-v2` (provider ElevenLabs,
  na liście ZDR; promo −50% na modele ElevenLabs do 19.10) — do porównania w razie potrzeby.
- `scribe_v2_medical` — ten sam kształt żądania i ta sama cena (nie testowany).
