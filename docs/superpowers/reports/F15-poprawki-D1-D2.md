# F15 — poprawki D1 i D2 po przeglądach (na polecenie użytkownika, 2026-10-15)

- **Commit:** `a6a7c0c`
- **`scripts/test.sh`:** `test.sh: 183/183 testów uruchomionych i zaliczonych.` (182 + 1 nowy `@Test`: `multiLineUtteranceIsSentAsOneLineSoItsTailIsNotLost`)
- **Mutacja:** usunięcie zamiany `\n` → spacja w `CorrectionBatches.render` → test pada na dwóch asercjach (jedna wypowiedź = jedna linia; `render` skleja `\r\n`/`\n`). Po cofnięciu `183/183`. Wykonane bezpośrednio, nie przez podagenta.

## D1 (przegląd T6)
`CorrectionBatches.render` skleja `\n` w wypowiedzi w spację, więc `parse` nie pomija ogona i korekta nie gubi treści. Wcześniej wypowiedź `"Akapit pierwszy długi.\nkoniec"` szła jako dwie linie, a linia bez `[` była ignorowana.

## D2 (przegląd T10)
`RecordingController` odświeża `micName` w sekundowym timerze (`CoreAudioDevices.defaultInputName() ?? micName`), bo `RawMicrophoneSource` podąża za domyślnym wejściem systemu (np. AirPods w trakcie nagrania). **Bez testu automatycznego** (sprzęt/CoreAudio) — **do potwierdzenia ręcznie w T13:** nagranie z rozwiniętą pigułką, zmiana domyślnego wejścia, nazwa w pigułce zmienia się w ciągu ~1 s.

## Plan
Licznik: tabela §3 przeglądu ma wiersz „po T12: poprawka D1" (+1 → 183), T13 oczekuje `183/183`. BACKLOG: obie pozycje oznaczone `[x]`.
