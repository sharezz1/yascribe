import Foundation

public enum CAFReadError: Error, Equatable {
    case tooShort
    case notOurLayout(String)
}

/// Czytnik plików zapisanych przez `CAFWriter` — i tylko takich. Sprawdza nagłówek
/// bajt po bajcie, więc cudzy albo uszkodzony plik daje błąd zamiast śmieci.
///
/// Nie używa AVFoundation celowo: `AVAudioFile.read(into:)` potrafi oddać
/// mniej ramek niż pojemność bufora (📐 64 000 ramek w pliku, 63 454 z jednego
/// wywołania), a czytelnik, który o tym zapomni, po cichu obcina końcówkę ścieżki.
public struct CAFReader: Sendable {
    public let sampleRate: Double
    public let channels: Int
    public let samples: [Int16]

    public var frames: Int { samples.count / channels }

    public init(url: URL) throws {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.count >= CAFLayout.headerSize else { throw CAFReadError.tooShort }
        func fourCC(_ at: Int) -> String { String(decoding: d[at..<(at + 4)], as: UTF8.self) }
        func u32(_ at: Int) -> UInt32 { d[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        func u64(_ at: Int) -> UInt64 { d[at..<(at + 8)].reduce(0) { $0 << 8 | UInt64($1) } }
        guard fourCC(0) == "caff" else { throw CAFReadError.notOurLayout("magic") }
        guard fourCC(8) == "desc", u64(12) == 32 else { throw CAFReadError.notOurLayout("desc") }
        guard fourCC(28) == "lpcm" else { throw CAFReadError.notOurLayout("format") }
        guard u32(32) == 2, u32(48) == 16 else { throw CAFReadError.notOurLayout("int16 le") }
        guard fourCC(52) == "data", u64(56) == UInt64.max else { throw CAFReadError.notOurLayout("data -1") }
        let ch = Int(u32(44))
        guard ch > 0 else { throw CAFReadError.notOurLayout("channels") }
        sampleRate = Double(bitPattern: u64(20))
        channels = ch
        let body = d[CAFLayout.headerSize...]
        let count = (body.count / CAFLayout.bytesPerFrame(channels: ch)) * ch
        var out = [Int16](repeating: 0, count: count)
        _ = out.withUnsafeMutableBytes { body.copyBytes(to: $0, count: count * CAFLayout.bytesPerSample) }
        // ⚠️ Poprawka po recenzji (R6): na little-endian (arm64, x86_64) bajty pliku są już
        // w kolejności pamięci. Spike robił tu `out.map { Int16(littleEndian: $0) }` — drugą
        // kopię ~1 GB przy 85-minutowej ścieżce systemowej.
        #if _endian(big)
        samples = out.map { Int16(littleEndian: $0) }
        #else
        samples = out
        #endif
    }
}
