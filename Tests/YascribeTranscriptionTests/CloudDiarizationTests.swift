import AVFoundation
import Foundation
import Testing
import YascribeProviders
@testable import YascribeTranscription

private final class CloudStub: DiarizationClient, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [Data] = []
    var calls: [Data] { lock.withLock { captured } }
    func diarize(m4a: Data, model: String, language: LanguageCode?) async throws -> [DiarizedWord] {
        lock.withLock { captured.append(m4a) }
        return [.init(speaker: "s", start: 0, end: 1)]
    }
}
private func cloudTrack() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-test-\(UUID().uuidString).caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
    buffer.frameLength = 16000
    try file.write(from: buffer)
    return url
}
@Suite struct CloudDiarizationTests {
 @Test func bitrateChoice() {
    let limit = 52_428_800
    #expect(CloudDiarization.bitrate(trackSeconds: 18000, limitBytes: nil) == 48000)
    #expect(CloudDiarization.bitrate(trackSeconds: 3600, limitBytes: limit) == 48000)
    #expect(CloudDiarization.bitrate(trackSeconds: 9000, limitBytes: limit) == 24000)
    #expect(CloudDiarization.bitrate(trackSeconds: 18000, limitBytes: limit) == nil)
    #expect(CloudDiarization.bitrate(trackSeconds: 6000, limitBytes: limit) == 24000)
 }
 @Test func segmentsMergeSameSpeakerWithinGap() {
    let words = [DiarizedWord(speaker: "a", start: 0, end: 1), .init(speaker: "a", start: 2.4, end: 3), .init(speaker: "a", start: 4.5, end: 5), .init(speaker: "a", start: 6.6, end: 7), .init(speaker: "b", start: 7, end: 8)]
    let result = CloudDiarization.segments(words)
    #expect(result.count == 4 && result[0].start == 0 && result[0].end == 3 && result[3].speaker == "b")
 }
 @Test func runWritesNothingWhenTooLong() async throws {
    let track = try cloudTrack(); defer { try? FileManager.default.removeItem(at: track) }
    let client = CloudStub()
    await #expect(throws: CloudDiarizationError.tooLong) { try await CloudDiarization.run(track: track, client: client, model: "m", language: nil, limitBytes: 1) }
    #expect(client.calls.isEmpty)
 }
 @Test func runEncodesWholeTrackOnce() async throws {
    let track = try cloudTrack(); defer { try? FileManager.default.removeItem(at: track) }
    let before = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("yascribe-cloud-") })
    let client = CloudStub()
    let result = try await CloudDiarization.run(track: track, client: client, model: "m", language: nil, limitBytes: nil)
    let after = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("yascribe-cloud-") })
    #expect(client.calls.count == 1 && String(decoding: client.calls[0].dropFirst(4).prefix(4), as: UTF8.self) == "ftyp")
    let encoded = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-check-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: encoded) }
    try client.calls[0].write(to: encoded)
    let audio = try AVAudioFile(forReading: encoded)
    #expect(Double(audio.length) / audio.processingFormat.sampleRate >= 0.99 && audio.processingFormat.channelCount == 1)
    #expect(result.count == 1 && before == after)
 }
 @Test func knownPinsAcceptCloudPins() { #expect(SpeakerCapability.pins.isSubset(of: SpeakerDiarization.knownPins(localPin: "local"))) }
}
