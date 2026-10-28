# SpeexDSP 1.2.1

Minimalny zestaw AEC/preprocesora/FFT z niezmienionego oficjalnego wydania:
https://downloads.xiph.org/releases/speex/speexdsp-1.2.1.tar.gz

SHA-256: `8c777343e4a6399569c72abc38a95b24db56882c83dbdb6c6424a5f4aeb54d3d`.
Pliki źródłowe w `vendor/` i `include/speex/` zachowują oryginalne prawa autorskie.
`vendor/config.h` wygenerowano dla floating point / smallft, bez SIMD.
Licencja dystrybucji jest w `Resources/ThirdPartyNotices/SpeexDSP.txt` i trafia do paczki aplikacji.
`AEC.c` i `include/YascribeAEC.h` są adapterem aplikacji.

Dokumentacja API: https://www.speex.org/docs/manual/speex-manual/node7.html#SECTION00740000000000000000
Preprocesor opóźnia sygnał o ramkę 256 próbek; adapter opróżnia bufor i kompensuje
to opóźnienie. DENOISE pozostaje włączone, bo steruje również tłumieniem resztkowego
echa; zwykłe tłumienie szumu i AGC są wyłączone. Stałe przetwarzania i regułę
wykrywania echa wersjonuje `OfflineAEC.Configuration.algorithmVersion`.
