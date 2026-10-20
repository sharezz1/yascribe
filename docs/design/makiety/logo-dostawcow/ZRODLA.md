# Logo dostawców — źródła (pobrane 2026-10-16)

Znaki towarowe właścicieli; użyte do identyfikacji dostawcy w prywatnej aplikacji. Nie rozciągać,
nie przekolorowywać (poza wariantem jasnym/ciemnym przewidzianym przez właściciela), zachować
margines ochronny.

| Plik | Źródło |
|---|---|
| `openrouter-glyph-ink.svg` (jasne tło), `openrouter-glyph-cloud.svg` (ciemne tło) | https://openrouter.ai/brand — „Glyph” |
| `elevenlabs-symbol.svg` | https://elevenlabs.io/brand — „Symbol” |
| `ollama.svg` | `@lobehub/icons-static-svg@1.95.1` (MIT), https://lobehub.com/icons/ollama — Ollama nie ma oficjalnej strony z logo |

## Dodane 2026-10-20 (F20 P3) — wersje jednobarwne (template)

Aplikacja rysuje je jak Ollamę i ElevenLabs: czerń w jasnym motywie, biel w ciemnym (`ProviderLogos.swift`, `template: true`).
**Odstępstwo od zasady „nie przekolorowywać":** llama.cpp ma pierwotnie wersję barwną (pomarańczowa lama na ciemnym kaflu);
tu użyta jest sama lama w jednym kolorze, na prośbę użytkownika (spójność z resztą listy). Właściciel nie przewiduje takiego wariantu,
więc jeśli to problem, wracamy do wersji barwnej (`media/llama1-icon-transparent.svg` w repo llama.cpp) i `template: false`.

| Plik | Źródło |
|---|---|
| `llamacpp-mono.svg` | repo `ggml-org/llama.cpp`, `media/llama1-icon.svg` (licencja repo: MIT); usunięty kafel, jeden kolor, `viewBox` dopasowany do lamy |
| `omlx-mono.svg` | repo `jundot/omlx`, `apps/omlx-mac/Resources/Assets.xcassets/MenubarFilled.imageset/menubar-filled.svg` (Apache-2.0); glif paska menu, `viewBox` wyśrodkowany |
| `yascribe-mark-mono.svg` | znak własny Yascribe: pióro i słupki z `docs/design/marka/ksztalty.json` (geometria jak w `zloz-ikone.py`, skala 2,0), bez kafla, jeden kolor |
