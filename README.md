# Yascribe

Natywna aplikacja macOS do notatek ze spotkań, która rozumie po polsku. Nagrywa dwa kanały osobno (dźwięk systemowy przez process tap Core Audio i mikrofon), transkrybuje je lokalnie (Parakeet TDT v3 przez FluidAudio) albo przez API (OpenRouter, ElevenLabs) i robi z transkryptu notatkę modelem wybranym w presecie (także lokalnym: Ollama, llama.cpp, oMLX). Do rozmowy nie dołącza żaden bot.

*English: a native macOS meeting-notes app that records system audio and microphone as two separate tracks, transcribes locally or via API, and writes notes with a model you choose. The app UI is currently English; Polish UI is planned.*

Projekt jednoosobowy, w budowie. Interfejs aplikacji jest na razie po angielsku (polska wersja jest w planie), dokumenty w repo po polsku.

## Instalacja

1. Pobierz `Yascribe-<wersja>.zip` z [Releases](https://github.com/sharezz1/yascribe/releases/latest), rozpakuj i przeciągnij `Yascribe.app` do `/Applications`.
2. Aplikacja jest podpisana samopodpisanym certyfikatem i **nie jest notaryzowana**, więc macOS zapyta o zgodę przy pierwszym uruchomieniu (Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to"). Notaryzacja jest w planie.
3. Przy pierwszym nagraniu zatwierdź dostęp do mikrofonu, dźwięku systemowego i (opcjonalnie) kalendarza.
4. Aktualizacje: Yascribe → „Check for Updates…". Instalacja zawsze na Twoje kliknięcie i nigdy nie przerywa trwającego nagrania.

Wymagania: macOS 27.

## Dane i klucze

Wszystko jest lokalne: nagrania, transkrypty i notatki leżą w `~/Library/Application Support/Yascribe`. Klucze API trzymane są w pęku kluczy macOS i wpisujesz je sam w aplikacji. Do chmury trafia tylko to, co wybierzesz (transkrypcja i notatki przez API); transkrypcja Parakeetem i lokalne modele tekstowe działają bez sieci.

## Budowanie

Wystarczą Command Line Tools (Swift 6.4), bez Xcode.

```
swift package --disable-keychain resolve
scripts/run.sh          # buduje i uruchamia z danymi w .devdata/
scripts/test.sh         # jedyny sposób uruchamiania testów
scripts/bundle.sh       # składa .build/Yascribe.app
```

Opis modułów, zasady pracy i stan faz: [CLAUDE.md](CLAUDE.md); wymagania: [docs/wymagania.md](docs/wymagania.md).

## Licencja

Yascribe jest wolnym oprogramowaniem na licencji **GNU GPL v3** (plik [LICENSE](LICENSE)). Licencje zależności i atrybucje: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Copyright (C) 2026 Michał Przytulski
