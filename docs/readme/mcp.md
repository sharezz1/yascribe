# Agenci AI i serwer MCP

Yascribe ma wbudowany serwer [MCP](https://modelcontextprotocol.io) (Model Context Protocol) na stdio.
Dzięki niemu Claude Code, Codex, OpenCode, Hermes i pi mogą czytać Twoje spotkania: listę z wyszukiwaniem,
transkrypt i notatkę, a także dostać całe spotkanie jako markdown.

Serwer **tylko czyta**. Nie zmienia ustawień, nie tworzy, nie poprawia i nie usuwa plików w katalogu danych.
Nie uruchamia też żadnych modeli ani podsumowań — to robi wyłącznie aplikacja.

## Włącz dostęp

Domyślnie serwer nie wydaje żadnych danych. Żeby go włączyć:

1. Otwórz Yascribe → **Settings** → **Agent access (MCP)**.
2. Włącz **Allow AI agents to read meetings** i kliknij **Save**.

Przełącznik zapisuje zgodę w `settings.json` tego katalogu danych, z którego czyta serwer.
Wyłączenie (albo usunięcie lub uszkodzenie `settings.json`) natychmiast zamyka dostęp: każde narzędzie
zwraca wtedy błąd „Agent access is off…”.

**Prywatność.** Co agent przeczyta, trafia do modelu tego dostawcy, na jego zasadach — tak jak każdy inny
tekst wklejony do czatu. Włączaj dostęp tylko dla agentów, którym ufasz, i wyłączaj go, gdy nie jest potrzebny.

## Podłącz klienta

Serwer jest częścią paczki: `/Applications/Yascribe.app/Contents/MacOS/yascribe-cli`, a uruchamia go
argument `mcp`. Jeśli trzymasz aplikację gdzie indziej, użyj swojej ścieżki.

### Claude Code

```sh
claude mcp add --scope user yascribe -- /Applications/Yascribe.app/Contents/MacOS/yascribe-cli mcp
```

### Codex

```sh
codex mcp add yascribe -- /Applications/Yascribe.app/Contents/MacOS/yascribe-cli mcp
```

albo w `~/.codex/config.toml`:

```toml
[mcp_servers.yascribe]
command = "/Applications/Yascribe.app/Contents/MacOS/yascribe-cli"
args = ["mcp"]
```

### OpenCode

```sh
opencode mcp add yascribe --global -- /Applications/Yascribe.app/Contents/MacOS/yascribe-cli mcp
```

albo w `opencode.json`:

```json
{ "mcp": { "servers": { "yascribe": { "type": "local", "command": ["/Applications/Yascribe.app/Contents/MacOS/yascribe-cli", "mcp"] } } } }
```

### Hermes

`~/.hermes/config.yaml`:

```yaml
mcp_servers:
  yascribe:
    command: /Applications/Yascribe.app/Contents/MacOS/yascribe-cli
    args: ["mcp"]
```

W trwającej sesji: `/reload-mcp`.

### pi

```sh
pi mcp add yascribe -- /Applications/Yascribe.app/Contents/MacOS/yascribe-cli mcp
```

Zapis trafia do `~/.pi/agent/mcp.json`; w sesji: `/reload`.

### Dane deweloperskie

Serwer czyta ten sam katalog co aplikacja: `~/Library/Application Support/Yascribe`, a przy ustawionej
zmiennej `YASCRIBE_DATA_DIR` — wskazany przez nią katalog. W konfiguracji klienta dodaj ją w `env`, np.:

```json
{ "mcp": { "servers": { "yascribe": { "type": "local", "command": ["/Applications/Yascribe.app/Contents/MacOS/yascribe-cli", "mcp"], "environment": { "YASCRIBE_DATA_DIR": "/ścieżka/do/.devdata" } } } } }
```

Zgoda i `recordingsPath` pochodzą z `settings.json` tego katalogu, który serwer czyta. Dwa profile
wskazujące te same nagrania to konfiguracja deweloperska: wtedy każdy z nich ma własną zgodę.

## Narzędzia

Wszystkie trzy są tylko do odczytu i czytają dane świeżo przy każdym wywołaniu — zmiany w aplikacji widać
od razu, bez restartu serwera. Daty są w ISO 8601 w UTC.

### `list_meetings`

Lista spotkań od najnowszych, z wyszukiwaniem.

| Argument | Opis |
|---|---|
| `query` | podciąg bez rozróżniania wielkości liter; szuka w tytule, Twoich notatkach, podsumowaniu i transkrypcie (z korektą i słownikiem) |
| `folder` | nazwa folderu; nieznana nazwa to błąd |
| `limit` | 1–100, domyślnie 20 |
| `offset` | od 0, domyślnie 0 |

Wynik to JSON: `total`, `offset` i `meetings` z polami `id`, `title`, `startedAt`, `durationMinutes`,
`folder`, `hasTranscript`, `transcriptVersion` (`corrected`/`original`/`null`), `hasSummary`, `overview`.

### `get_meeting`

Jedno spotkanie jako markdown: tytuł, data, czas, folder, wersja transkryptu, model podsumowania,
a potem sekcje „Overview”, „Summary”, „My notes” i — na życzenie — „Transcript”.

| Argument | Opis |
|---|---|
| `id` | nazwa katalogu spotkania (z `list_meetings`) |
| `include_transcript` | `true` dołącza transkrypt; domyślnie `false` |

To jest eksport do markdown — agent zapisuje plik sam, według Twojego polecenia. Przy transkrypcie dłuższym
niż 2000 linii wynik kończy się informacją o obcięciu i wskazówką, żeby dopobrać resztę przez `get_transcript`.

### `get_transcript`

Transkrypt jednego spotkania, stronicowany.

| Argument | Opis |
|---|---|
| `id` | nazwa katalogu spotkania |
| `version` | `corrected` (domyślnie) albo `original`; brak poprawionego daje oryginalny, jak w aplikacji |
| `offset` | od 0, domyślnie 0 |
| `limit` | 1–2000, domyślnie 500 |

Każda linia ma postać `[H:MM:SS] Mówca: tekst`, a wyciszenia trafiają między wypowiedzi jako osobne linie —
dokładnie to, co daje przycisk „Copy” w aplikacji. Gdy jest więcej linii, ostatnia linia mówi
`Next: offset <n>`.

## Rozwiązywanie problemów

- **„Agent access is off…”** — włącz przełącznik w Settings i zapisz.
- **Pusto, choć masz spotkania** — sprawdź, czy klient uruchamia serwer z tym samym `YASCRIBE_DATA_DIR`
  (albo bez niego, jeśli używasz zwykłego katalogu).
- **Klient nie widzi narzędzi** — uruchom ręcznie i sprawdź, czy odpowiada:
  `printf '{"jsonrpc":"2.0","id":1,"method":"ping"}\n' | /Applications/Yascribe.app/Contents/MacOS/yascribe-cli mcp`.
  Na stdout ma pojawić się dokładnie `{"id":1,"jsonrpc":"2.0","result":{}}`.
