@preconcurrency import AVFoundation
import Foundation

public enum ResampleError: Error, Equatable {
    case converter
}

/// Przepróbkowanie całej ścieżki do 16 kHz mono na potrzeby ASR. Offline:
/// konwerter dostaje koniec strumienia i oddaje ogon filtra — inaczej niż
/// w nagrywaniu, gdzie strumień trwa.
public enum Resampler {
    public static let asrRate = 16_000.0

    public static func toASR(_ samples: [Int16], sampleRate: Double, channels: Int) throws -> [Float] {
        let frames = samples.count / channels
        guard frames > 0 else { return [] }
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                        channels: AVAudioChannelCount(channels), interleaved: true),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asrRate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let input = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(frames)) else {
            throw ResampleError.converter
        }
        if channels > 1 { conv.downmix = true }
        input.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { src in
            input.int16ChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        var out: [Float] = []
        out.reserveCapacity(Int(Double(frames) * asrRate / sampleRate) + 1_024)
        var fed = false
        while true {
            guard let buf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 16_384) else { throw ResampleError.converter }
            var err: NSError?
            let st = conv.convert(to: buf, error: &err) { _, status in
                if fed {
                    status.pointee = .endOfStream
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return input
            }
            if err != nil || st == .error { throw ResampleError.converter }
            out.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
            if st == .endOfStream || (st == .inputRanDry && buf.frameLength == 0) { break }
        }
        return out
    }
}
