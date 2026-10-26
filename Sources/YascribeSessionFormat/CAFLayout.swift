import Foundation

/// Układ pliku CAF zapisywanego przez rdzeń nagrywania: PCM Int16 little-endian,
/// przeplatany, blok `data` o rozmiarze -1 („do końca pliku"). Dzięki temu plik
/// jest poprawny w każdej chwili, także po `kill -9` (spec rdzenia §5).
/// Wspólne dla pisarza (YascribeRecording) i czytelnika (podsumowanie po awarii).
public enum CAFLayout {
    /// 'caff' + wersja + flagi (8) + nagłówek 'desc' (12) + treść 'desc' (32)
    /// + nagłówek 'data' (12) + licznik edycji (4).
    public static let headerSize = 68
    public static let bytesPerSample = 2

    public static func bytesPerFrame(channels: Int) -> Int { channels * bytesPerSample }

    /// Liczba pełnych ramek w pliku o danym rozmiarze.
    public static func frames(fileSize: Int, channels: Int) -> Int {
        max(0, fileSize - headerSize) / bytesPerFrame(channels: channels)
    }
}
