# F20 T9 — spike S2: lokalne serwery tekstowe (Ollama, llama.cpp, oMLX)

> Pomiar na tym Macu (Apple M4, 16 GB, macOS 27), 2026-10-20, noc. Skrypty throwaway poza repo (scratchpad sesji). Wersje: Ollama 0.40.6 (aplikacja),
> `llama-server` 0.7.0 (Homebrew, build 11669), oMLX 0.7.0 (`oMLX.app`, uruchamiany przez `omlx-cli serve`). Bez kluczy API, bez ruszania
> Ustawień systemowych, TCC i pęku kluczy. Dokument bez treści nagrań użytkownika: tylko liczby; cytowane są wyłącznie wyniki na materiale
> **syntetycznym** i komunikaty błędów serwerów. **Baseline API: nie zmierzony (potrzebny klucz użytkownika).**

## 0. Najważniejsze wnioski (dla T10–T13)

1. **Ollama 0.40.6 NIE obcina wejścia po cichu.** Wejście ponad `num_ctx` daje **HTTP 400** z komunikatem „request (N tokens) exceeds the available context size (4096 tokens), try increasing it" (na `/v1` i na natywnym `/api/chat`). llama.cpp: ten sam komunikat, `type: exceed_context_size_error`. Dotychczasowy `ContextError.isContextOverflow` to rozpozna (słowo „context").
2. **Ciche obcięcie jest po stronie WYJŚCIA.** Gdy prompt + odpowiedź przekraczają kontekst, serwer kończy generację na granicy kontekstu i zwraca **HTTP 200 z `finish_reason: "length"`**, bez żadnego błędu (Ollama i llama.cpp; llama.cpp loguje `truncated = 1`). Aplikacja dziś **nie czyta `finish_reason`** — korekta 6000 znaków przy 4096 tokenach daje 45 z 49 linii, `parse` zwraca `nil`, cała partia przepada; notatka urwana w pół zdania wyglądałaby jak kompletna. Dochodzi to samo z `num_predict` zaszytym w Modelfile (patrz 3.4). **T10 musi traktować `finish_reason == "length"` jako błąd/ostrzeżenie.**
3. **Domyślny kontekst Ollamy w aplikacji to 4096 tokenów** (`ollama ps`, `/api/ps`). To za mało na cokolwiek ponad ~5 min mowy (notatka) i na partię korekty 6000 znaków.
4. **Model „thinking" bez wyłączenia myślenia jest w praktyce bezużyteczny**: `bonsai-2` na prostej notatce z 10 min spotkania spędził 5,6 tys. tokenów na rozumowanie (451 s do pierwszego znaku odpowiedzi, ucięty limitem); na Ollamie z domyślnymi 4096 tokenów wywołanie „tytuł" skończyło się po 126 s z `finish_reason=length` i **pustą** odpowiedzią (cały kontekst zjadło rozumowanie). Myślenie wyłącza `reasoning_effort: "none"` (działa na obu serwerach), co wymaga pola w ciele żądania, którego klient dziś nie wysyła.
5. **Odpowiedź korekty ≈ wielkość wejścia** (6171 znaków → 6172 znaków), więc jeden współczynnik „rezerwy 40%" nie wystarcza dla korekty i mapy; potrzebne dwie wartości (sekcja 7).
6. **Bramka `CorrectionRules.accepts` (pasmo długości 0,6–1,6) nie odrzuciła ani jednej linii** w żadnym pomiarze, także gdy model zmienił datę („pierwszego grudnia" → „pierwszy stycznia"), wstawił angielskie „month" albo zmyślone słowo. Odrzucenia na poziomie linii: 0 we wszystkich sparsowanych partiach; realnym „odrzuceniem" jest odrzucenie CAŁEJ partii przez `parse` (zła numeracja).
7. **oMLX: nie zmierzony** — jedyny kompletny model MLX na dysku (gemma-3-12b-it-qat-4bit, 7,85 GB) jest odrzucany przez strażnika pamięci oMLX: HTTP 507 (sekcja 6). Port 8000 potwierdzony z konfiguracji.

## 1. Maszyna, modele, obciążenie

| Serwer | Modele dostępne lokalnie (przed pomiarem) | Użyte w pomiarze |
|---|---|---|
| Ollama | `genesys-ministral3` (własny fine-tune użytkownika, Ministral 3 8,5B Q4_K_M, w Modelfile `num_predict 1024`, `temperature 0.7`); **po zgodzie pobrano `bonsai-2:latest`** (Prism ML, qwen35 9B **Q2_0**, 3,2 GB, „thinking", Modelfile: `temperature 1`, `top_k 20`, `top_p 0.95`, `presence_penalty 1`) | oba |
| llama.cpp | tylko GGUF-y z magazynu Ollamy (ten sam plik = porównanie serwerów 1:1): oba powyższe; Q2_0 ładuje się w 0.7.0 | oba |
| oMLX | w `model_dirs` aplikacji **żadnych wag** (katalogi Hugging Face puste albo nieistniejące); jedyny kompletny MLX-instruct: `gemma-3-12b-it-qat-4bit` (7,85 GB) w `GCX/meeting notes/_intelligence/models` | próba, odrzucona (507) |

Nie pobierano niczego poza `bonsai-2`. Do Ollamy dodałem i usunąłem na chwilę pochodny model `f20s2-ctx8k` (tylko manifest, test `PARAMETER num_ctx`).

**Obciążenie (uczciwie):** w tym samym czasie inny agent budował Swifta; load average przy pomiarach 2–107, swap 6,5–7,2 z 8 GB. Każdy wiersz czasów w sekcji 2 ma zapisane load i liczbę procesów swift (surowe wyniki w scratchpadzie). Czasy są **pesymistyczne**; maszyna nie była cicha przez dłuższy czas. Najczystsze wiersze: `llama.cpp bonsai bez myślenia` (load 2–6, swift 0 na starcie).

## 2. Czasy

Wywołania dokładnie jak w aplikacji: `POST /v1/chat/completions`, **bez streamu**, system + user jak `NotePromptBuilder.build` (szablon Standard, „Write the notes in Polish"), `Corrector.system` (PL), `AutoTitle.prompt` (3×2000 znaków). Dla odtworzenia „TTFB" mierzono też stream.

**TTFB w trybie niestreamowanym = czas całości** (nagłówki odpowiedzi przychodzą dopiero po końcu generacji — potwierdzone `t_headers == t_total` na Ollamie i llama.cpp we wszystkich wywołaniach). Limit transportowy (`timeoutInterval`, bezczynność) musi więc przekraczać CAŁE wywołanie. Przy streamie pierwszy znak przychodzi po prefillu: **TTFT** poniżej.

Materiały: **A** — 44 tys. znaków (≈17,4 tys. tokenów), 645 linii, zegar skalowany do 60 min, zbudowane z **4,4 tys. znaków unikalnego tekstu** prawdziwych sesji (bez dwóch sesji B1) zapętlonych ≈11×: **tylko do czasów/kontekstu**, nie do jakości. **B1** — prawdziwe sesje `2026-10-19…` (66 linii, 7,8 tys. znaków, 9,4 min; po wyłączeniu 8 linii echa) i `2026-10-15…` (7 linii) — jakość korekty/notatki, tylko liczby. **B2** — **syntetyczny** dialog PL (28 wypowiedzi, 3 tys. znaków, 10 linii z błędami ASR wpisanymi celowo, wzorzec znany).

Skróty: P = tokeny promptu, O = tokeny odpowiedzi; dec = tok/s generacji; load = 1-min load average.

| Serwer / model | Wywołanie | Całość | TTFT (stream) | P / O | dec | load |
|---|---|---|---|---|---|---|
| llama.cpp ministral (Q4_K_M) | notatka B1 | 40 s | 26,5 s | 3424 / 206 | 15 | 3,8 (swift 2) |
| | korekta B1 partia 1 (6171 zn.) | 172 s niestream / 227 s stream | 26,2 s | 2390 / 1667…2289 | 10–11 | 3–4,5 |
| | notatka A (60 min) | **524 s** | **367 s** | 17413 / 1013 | 6,4 | 4,6 (swift 2) |
| llama.cpp bonsai, **bez myślenia** | tytuł (3×2000 zn.) | 15 s | – | 2402 / 14 | – | 4,1 |
| | notatka B1 | 62–72 s | 32 s | 3240 / 731…992 | 18 | 4,5–6,6 |
| | korekta B1 partia 1 | 133–150 s | 21 s | 2216 / 2106 | 15–16 | 2–7 |
| | mapa 7 tys. zn. | 143–167 s | – | 2560 / 2100–2430 | 15 | 1,7–2 |
| llama.cpp bonsai, **z myśleniem** | notatka B1 | **465 s, ucięta** `length` | 47 s do 1. znaku rozumowania, **452 s do 1. znaku odpowiedzi** | 3237 / 6000 (rozumowanie 19,5 tys. zn., odpowiedź 812) | 13 | 5,5 |
| Ollama (env 24576) bonsai, bez myślenia | tytuł | 26 s | – | 2401 / 14 | – | 2,8 (swift 9) |
| | notatka B1 | 73–86 s | 26,5 s | 3241 / 830…1086 | 18 | 2–11 |
| | korekta B1 partia 1 | 126–154 s | 26 s | 2215 / 2109 | 14–16,5 | 2,7–7,8 |
| Ollama (env 24576) ministral | notatka B1 | 198 s | 62 s | 3426 / 1143 | 8 | 7 |
| | korekta B1 partia 1 | **277 s** | 41 s | 2389 / 1992 | 7 | **56** (swift 18) |
| Ollama app (4096) bonsai, **z myśleniem** (stan domyślny) | tytuł | **126 s, `length`, odpowiedź pusta** | – | 2398 / 1698 (wszystko rozumowanie) | – | 14 |
| Ollama app (4096) ministral | notatka B1 | 126 s, **`length` po 1024 tokenach** | – | 3424 / 1024 | – | 9,6 |
| | korekta B1, partia 6000 zn. | 125 s, `length` po 1024 tokenach, 24 z 49 linii | – | 2390 / 1024 | – | 14 |
| Ollama app (4096) bonsai bez myślenia | korekta B1 partia 1 | 143 s, **`length` na granicy kontekstu**, 45 z 49 linii | – | 2217 / 1879 (P+O = 4096) | – | – |
| llama.cpp (-c 4096) bonsai bez myślenia | korekta B1 partia 1 | 118 s, `length`, `truncated = 1`, 45 z 49 linii | – | 2217 / 1879 | – | – |
| Zimny start modelu (Ollama) | pierwsze żądanie | +17–19 s | – | – | – | – |

Wnioski czasowe: generacja **14–18 tok/s** (bonsai, load ≤ 7), **10–15 tok/s** (ministral na llama.cpp), 6–8 tok/s pod obciążeniem >10. Prefill ≈ **130–170 tok/s** (tytuł: 2400 tokenów w 15 s), przy 17 tys. tokenów pod obciążeniem tylko ≈47 tok/s. Dlatego: korekta partii 6000 znaków to **2–2,5 min na czysto, 4,6 min pod obciążeniem** (dzisiejsze 120 s nie wystarcza — dokładnie to widać w istniejącym `corrected.json` z API: 1 z 2 partii „didn't answer within 120 s"), notatka z 60 min jednym przebiegiem ≈ 9 min (tego **nie** robić — wejście ≈17 tys. tokenów wymaga kontekstu ≥ ~20 tys.).

Wyjątek niestety istotny: **tytuł na `genesys-ministral3` przez llama.cpp bez `max_tokens` nie skończył się w ≥27 min** (16,6 tys. tokenów, brak EOS; przerwałem; w Ollamie chroni go `num_predict 1024` z Modelfile). Wywołanie „tytuł" (ma kończyć się jedną linią) **musi mieć `max_tokens`** (np. 64).

## 3. „Thinking", format, jakość

### 3.1 Jak serwery eksponują rozumowanie
| Serwer | Pole odpowiedzi (`/v1`, bez streamu i w deltach streamu) | Wyłączenie |
|---|---|---|
| Ollama 0.40.6 | `message.reasoning` (obok `content`; bez streamu — delty streamu przy myśleniu niezmierzone); `<think>` w `content` **nie** wystąpiło | `reasoning_effort: "none"` działa; `think: false` na `/v1` **ignorowane**, na natywnym `/api/chat` działa; `chat_template_kwargs` ignorowane |
| llama.cpp 0.7.0 | `message.reasoning_content` (bez streamu i w deltach streamu — zmierzone) | `reasoning_effort: "none"` **i** `chat_template_kwargs: {"enable_thinking": false}` działają; `think: false` ignorowane |
| oMLX | nie zmierzone; w `model_settings.json` użytkownika jest `chat_template_kwargs.enable_thinking=false` per model (konfiguracja po stronie serwera) | – |

`ThinkingStripper` obsługujący `<think>` wystarcza dla tych dwóch serwerów (rozumowanie idzie osobnym polem, a `chatContent` czyta tylko `content`), **ale**: (a) przy rozumowaniu ucinanym limitem `content` jest pusty (to „empty reply" — poprawny błąd, tylko kosztowny: 2 min); (b) jednorazowo zaobserwowałem dosłowny znacznik `[THINK]` w `content` przy bardzo krótkiej odpowiedzi ministrala (`max_tokens 5`); w pełnych przebiegach go nie było.

### 3.2 Wierność numeracji linii korekty (B1, prawdziwe dane, liczby)
`Corrector` numeruje wypowiedzi `indeks+1` i **pomija zaflagowane (echo)**, więc numery w partii mają **dziury** (w B1: 18, 22, 32). **Modele wypełniają dziury** — wyjście numerują ciągle (…17, 18, 19, 20…), przesuwając resztę o jeden: `parse` → `nil`, partia przepada. To nie błąd modelu, tylko własność formatu wejścia. Wyniki (partia 1: 49 linii, partia 2: 17 linii):

| Konfiguracja | partia 1 | partia 2 | uwagi |
|---|---|---|---|
| llama.cpp bonsai bez myślenia (temp. domyślna serwera) | **49/49 OK**, 48 identycznych z oryginałem | 17/17 OK, identyczne | ten sam przebieg dwukrotnie (niestream i stream) OK |
| Ollama bonsai bez myślenia (Modelfile: temp. 1, presence_penalty 1) | **`parse` = nil** (dziury wypełnione), przy lenient dopasowaniu 22 z 46 linii poza pasmem (przesunięcie) | 17/17 OK | wynik niedeterministyczny, n=1–2 |
| llama.cpp ministral | **nil** (28 z 49 linii; w osobnym przebiegu stream wyjście miało 6147 znaków, nie parsowano) | nil (11 z 17) | model gubi linie |
| Ollama ministral | nil (40 z 49), nil w stream | nil (12 z 17) | |
| Ollama 4096 (jakiekolwiek) | partia 6000 zn. **urwana** na granicy kontekstu → nil | – | patrz sekcja 5 |

Odsetek odrzuconych **linii** (`accepts`) w partiach, które się sparsowały: **0%** (llama.cpp bonsai: 66/66 linii B1; B2: 28/28 w każdej konfiguracji, która się sparsowała). Rzeczywisty ubytek to odrzucenie **całej partii**: B1 — llama.cpp bonsai 0 z 2 partii, Ollama bonsai 1 z 2, ministral 2 z 2 (obie serwery). Sugestia do T12 (do decyzji): numerować linie w partii **ciągle 1..N** i mapować z powrotem — usuwa tę klasę błędu.

### 3.3 Jakość poprawek (B2 syntetyczny, 10 linii z błędami, 18 poprawnych)
| Konfiguracja | naprawione z 10 | zepsute z 18 poprawnych (jakakolwiek zmiana) |
|---|---|---|
| llama.cpp bonsai, partia 6000 / 1500 zn. | 3 / 6 | 2 / 4 |
| Ollama bonsai, partia 6000 / 1500 zn. | **7** / 1 | **7** / 2 |
| llama.cpp ministral, 6000 / 1500 | 2 / 0 | 4 / 3 |

Przykłady szkód (syntetyczne): „pierwszego grudnia" → „pierwszy stycznia" (zmiana daty, Ollama bonsai, temp. 1), „na miesiąc" → „na month", „dwudziestego" → „dwudziestogo"/„dwudziestocy" (zmyślone formy), „atrapę" → „atrapy". **Wszystkie te zmiany przechodzą `accepts`.** Poprawki trafne: „wdrorzenia" → „wdrożenia" (llama.cpp), przecinki przed „że"/„ile", „kopi" → „kopii", „produkcje" → „produkcję". Wniosek: `bonsai-2` (Q2_0) **popełnia merytoryczne szkody w korekcie** także na dobrych danych; wyższa temperatura z Modelfile Ollamy (temp. 1 + presence_penalty 1) wyraźnie pogarsza. Jakościowo tylko n=1–2 na komórkę.

Referencja bez klucza (stare artefakty z aplikacji, tylko liczby): korekta przez `deepseek/deepseek-v4.1-flash` tej samej sesji B1 — partia 1 (49 linii) nieudana (limit 120 s), partia 2 (17 linii): zmieniono **6 linii** (podobieństwo 0,90–1,00); lokalny bonsai zmienił 0 z 17, więc jest zachowawczy. Notatka API: 6098 znaków (szablon Weekly team) vs lokalne 2,6–3,8 tys. (Standard) — inna konfiguracja, więc **nie jest to porównanie**. **Baseline API: nie zmierzony (potrzebny klucz użytkownika).**

### 3.4 Notatka (B1, tylko liczby)
- bonsai bez myślenia (oba serwery): tytuł `# …` w pierwszej linii (zgodnie z promptem), 3 sekcje `##`, po polsku, 2,6–3,8 tys. znaków; llama.cpp: 9 punktów, Ollama: 18.
- ministral (fine-tune użytkownika): **łamie format** (zaczyna od `## …` zamiast tytułu `# …`), 0,65–3,5 tys. znaków, dużo zmienności; **Modelfile `num_predict 1024` ucina odpowiedź** (`finish=length`, 3070 znaków) — wpływa też na korektę i mapę. Ten model to fine-tune pod Genesysa, więc jego jakość nie reprezentuje Ministrala 3.
- Notatka A (60 min, llama.cpp ministral): 3111 znaków, TTFT 367 s.

## 4. Ollama — kontekst, sterowanie, wykrywanie

| Pytanie | Wynik (zmierzone) |
|---|---|
| Domyślny `num_ctx` | **4096** (`ollama ps`, `/api/ps` → `"context_length":4096`); dokumentacja Ollamy: 4k poniżej 24 GB VRAM |
| Wejście dłuższe niż `num_ctx` | **HTTP 400**, `/v1`: `{"error":{"message":"request (6057 tokens) exceeds the available context size (4096 tokens), try increasing it","type":"invalid_request_error","param":null,"code":null}}`; natywnie `{"error":"request (5620 tokens) exceeds the available context size (4096 tokens), try increasing it"}`. **Brak cichego obcięcia wejścia.** Sprawdzone na `genesys-ministral3`; na `bonsai-2` wejścia nie testowano (wyjście — tak). |
| Czy `/v1/chat/completions` honoruje `options.num_ctx` | **Nie** (ani `options.num_ctx`, ani `num_ctx` na wierzchu ciała; `ollama ps` bez zmian: 4096). Natywny `/api/chat` z `options.num_ctx: 8192` — **tak** (przeładowanie modelu z 8192). |
| `OLLAMA_CONTEXT_LENGTH` | **Działa także dla `/v1`** (drugi `ollama serve` na 11435 z 8192: wejście 5624 tokenów przeszło; z 24576 działa wszystko z tego raportu). Wymaga restartu serwera. |
| `PARAMETER num_ctx` w Modelfile | **Działa dla `/v1`** (model pochodny z `num_ctx 8192`: wejście 5625 tokenów przeszło, `ollama ps` → 8192). Uwaga: Modelfile przenosi też `num_predict`, `temperature` itd. na `/v1`. |
| Suwak „Context length" w aplikacji Ollamy | **Niezweryfikowane** (nie ruszałem ustawień użytkownika); istnieje wg dokumentacji. |
| `POST /api/show` (`{"model": "…"}`; wymaga nazwy — bez niej 400 „model is required") | Zwraca **maksimum modelu** (`model_info.llama.context_length` = 262144 oraz `qwen35.context_length` = 262144), NIE efektywny kontekst; `parameters` pokazuje `num_ctx` tylko gdy Modelfile go ustawia. Do wykrywania efektywnego kontekstu **bezużyteczne** (nigdy nie obniży). |
| `GET /api/ps` | Dla **załadowanego** modelu zwraca **efektywny** `context_length` (4096 / 8192 / 24576) — lepsze źródło niż `/api/show`; pusta lista, gdy nic nie załadowano. |
| `GET /props` na Ollamie | 404. |
| Port | 11434, adres z `/v1` w `Provider.baseURL`; `/api/*` leży poza `/v1`. |

## 5. llama.cpp — kontekst

| Pytanie | Wynik |
|---|---|
| Domyślny kontekst | **zależny od pamięci** (auto-fit): `n_ctx = 45824` przy 4 slotach (kv_unified), model ma `n_ctx_train 262144`. Z `-c 8192 -np 1` → 8192. |
| `GET /props` (poza `/v1`) | `default_generation_settings.n_ctx` = **efektywny kontekst na slot** (45824 / 8192 / 24576 / 4096 w próbach), `total_slots`, `model_alias`, `model_path`. `GET /v1/models` ma też `data[0].meta.n_ctx` (efektywny) i `n_ctx_train` (maksimum). Brak `/props` w innych serwerach. |
| Wejście dłuższe niż kontekst | **HTTP 400**: `{"error":{"code":400,"message":"request (11535 tokens) exceeds the available context size (8192 tokens), try increasing it","type":"exceed_context_size_error","n_prompt_tokens":11535,"n_ctx":8192}}` — stabilny marker `exceed_context_size_error` + liczby. |
| Wyjście przekraczające kontekst | HTTP 200, `finish_reason: "length"`, `truncated = 1` w logu serwera (jak Ollama). |

## 6. oMLX 0.7.0

- **Port: 8000 — potwierdzony z trzech źródeł:** `config.json` aplikacji (`"port": 8000`), `~/.omlx/settings.json` (`server.port 8000`, `host 0.0.0.0` — czyli **nasłuch nie tylko na loopbacku**), domyślny `--port` w CLI; `omlx-cli serve` faktycznie słuchał na 127.0.0.1:8000. Aplikacja po uruchomieniu **nie wystartowała serwera** sama (`auto_start_on_launch: false`; wymaga „Start" w menu — nie klikałem). Uruchamiałem serwer z `--base-path` w scratchpadzie (nie ruszałem `~/.omlx`).
- **Autoryzacja:** konfiguracja użytkownika ma ustawiony klucz API (nie czytałem go, nie używałem); stare logi: `GET /v1/models → 401: API key required`. Wpis `omlx` z `needsKey: false` (plan T11) **nie zadziała** u użytkownika bez klucza w presecie dostawcy — T11 musi dopuścić opcjonalny klucz.
- **Brak użytecznego modelu:** `model_dirs` aplikacji wskazują puste katalogi HF (Ministral-3-8B-Instruct-2512 w ogóle nie ma; Qwen3.5-9B i gemma-4-e4b to 0 B). Jedyny kompletny model MLX, `gemma-3-12b-it-qat-4bit` (7,85 GB), dostał **HTTP 507**: `{"error":{"message":"Model 'gemma-3-12b-it-qat-4bit' (7.85GB) does not fit under the dynamic memory ceiling (3.92GB). Close other apps to free RAM (static cap is 13.00GB but only 3.79GB is reclaimable right now), raise memory_guard_tier (safe → balanced → aggressive), or use a smaller model.","type":"server_error","param":null,"code":null}}` — także z `--memory-guard off` i `aggressive` (sufit liczony z pamięci do odzyskania). Na 16 GB przy normalnym pulpicie model 12B nie wchodzi; nie zamykałem cudzych aplikacji.
- **Niezmierzone w całości:** czas, TTFB, thinking, jakość, przepełnienie kontekstu (kod/treść), wykrywanie kontekstu. Z konfiguracji: `max_model_len` w `/v1/models` = **maksimum modelu** (131072 dla gemmy), nie efektywne; w ustawieniach użytkownika `sampling.max_context_window 32768` i `max_tokens 32768` (domyślne `max_tokens` serwera!). **Brak znanego endpointu efektywnego kontekstu** — dla oMLX zostaje wartość nastawialna.
- Pośrednio (stare logi oMLX użytkownika, sierpień 2026, inne modele, których wag już nie ma): Bielik-4.5B 8-bit ≈ 17–19 tok/s, Bielik-Minitron-7B 4-bit ≈ 22–24 tok/s, gemma-4-E4B 4-bit ≈ 21–28 tok/s — rząd wielkości zbliżony do llama.cpp/Ollamy.
- Aplikację oMLX uruchomiłem tylko po to, by sprawdzić port, i zakończyłem sygnałem (AppleScript „quit" został anulowany przez system/użytkownika, nic nie zatwierdzałem).

## 6a. Znaki na token i wyjście mapy

**Znaki na token (polski, liczniki użycia serwerów):**
- Ministral (tokenizer Mistral): **2,65–2,7** (notatka A vs B1: Δ 37086 znaków / Δ 13989 tokenów = 2,65; odpowiedź korekty 6147 zn. / 2289 tok. = 2,69; 4448/1667 = 2,67).
- Qwen3.5 (bonsai): **2,9–2,95** (odpowiedź korekty 6172 zn. / 2110 tok. = 2,93; wejście korekty 2,9).
- Zawyżone o prefiksy `[m:ss] Me:` w wejściu notatki (≈2,75–2,8 dla Ministrala). Gemma/Llama nie zmierzone.
- Prompt systemowy notatki: 1559 znaków ≈ 580 tokenów; `Corrector.system`: 371 znaków ≈ 140 tokenów.
- Długość odpowiedzi notatki: 650–3841 znaków ≈ 220–1300 tokenów, także dla 60 min (3111 zn.).

**Mapa („condense, zachowaj `[m:ss] Me|Them:`")**, części 6,6–7,0 tys. znaków (≈100 linii):
| Konfiguracja | wyjście / wejście | uwagi |
|---|---|---|
| bonsai, prompt bez celu długości (llama.cpp) | 0,99 i 0,83 | prawie nie skraca |
| bonsai, ten sam prompt (Ollama) | 0,26 i 0,95 | duży rozrzut |
| bonsai, prompt „AT MOST 40% of the input" (`max_tokens 2400`, nie osiągnięty) | **0,12 / 0,24 / 0,33**, `stop` | format linii 100% (23/23, 53/53, 73/73), czasy 38–84 s |
| ministral (oba serwery) | 0,41–0,50 oraz **2,0 (ucieczka: 6000 tokenów, 381–389 linii, `length`)**; w jednym przebiegu 0 linii w formacie | bez `max_tokens` byłby bez końca |

Uwaga: materiał A to zapętlony tekst (łatwy do skracania; zaniża wyjście), więc rozkład dla realnego spotkania może być wyższy.

## 7. WARTOŚCI PROPONOWANE dla T10–T13 (do wyboru użytkownika — STOP)

Legenda: **[M]** zmierzone, **[Z]** zgadnięte/wyprowadzone, **[N]** niezweryfikowane.

### Limity czasu (T10, `ChatLimits.for(provider, role:)`, lokalne = loopback)
| Rola | miękki (`withDeadline`) | transportowy (`timeoutInterval`) | podstawa |
|---|---|---|---|
| notatka (jedno wywołanie) | **600 s** [Z z M] | **660 s** | M: B1 40–198 s; A (17,4 tys. tokenów) 524 s pod obciążeniem; zimny start +19 s |
| korekta, **na partię** | **300 s** [Z z M] | **330 s** | M: partia 6000 zn. 126–154 s (czysto), 277 s (load 56); mniejsze partie proporcjonalnie krócej |
| tytuł | **120 s** [Z] | **150 s** | M: 15–26 s bez myślenia; z myśleniem >126 s i pusto |
| mapa, **na wywołanie** | **300 s** [Z z M] | **330 s** | M: 38–84 s (z celem 40%), 143–167 s (bez), 179–592 s (ucieczki ministrala) |

Transport zawsze ≥ miękki + 30 s i **musi obejmować całe wywołanie** (bez streamu TTFB = całość) [M]. Alternatywa do rozważenia w T10: stream + limit bezczynności (TTFT 21–62 s dla 2–3,5 tys. tokenów; 367 s dla 17,4 tys.) [M, decyzja użytkownika]. Czas zależy od obciążenia maszyny 1,5–3× [M] — stąd marginesy.

**`max_tokens` w każdym wywołaniu lokalnym [M — wymaga T10]:** tytuł 64 [Z]; korekta ≈ 1,3 × (tokeny wejścia partii) [Z]; mapa — poniżej; notatka ≈ 4096 [Z; M: odpowiedzi do 1300 tokenów]. **`finish_reason == "length"` = błąd/ostrzeżenie, nie sukces** [M].

### Budżet kontekstu (T12)
- **Domyślne `contextTokens`: 4096** [M: tyle ma Ollama w aplikacji; wyższa wartość domyślna daje HTTP 400 u domyślnej Ollamy]. Konsekwencja [M]: przy 4096 realne wejście notatki ≈ (4096 − 580 − 1500) × 2,4 ≈ 4,8 tys. znaków (≈6 min mowy); 60-minutowe spotkanie **nie da się streścić** nawet 3-poziomowym reduce (46 tys. → 23 → 11,5 → 5,7 tys. zn. > 4,8 tys.). Interfejs powinien jasno podpowiadać **podniesienie kontekstu do ≥ 16384** (`OLLAMA_CONTEXT_LENGTH`, suwak w aplikacji Ollamy [N], Modelfile `num_ctx`; llama.cpp `-c`); 24576 działało na tej maszynie z bonsai i ministralem [M].
- **`charsPerToken`: 2,4** [Z: mierzone 2,65 (Mistral) i 2,9 (Qwen3.5), margines ≈10%, inne tokenizery niezmierzone]. Wartość 1,5 ze szkicu planu jest zbyt zachowawcza (budżet o 40% mniejszy niż potrzeba).
- **Rezerwa — nie jedna proporcja, lecz dwie reguły [M, STOP dla T12, bo zmienia „jeden `inputChars`" ze speca §11.9]:**
  - **notatka / reduce:** `inputChars = (tokens − 2400) × charsPerToken`; 2400 tokenów = system ≈580 + odpowiedź do ≈1500 + margines na „My notes"/kontekst użytkownika (nie mierzone) [Z z M]. Odpowiednik „reserveChars" ≈ 2400 × 2,4 ≈ 5800 znaków **stałych** (to 59% budżetu przy 4096, 10% przy 24576), nie 40%.
  - **korekta i mapa (wyjście ≈ wejście):** `inputChars = ((tokens − 250) / 2) × charsPerToken` — połowa kontekstu na wejście [M: partia 6000 zn. = 2217 + 2110 = 4327 tokenów > 4096 → urwana]. Przy 4096 ⇒ ≈ 4,6 tys. znaków na partię; `Corrector.maxBatchChars` powinno być ≤ tego, a przy braku budżetu (API) zostaje 6000.
- **Limit wyjścia mapy (`max_tokens`):** `min(0,5 × tokeny wejścia części, …)` ≈ **1350 dla części 7 tys. znaków** [Z; M: z promptem „≤ 40%" wyjście było 0,12–0,33 wejścia (n=3, jeden model, materiał zapętlony → optymistyczne); bez celu długości 0,26–1,0, ministral do 2,0]. Prompt mapy **musi** zawierać cel długości („at most 40% of the input"), a `finish=length` = część nieudana (nie wysyłać dalej). Suma wyjść mapy ≈ 0,3–0,5 wejścia ⇒ dla 60 min (46 tys. zn.) reduce ≈ 14–23 tys. zn. ≈ 6–10 tys. tokenów ⇒ wymaga kontekstu ≥ ~12 tys. (≥ 8192 + hierarchia) [Z z M].
- **Wykrywanie kontekstu (tylko obniżanie, spec §5.2 pkt 3)** [M]:
  - Ollama: `GET <host>/api/ps` → `models[].context_length` (**efektywny**, tylko dla załadowanego modelu; dopasuj po nazwie, bez `:latest` w porównaniu); `/api/show` zwraca tylko maksimum modelu (262144) ⇒ do obniżania **nie przydaje się**, ewentualnie jako informacja.
  - llama.cpp: `GET <host>/props` → `default_generation_settings.n_ctx` (efektywny na slot); zapasowo `GET /v1/models` → `data[0].meta.n_ctx`.
  - oMLX: **brak** endpointu efektywnego kontekstu [N] (`/v1/models` → `max_model_len` = maksimum modelu); tylko wartość nastawialna.
  - `base = provider.contextTokens ?? 4096`, `tokens = min(base, wykryty)`; wykryta wartość większa niż domyślna nie podnosi (tak: spec). Do rozważenia przez użytkownika: ponieważ `/api/ps` i `/props` zwracają wartości **efektywne**, bezpieczne byłoby też podnoszenie domyślnej do wykrytej (z sufitem) — zmieniłoby to decyzję speca, więc **tylko propozycja**.
  - `baseURL` zawiera `/v1` ⇒ odetnij je dla `/api/*` i `/props` [M].
- **Rozpoznawanie przepełnienia (`ContextError.isContextOverflow`) [M]:** HTTP 400 z treścią zawierającą „exceeds the available context size" (Ollama `/v1`: `error.type = invalid_request_error`; llama.cpp: `error.type = exceed_context_size_error`, pola `n_prompt_tokens`, `n_ctx`) — obecna lista słów („context") wystarcza dla obu; dodatkowo **`finish_reason == "length"` przy HTTP 200** (nowy przypadek, nie jest błędem HTTP). oMLX: przepełnienia nie zmierzono [N]; błąd pamięci modelu to **HTTP 507** `server_error` „does not fit under the dynamic memory ceiling" — inny komunikat niż „serwer nie działa" i niż „kontekst" (T11).

### Pozostałe wartości klienta
- **Wyłączenie myślenia:** wysyłać `reasoning_effort: "none"` dla lokalnych [M: Ollama i llama.cpp; zachowanie na serwerach/modelach bez „thinking" niezmierzone — [N]]. Bez tego bonsai jest nieużyteczny (sekcja 0, pkt 4).
- **Temperatura korekty:** niska (≈0–0,2) [Z; M: temp. 1 z Modelfile Ollamy zmieniła daty i słowa] — klient dziś nie wysyła `temperature`, więc o wyniku decydują domyślne parametry serwera/Modelfile.
- **Numeracja linii korekty:** ciągła 1..N z mapowaniem z powrotem [M: dziury powodują przesunięcie] — propozycja do T12.
- **Bramka `accepts`:** pasmo długości nie łapie zmian merytorycznych [M] — jeśli bramka ma chronić „zmyślone treści" (spec §2), potrzebna dodatkowa (np. porównanie liczb/dat), to decyzja użytkownika, nie T10–T13.

### Modele rekomendowane
- **Notatka:** `bonsai-2` (9B Q2_0) **tylko z wyłączonym myśleniem** [M]: poprawny format (tytuł, sekcje, PL), 14–18 tok/s, 62–86 s na notatkę z 10 min; **ostrzeżenie:** kwantyzacja Q2_0.
- **Korekta:** **żadnego modelu nie rekomenduję** [M]: bonsai bez myślenia daje 100% poprawnej numeracji tylko część razy i potrafi zmienić datę/słowo (przechodzi bramkę); ministral (fine-tune) gubi linie i format. Wymaga decyzji użytkownika, czy lokalna korekta ma w ogóle wejść w 2.0b, czy z mocniejszym modelem (np. 8B Q4 ogólnego przeznaczenia — niedostępny lokalnie, nie pobierałem).
- **`genesys-ministral3`:** nie polecać (fine-tune Genesys; ucieczka generacji, `num_predict 1024`, łamie format).
- **oMLX:** brak rekomendacji (niezmierzone; 12B nie wchodzi w pamięć).

## 8. Czego NIE zweryfikowałem
- oMLX: czas, TTFB, thinking, jakość, przepełnienie kontekstu, wykrywanie kontekstu (brak modelu, który się zmieści; 507).
- Baseline API (potrzebny klucz). Notatka/korekta jakościowo tylko na n=1–2 na komórkę; nie ma statystyki, wyniki są niedeterministyczne.
- Suwak „Context length" w aplikacji Ollamy (nie zmieniałem ustawień).
- Wejście dłuższe niż kontekst na `bonsai-2` (tylko na `genesys-ministral3`); strumieniowy wariant przepełnienia; zachowanie `reasoning_effort` poza modelami „thinking".
- Czasy w warunkach ciszy: maszyna była obciążona (load do 107, swap ≈7 z 8 GB) — wartości pesymistyczne, rząd wielkości 1,5–3×.
- Jakość na materiale rzeczywistym: tylko jedna sesja (74 wypowiedzi) i druga mała; korpus rzeczywisty 14 tys. znaków; materiał A to pętla 4,4 tys. znaków unikalnego tekstu (nadaje się wyłącznie do czasów/kontekstu).
- Gemma/Llama tokenizery (znaki na token).
