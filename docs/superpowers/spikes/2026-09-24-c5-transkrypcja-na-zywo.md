# C5 — transkrypcja na żywo (spike, 2026-10-12)

Sesja S13. Materiał: świeże nagranie 10,6 min (`/tmp/mn-s2`; `system` 48 kHz × 2 / 634,0 s, `mic_raw` 16 kHz × 1 / 637,7 s; offset mic **−3,647 s** vs system). Model: `microsoft/mai-transcribe-2` przez OpenRouter, `--language pl`.

## Liczniki (run `2026-10-12T12-51-35Z`, pełny)

| Pole | Wartość |
|---|---|
| requestCount | 24 (12 okien × 2 ścieżki) |
| audioSecondsSent | 1218,3 s vs 1268 s sesji (2×634) — ~25 s ciszy/ścieżkę odsiane |
| failedChunkCount | 0 |
| wypowiedzi | 15 (5 Them / 10 Me) |
| czas | 12:51:35→13:00:54Z (~9,3 min) |

## P5 — wznowienie

Bieg 1 przerwany po 7 oknach (`chunks/system-0..6`, brak `run.json`). Bieg 2 z tym samym `--run p5`: **requestCount = 17** (24−7), failed 0, 14:32:42→14:39:20Z. Teksty vs bieg pełny: identyczne czasy, 11/15 identycznych tekstów; 4 różnice kosmetyczne (format liczb) — niedeterminizm ASR.

## Oś sesji vs pliki ścieżek

Czasy wypowiedzi = oś sesji (kotwice zegara). `system` = oś sesji (offset 0); `mic_raw` przesunięty **+3,647 s** (mikrofon ruszył wcześniej). Weryfikacja w QuickTime: `system.caf` 0:01 ✓ i 3:27 ✓; `mic_raw.caf` 1:38,8–1:44,5 ✓ (po korekcie offsetu; bez korekty 1:35 = 0,9 s ogona echa). Whisper (ggml-base) na wycinku mic 93–101 s: echo „A drugi pomysł? Tak, masz rację." (0–5 s), komentarz „Ale chciałbym jeszcze…" (5,7–8 s). `system.caf` 1:30,5–1:42,0 = cyfrowe zero (pauza wideo).

## Pomiar przecieku (echo z głośników)

10 wypowiedzi „Me", większość = echo wideo. Korelacja obwiedni 20 ms (`mn-corr.py`; region mic 103–143 s):

| Wyrównanie | best corr (lag 0–0,3 s) |
|---|---|
| offset runnera (+8 ramek, mic 0,15 s) | ≈ 0 |
| **poprawne (mic−system = −182 ramek; best −184, lag ~40 ms)** | **0,458** |

Próg `CrosstalkFilter` = 0,8 (test syntetyczny ~1,0) → prawdziwe echo z głośników nie ma jak zostać odsiane. Wniosek: próg zachowawczy działa jak zaprojektowano, ale realny przeciek wymaga AEC (backlog C, wyzwalacz odpalony).

## Błędy po drodze

- `baseURL` bez schematu (`openrouter.ai/api/v1`): 24/24 `NSURLErrorDomain −1002 "unsupported URL"`; powód tylko w `transcript.json.failedChunks[].error`. BACKLOG: walidacja adresu.
- Pasek postępu `0%` do ~25 s (pierwsze okno) — dwa przerwania „za wcześnie" (0 i 7 okien).
