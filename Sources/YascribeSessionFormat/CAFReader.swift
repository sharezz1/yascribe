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

    public init(url: URL) throws { try self.init(url: url, frames: nil) }

    public static func read(url: URL, frames: Range<Int>) throws -> CAFReader {
        try CAFReader(url: url, frames: frames)
    }

    public static func info(url: URL) throws -> (sampleRate: Double, channels: Int, frames: Int) {
        let reader = try CAFReader(url: url, frames: 0..<0)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return (reader.sampleRate, reader.channels, max(0, (size?.intValue ?? 0) - CAFLayout.headerSize) / CAFLayout.bytesPerFrame(channels: reader.channels))
    }

    private init(url: URL, frames: Range<Int>?) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= CAFLayout.headerSize else { throw CAFReadError.tooShort }
        try file.seek(toOffset: 0)
        let d = try file.read(upToCount: CAFLayout.headerSize) ?? Data()
        guard d.count == CAFLayout.headerSize else { throw CAFReadError.tooShort }
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
        let totalFrames = (Int(size) - CAFLayout.headerSize) / CAFLayout.bytesPerFrame(channels: ch)
        let selected = frames ?? 0..<totalFrames
        guard selected.lowerBound >= 0, selected.upperBound <= totalFrames else { throw CAFReadError.notOurLayout("frame range") }
        let stride = CAFLayout.bytesPerFrame(channels: ch)
        try file.seek(toOffset: UInt64(CAFLayout.headerSize + selected.lowerBound * stride))
        let byteCount = (selected.upperBound - selected.lowerBound) * stride
        let body = try file.read(upToCount: byteCount) ?? Data()
        guard body.count == byteCount else { throw CAFReadError.tooShort }
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
