import Foundation

/// WAV 16 kHz mono Int16 z fragmentów okna — tak wysyłamy audio do ASR.
public enum WAVEncoder {
    public static func encode(_ chunk: Chunk, samples x: [Float], rate: Double = Resampler.asrRate) -> Data {
        var pcm = [Int16](repeating: 0, count: chunk.length)
        for s in chunk.segments {
            for i in 0..<s.length {
                let v = max(-1, min(1, x[s.sourceStart + i]))
                pcm[s.chunkStart + i] = Int16((v * 32_767).rounded())
            }
        }
        return wav(pcm, rate: rate)
    }

    public static func wav(_ pcm: [Int16], rate: Double) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(pcm.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        pcm.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: pcm.count * 2)) }
        return d
    }
}
