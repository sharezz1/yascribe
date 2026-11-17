import AVFoundation
import Foundation

public enum AACEncoder {
    public static func encode(caf: URL, to: URL, bitrate: Int) throws {
        let input = try AVAudioFile(forReading: caf)
        let rate = min(input.processingFormat.sampleRate, 48_000)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let converter = AVAudioConverter(from: input.processingFormat, to: mono),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_384),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 16_384) else { throw CloudDiarizationError.audioFormat }
        converter.downmix = true // tor stereo: oba kanały, nie tylko lewy
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitrate]
        let output = try AVAudioFile(forWriting: to, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var readError: Error?
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, state in
                do {
                    if input.framePosition >= input.length { state.pointee = .endOfStream; return nil }
                    try input.read(into: inBuffer)
                    state.pointee = inBuffer.frameLength == 0 ? .endOfStream : .haveData
                    return inBuffer.frameLength == 0 ? nil : inBuffer
                } catch {
                    readError = error
                    state.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            if outBuffer.frameLength > 0 { try output.write(from: outBuffer) }
            if status == .endOfStream { break }
            if status == .error { throw CloudDiarizationError.audioFormat }
        }
    }
}
