import Foundation
import YascribeSessionFormat

/// Minimalny pisarz CAF: PCM Int16 LE, przeplatany, blok `data` o rozmiarze -1.
/// Nagłówek jest kompletny od pierwszego bajtu, więc plik da się odczytać
/// w każdej chwili — także po `kill -9` (T7). Układ: `CAFLayout`.
public final class CAFWriter {
    public let url: URL
    public let sampleRate: Double
    public let channels: Int
    public private(set) var framesWritten = 0
    private let handle: FileHandle

    public init(url: URL, sampleRate: Double, channels: Int) throws {
        precondition(sampleRate > 0 && channels > 0)
        self.url = url
        self.sampleRate = sampleRate
        self.channels = channels
        FileManager.default.createFile(atPath: url.path, contents: Self.header(sampleRate: sampleRate, channels: channels))
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    static func header(sampleRate: Double, channels: Int) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func i64(_ v: Int64) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func fourCC(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        fourCC("caff"); u16(1); u16(0)
        fourCC("desc"); i64(32)
        withUnsafeBytes(of: sampleRate.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        fourCC("lpcm")
        u32(2) // kCAFLinearPCMFormatFlagIsLittleEndian
        u32(UInt32(CAFLayout.bytesPerFrame(channels: channels))) // bajtów na pakiet
        u32(1) // ramek na pakiet
        u32(UInt32(channels))
        u32(16)
        fourCC("data"); i64(-1) // rozmiar nieznany: do końca pliku
        u32(0) // licznik edycji
        assert(d.count == CAFLayout.headerSize)
        return d
    }

    /// Dopisuje próbki przeplatane. Liczba próbek musi być wielokrotnością liczby kanałów.
    public func append(_ samples: [Int16]) throws {
        precondition(samples.count % channels == 0, "niepełna ramka")
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { buf in
            Data(buffer: UnsafeBufferPointer(start: buf.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self) },
                                             count: buf.count * CAFLayout.bytesPerSample))
        }
        try handle.write(contentsOf: data)
        framesWritten += samples.count / channels
    }

    public func appendSilence(frames: Int) throws {
        var left = frames
        let block = 4_800
        while left > 0 {
            let n = min(left, block)
            try handle.write(contentsOf: Data(count: n * CAFLayout.bytesPerFrame(channels: channels)))
            framesWritten += n
            left -= n
        }
    }

    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }
}
