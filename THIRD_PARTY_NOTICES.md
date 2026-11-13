# Licencje zależności i atrybucje

| Składnik | Licencja | Uwagi |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.7 | Apache-2.0 | zależność SwiftPM, wbudowana w aplikację; tekst licencji w repozytorium zależności |
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.9.2 | MIT (z notami autorów w pliku `LICENSE` projektu) | framework w `Yascribe.app/Contents/Frameworks`; aktualizacje |
| Model Parakeet TDT 0.6B v3 (NVIDIA; konwersja CoreML: FluidInference) | CC-BY-4.0 | **atrybucja:** model © NVIDIA, [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), licencja [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); konwersja [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). Model nie jest częścią repozytorium ani paczki; użytkownik pobiera go w aplikacji. |

Usługi API (OpenRouter, ElevenLabs i modele za nimi) podlegają warunkom ich dostawców.

## Port potoku Cohere

Kod w `Sources/YascribeLocalASR/Cohere/` pochodzi z
[altic-dev/FluidAudio](https://github.com/altic-dev/FluidAudio/tree/386f7195670b77f2954c7ee143ec63fcb50b6c3b/Sources/FluidAudio/ASR/Cohere),
rewizja `386f7195670b77f2954c7ee143ec63fcb50b6c3b`, Apache-2.0.
Test planera pochodzi z `Tests/FluidAudioTests/ASR/Cohere/CohereAudioChunkPlannerTests.swift` tej samej rewizji.
Pełny tekst licencji: [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt).
API GitHub dla tej rewizji potwierdziło brak głównego pliku `NOTICE`; przenoszone źródła nie zawierają dodatkowych not autorów.
Zmiany Yascribe oznaczono w nagłówkach: własność aktora Swift 6, sekwencyjne dekodowanie, EOS, język,
własny magazyn kompilacji, klucz z odcisku i atomowa publikacja.

## Model Cohere Transcribe 6-bit

[BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit](https://huggingface.co/BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit/tree/79320e92e2e220ed2ed2a9acb41f3caff06acb85),
rewizja `79320e92e2e220ed2ed2a9acb41f3caff06acb85`, GPL-3.0.
Konwersja: Barathwaj Anandan; model bazowy: CohereLabs/cohere-transcribe-03-2026.
API HF potwierdziło `license: gpl-3.0` w tej rewizji; sprawdzono pełny
[LICENSE](https://huggingface.co/BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit/blob/79320e92e2e220ed2ed2a9acb41f3caff06acb85/LICENSE)
(GNU GPL wersja 3) i metadane README. Rewizja nie zawiera osobnego `NOTICE`.
Model nie jest częścią repozytorium ani paczki; plik LICENSE jest objęty manifestem pobierania.

**Zakaz dystrybucji binariów z portem Cohere do czasu T12:** noty i licencje trzeba jeszcze
spakować do aplikacji oraz rozszerzyć `check-bundle.sh`. Obecna kontrola paczki nie weryfikuje nowych licencji.
