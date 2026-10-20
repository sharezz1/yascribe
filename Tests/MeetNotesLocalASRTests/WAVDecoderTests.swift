import Foundation
import Testing
import MeetNotesTranscription
@testable import MeetNotesLocalASR

private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

@Test func roundTripsWAVEncoderOutput() throws {
    let pcm: [Int16] = [0, 1, -1, 12_345, -12_345, 32_767, -32_767]
    let samples = try WAVDecoder.samples(WAVEncoder.wav(pcm, rate: 16_000))
    #expect(samples.count == pcm.count)
    for (s, p) in zip(samples, pcm) { #expect(abs(s - Float(p) / 32_767) <= 1 / 32_767) }
}

@Test func rejectsStereoAndWrongRate() {
    var wrongRate = WAVEncoder.wav([1, 2, 3], rate: 16_000)
    wrongRate.replaceSubrange(24..<28, with: le32(48_000))
    #expect(throws: WAVDecodeError.self) { _ = try WAVDecoder.samples(wrongRate) }
    var stereo = WAVEncoder.wav([1, 2, 3, 4], rate: 16_000)
    stereo.replaceSubrange(22..<24, with: le16(2))
    #expect(throws: WAVDecodeError.self) { _ = try WAVDecoder.samples(stereo) }
    #expect(throws: WAVDecodeError.self) { _ = try WAVDecoder.samples(Data("not a wav".utf8)) }
}

@Test func findsTheDataChunkAfterExtraHeaderChunks() throws {
    // Nagłówek z dodatkowym chunkiem LIST (nieparzysty rozmiar + bajt wyrównania) przed `data` — nie 44 bajty.
    let canonical = WAVEncoder.wav([100, -200, 300], rate: 16_000)
    var wav = canonical.prefix(36)
    wav += Data("LIST".utf8) + le32(3) + Data([1, 2, 3, 0])
    wav += Data("data".utf8) + le32(6) + canonical.suffix(6)
    #expect(try WAVDecoder.samples(wav) == [100, -200, 300].map { Float($0) / 32_767 })
}
