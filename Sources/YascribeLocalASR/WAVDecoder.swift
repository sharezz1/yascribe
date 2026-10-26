import Foundation

public struct WAVDecodeError: Error, Equatable, LocalizedError, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// WAV 16 kHz mono Int16 (jak `WAVEncoder`, także klipy sondy) → `[Float]` w -1…1. Inny format = błąd.
public enum WAVDecoder {
    public static func samples(_ wav: Data) throws -> [Float] {
        let b = [UInt8](wav)
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard b.count >= 12, Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WAVE".utf8) else {
            throw WAVDecodeError(message: "Not a WAV file.")
        }
        var format: (tag: Int, channels: Int, rate: Int, bits: Int)?
        var i = 12
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<i + 4], as: UTF8.self)
            let size = u32(i + 4)
            let body = i + 8
            if id == "fmt " {
                guard size >= 16, body + 16 <= b.count else { throw WAVDecodeError(message: "Malformed WAV fmt chunk.") }
                format = (u16(body), u16(body + 2), u32(body + 4), u16(body + 14))
            } else if id == "data" {
                guard let f = format else { throw WAVDecodeError(message: "WAV data before fmt chunk.") }
                guard f.tag == 1, f.channels == 1, f.rate == 16_000, f.bits == 16 else {
                    throw WAVDecodeError(message: "Expected 16 kHz mono 16-bit PCM, got \(f.rate) Hz, \(f.channels) ch, \(f.bits) bit.")
                }
                let end = min(b.count, body + size) // tolerujemy ucięty chunk
                return stride(from: body, to: end - 1, by: 2).map { Float(Int16(bitPattern: UInt16(u16($0)))) / 32_767 }
            }
            i = body + size + (size & 1) // chunki są wyrównane do 2 bajtów
        }
        throw WAVDecodeError(message: "WAV has no data chunk.")
    }
}
