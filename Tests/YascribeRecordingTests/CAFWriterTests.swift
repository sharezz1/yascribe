import AVFoundation
import Foundation
import Testing
@testable import YascribeRecording
import YascribeSessionFormat

func tempURL(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d.appendingPathComponent(name)
}

func sine(frames: Int, channels: Int, rate: Double = 48_000, hz: Double = 440, amp: Double = 0.5) -> [Int16] {
    var out: [Int16] = []
    out.reserveCapacity(frames * channels)
    for i in 0..<frames {
        let v = Int16(amp * 32_767 * sin(2 * .pi * hz * Double(i) / rate))
        for _ in 0..<channels { out.append(v) }
    }
    return out
}

/// Czyta plik systemowym czytnikiem (AVAudioFile) — dowód, że nasz CAF jest
/// zwykłym CAF-em dla innych narzędzi. Czyta w pętli, bo jedno `read(into:)`
/// potrafi oddać mniej ramek niż pojemność bufora.
func readInt16(_ url: URL) throws -> (samples: [Int16], rate: Double, channels: Int) {
    let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
    let ch = Int(f.processingFormat.channelCount)
    let buf = try #require(AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8_192))
    var out: [Int16] = []
    while f.framePosition < f.length {
        try f.read(into: buf)
        if buf.frameLength == 0 { break }
        let p = try #require(buf.int16ChannelData)
        out.append(contentsOf: UnsafeBufferPointer(start: p[0], count: Int(buf.frameLength) * ch))
    }
    return (out, f.processingFormat.sampleRate, ch)
}

@Test func headerHasTheSizeTheReaderAssumes() {
    #expect(CAFWriter.header(sampleRate: 48_000, channels: 2).count == CAFLayout.headerSize)
}

@Test func writtenSamplesReadBackBitExact() throws {
    let url = try tempURL("system.caf")
    let w = try CAFWriter(url: url, sampleRate: 48_000, channels: 2)
    let s = sine(frames: 4_800, channels: 2)
    try w.append(s)
    try w.close()
    let r = try readInt16(url)
    #expect(r.rate == 48_000)
    #expect(r.channels == 2)
    #expect(r.samples == s)
}

@Test func fileIsReadableWithoutClose() throws {
    // Symulacja kill -9: pisarz nie dostaje close(), a plik ma być czytelny.
    let url = try tempURL("mic_raw.caf")
    let w = try CAFWriter(url: url, sampleRate: 16_000, channels: 1)
    try w.append(sine(frames: 16_000, channels: 1, rate: 16_000))
    let r = try readInt16(url)
    #expect(r.samples.count == 16_000)
    _ = w // pisarz żyje dalej, nie zamknięty
}

@Test func silenceIsWrittenAsZeros() throws {
    let url = try tempURL("s.caf")
    let w = try CAFWriter(url: url, sampleRate: 16_000, channels: 1)
    try w.appendSilence(frames: 10_000)
    try w.close()
    let r = try readInt16(url)
    #expect(r.samples.count == 10_000)
    #expect(r.samples.allSatisfy { $0 == 0 })
    #expect(w.framesWritten == 10_000)
}

@Test func ownReaderMatchesSystemReader() throws {
    let url = try tempURL("system.caf")
    let w = try CAFWriter(url: url, sampleRate: 48_000, channels: 2)
    let s = sine(frames: 70_000, channels: 2)
    try w.append(s)
    let own = try CAFReader(url: url)
    #expect(own.samples == s)
    #expect(own.sampleRate == 48_000)
    #expect(own.channels == 2)
    #expect(try readInt16(url).samples == s)
}

@Test func ownReaderRejectsForeignFile() throws {
    let url = try tempURL("x.caf")
    try Data(repeating: 0x41, count: 200).write(to: url)
    #expect(throws: CAFReadError.notOurLayout("magic")) { _ = try CAFReader(url: url) }
}
