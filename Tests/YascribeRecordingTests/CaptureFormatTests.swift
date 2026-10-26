@preconcurrency import AVFoundation
import Testing
@testable import YascribeRecording

private func tapFormat(_ rate: Double = 48_000) -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: true)!
}

@Test func captureFormatKeepsTheTapFormatWhenRatesAgree() {
    let tap = tapFormat()
    #expect(CoreAudioDevices.captureFormat(tap: tap, deviceRate: 48_000) === tap)
}

@Test func captureFormatTakesTheDeviceRateWhenTheyDiffer() {
    let f = CoreAudioDevices.captureFormat(tap: tapFormat(), deviceRate: 44_100)
    #expect(f.sampleRate == 44_100)
    #expect(f.channelCount == 2)
}

@Test func captureFormatIgnoresAnUnreadableDeviceRate() {
    let tap = tapFormat()
    #expect(CoreAudioDevices.captureFormat(tap: tap, deviceRate: 0) === tap)
}
