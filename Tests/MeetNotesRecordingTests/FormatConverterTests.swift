import AVFoundation
import Foundation
import Testing
@testable import MeetNotesRecording

private func floatBuffer(frames: Int, rate: Double, channels: Int, hz: Double) throws -> AVAudioPCMBuffer {
    let fmt = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                         channels: AVAudioChannelCount(channels), interleaved: false))
    let b = try #require(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)))
    b.frameLength = AVAudioFrameCount(frames)
    for c in 0..<channels {
        for i in 0..<frames { b.floatChannelData![c][i] = Float(0.5 * sin(2 * .pi * hz * Double(i) / rate)) }
    }
    return b
}

@Test func downsamplesStereo48kToMono16k() throws {
    let src = try floatBuffer(frames: 4_800, rate: 48_000, channels: 2, hz: 440)
    let conv = try FormatConverter(input: src.format, sampleRate: 16_000, channels: 1)
    var out: [Int16] = []
    for _ in 0..<10 { out += conv.convert(src) } // 10 × 100 ms
    #expect(abs(out.count - 16_000) <= 1) // bez przetrzymywania: etykieta czasu hosta zostaje prawdziwa
    #expect(Levels.rmsDBFS(out) > -12) // sinus 0,5 ≈ -9 dBFS przetrwał
}

@Test func sameRateConversionKeepsFrameCountAndShape() throws {
    let src = try floatBuffer(frames: 4_800, rate: 48_000, channels: 2, hz: 1_000)
    let conv = try FormatConverter(input: src.format, sampleRate: 48_000, channels: 2)
    let out = conv.convert(src)
    #expect(out.count == 4_800 * 2) // bufor większy niż wewnętrzny limit 4096 wychodzi w całości
    let expected = sine(frames: 4_800, channels: 2, rate: 48_000, hz: 1_000)
    let fit = AudioFit.fit(reference: AudioFit.mono(expected, channels: 2), recorded: AudioFit.mono(out, channels: 2), maxLagFrames: 0)
    #expect(fit.rSquared > 0.999) // T1 na poziomie konwersji: Float32 → Int16 bez zniekształceń
}

@Test func everyCallReturnsItsOwnFramesForTypicalHALBuffers() throws {
    // 512 ramek to typowy bufor IOProc. Wyjście każdego wywołania = jego wejście,
    // więc czas hosta porcji wejściowej jest czasem jej pierwszej próbki wyjścia.
    let src = try floatBuffer(frames: 512, rate: 48_000, channels: 2, hz: 440)
    let conv = try FormatConverter(input: src.format, sampleRate: 48_000, channels: 2)
    for _ in 0..<20 { #expect(conv.convert(src).count == 1_024) }
}

@Test func conversionFailuresAreReportedEvenWhenTheyComeInBursts() {
    // S4 P1: jedno convert potrafi dodać kilka awarii naraz (plasterki).
    #expect(FormatConverter.shouldReport(before: 0, after: 5))
    #expect(!FormatConverter.shouldReport(before: 5, after: 9))
    #expect(FormatConverter.shouldReport(before: 998, after: 1_001))
    #expect(!FormatConverter.shouldReport(before: 3, after: 3))
}

@Test func mixesMicArrayChannelsWithGain() throws {
    // Mikrofon pod VP: 3 kapsuły, przeplatane Float32 (runda 3). Średnia × wzmocnienie, obcięta do ±1.
    let fmt = try #require(CoreAudioDevices.format(AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 12, mFramesPerPacket: 1, mBytesPerFrame: 12, mChannelsPerFrame: 3, mBitsPerChannel: 32, mReserved: 0)))
    let b = try #require(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 2))
    b.frameLength = 2
    let p = b.floatChannelData![0]
    for (i, v) in [0.01, 0.02, 0.03, 0.5, 0.5, 0.5].enumerated() { p[i] = Float(v) }
    let m = try #require(HALCapture.mixArray(b, gain: 10))
    #expect(abs(m.floatChannelData![0][0] - 0.2) < 1e-6)
    #expect(m.floatChannelData![0][1] == 1)
    #expect(HALCapture.converterInput(fmt, 10).channelCount == 1)
    #expect(HALCapture.converterInput(fmt, nil).channelCount == 3)
}
