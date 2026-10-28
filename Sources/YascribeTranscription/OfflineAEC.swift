import CSpeexDSP
import CryptoKit
import Foundation
import YascribeSessionFormat

/// Offline only: the reference follows the original microphone sample indices.
/// Recording files and the sample/time mapping consumed by Merger are unchanged.
public enum OfflineAEC {
    public struct Configuration: Codable, Equatable, Sendable {
        public let algorithmVersion: Int
        public let libraryVersion: String
        public init() { algorithmVersion = 1; libraryVersion = "1.2.1" }
    }

    public enum Disposition: String, Codable, Sendable {
        case applied, notApplicable, unreliableClock, deviceChanged, unhealthyTrack, noEchoEvidence
    }

    public struct Report: Codable, Equatable, Sendable {
        public let disposition: Disposition
        public let correlation: Double?
        public let lagSeconds: Double?
        public let processedSamples: Int

        init(_ disposition: Disposition, correlation: Double? = nil, lagSeconds: Double? = nil, processedSamples: Int = 0) {
            self.disposition = disposition
            self.correlation = correlation
            self.lagSeconds = lagSeconds
            self.processedSamples = processedSamples
        }
    }

    public enum ProcessingError: Error, Equatable {
        case unsupportedConfiguration
        case processor(Int32)
    }

    struct Result {
        let samples: [Float]
        let report: Report
    }

    /// Includes the complete journal and all selected audio, even if AEC is
    /// bypassed or a healthy historical mic_aec is selected.
    static func fingerprint(session: SessionDirectory, trackIDs: [String]) throws -> String {
        var hash = SHA256()
        hash.update(data: Data("YascribeOfflineAEC-input-v1\n".utf8))
        for name in ["journal.jsonl"] + trackIDs.sorted().map({ "\($0).caf" }) {
            let file = try FileHandle(forReadingFrom: session.url.appendingPathComponent(name))
            defer { try? file.close() }
            var content = SHA256()
            while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty {
                try Task.checkCancellation()
                content.update(data: bytes)
            }
            hash.update(data: Data(name.utf8))
            hash.update(data: Data(content.finalize()))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A clock represented in ASR-frame coordinates and host seconds relative
    /// to the first mic sample. A single anchor uses the nominal rate.
    private struct Timeline {
        let frames: [Double]
        let times: [Double]

        init?(_ track: SessionSummary.Track, origin: UInt64, timebase: Timebase) {
            guard track.sampleRate.isFinite, track.sampleRate > 0,
                  timebase.numer > 0, timebase.denom > 0, let first = track.firstSampleHostTime else { return nil }
            let anchors = track.clock
            guard anchors.isEmpty || (anchors.first?.frameIndex == 0 && anchors.first?.hostTime == first) else { return nil }
            var f = anchors.isEmpty ? [0.0] : anchors.map { Double($0.frameIndex) * Resampler.asrRate / track.sampleRate }
            var t = anchors.isEmpty ? [timebase.secondsBetween(first, origin)] : anchors.map { timebase.secondsBetween($0.hostTime, origin) }
            if f.count == 1 { f.append(Resampler.asrRate); t.append(t[0] + 1) }
            for i in 1..<f.count {
                guard f[i].isFinite, t[i].isFinite, f[i] > f[i-1], t[i] > t[i-1],
                      abs((f[i]-f[i-1])/(t[i]-t[i-1])/Resampler.asrRate - 1) <= 0.05 else { return nil }
            }
            frames = f; times = t
        }

        func time(at frame: Double) -> Double { interpolate(frame, from: frames, to: times) }
        func frame(at time: Double) -> Double { interpolate(time, from: times, to: frames) }

        private func interpolate(_ x: Double, from: [Double], to: [Double]) -> Double {
            var i = 0
            while i + 2 < from.count && from[i+1] <= x { i += 1 }
            return to[i] + (x-from[i]) * (to[i+1]-to[i]) / (from[i+1]-from[i])
        }
    }

    static func process(microphone: [Float], system: [Float], summary: SessionSummary,
                        configuration: Configuration) throws -> Result {
        guard configuration == Configuration() else { throw ProcessingError.unsupportedConfiguration }
        try Task.checkCancellation()
        func skip(_ why: Disposition) -> Result { Result(samples: microphone, report: Report(why)) }
        guard !microphone.isEmpty, system.count > 1,
              let mic = summary.tracks.first(where: { $0.id == "mic_raw" }),
              let sys = summary.tracks.first(where: { $0.id == "system" }) else { return skip(.notApplicable) }
        guard mic.failure == nil, sys.failure == nil, mic.permissionDenied == nil, sys.permissionDenied == nil,
              mic.rateMismatch == nil, sys.rateMismatch == nil else { return skip(.unhealthyTrack) }
        guard mic.deviceUIDs.count <= 1, sys.deviceUIDs.count <= 1 else { return skip(.deviceChanged) }
        guard let origin = mic.firstSampleHostTime,
              let micClock = Timeline(mic, origin: origin, timebase: summary.timebase),
              let sysClock = Timeline(sys, origin: origin, timebase: summary.timebase) else { return skip(.unreliableClock) }

        var reference = [Float](repeating: 0, count: microphone.count)
        let aligned = reference.withUnsafeMutableBufferPointer { out in
            yascribe_align_reference(system, system.count, out.baseAddress!, out.count,
                                     micClock.frames, micClock.times, micClock.frames.count,
                                     sysClock.frames, sysClock.times, sysClock.frames.count)
        }
        guard aligned == 0 else { return skip(.unreliableClock) }
        let evidence = yascribe_echo_evidence(microphone, reference, microphone.count)
        try Task.checkCancellation()
        guard evidence.matching_windows >= 2 else { return skip(.noEchoEvidence) }

        // Leave one frame of causal room response in the FIR; the accepted
        // acoustic delay can otherwise exceed its 256 ms tail. Delay only the
        // reference, never the microphone or its timestamp/sample positions.
        let referenceShift = max(0, Int(evidence.lag_frames) - 256)
        if referenceShift > 0 {
            reference.withUnsafeMutableBufferPointer { buffer in
                _ = memmove(buffer.baseAddress!.advanced(by: referenceShift), buffer.baseAddress!,
                            (buffer.count-referenceShift) * MemoryLayout<Float>.stride)
                for i in 0..<referenceShift { buffer[i] = 0 }
            }
        }

        // Gaps already exist as silence in CAF. Never insert/remove samples.
        // Preserve original mic throughout mic mutes/gaps and reference outages;
        // drain and restart WOLA independently for each surrounding valid span.
        var protected: [Range<Int>] = []
        let availableStart = micClock.frame(at: sysClock.time(at: 0)) + Double(referenceShift)
        let availableEnd = micClock.frame(at: sysClock.time(at: Double(system.count)))
        let prefix = max(referenceShift, Int(max(0, min(Double(microphone.count), availableStart.rounded(.up)))))
        let suffix = Int(max(0, min(Double(microphone.count), availableEnd.rounded(.down))))
        if prefix > 0 { protected.append(0..<prefix) }
        if suffix < microphone.count { protected.append(suffix..<microphone.count) }
        for (track, clock) in [(mic, micClock), (sys, sysClock)] {
            let intervals: [(Double, Double?)] = track.gaps.map { (Double($0.frameIndex), Double($0.frameIndex) + Double($0.frames)) }
                + (track.mutes ?? []).map { (Double($0.frameIndex), $0.endFrame.map(Double.init)) }
            for (start, end) in intervals {
                let a = micClock.frame(at: clock.time(at: start * Resampler.asrRate / track.sampleRate))
                var b = end.map { micClock.frame(at: clock.time(at: $0 * Resampler.asrRate / track.sampleRate)) }
                    ?? Double(microphone.count)
                if track.id == "system" { b += Double(evidence.lag_frames) }
                guard a.isFinite, b.isFinite else { return skip(.unreliableClock) }
                let lo = Int(max(0, min(Double(microphone.count), a.rounded(.down))))
                let hi = Int(max(0, min(Double(microphone.count), b.rounded(.up))))
                if lo < hi { protected.append(lo..<hi) }
            }
        }
        var merged: [Range<Int>] = []
        for range in protected.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count-1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        var output = microphone
        var processed = 0
        try microphone.withUnsafeBufferPointer { input in
            try reference.withUnsafeBufferPointer { ref in
                try output.withUnsafeMutableBufferPointer { out in
                    func span(_ range: Range<Int>) throws {
                        guard !range.isEmpty else { return }
                        try Task.checkCancellation()
                        let result = yascribe_cancel_echo(input.baseAddress!.advanced(by: range.lowerBound),
                                                         ref.baseAddress!.advanced(by: range.lowerBound),
                                                         out.baseAddress!.advanced(by: range.lowerBound), range.count)
                        guard result == 0 else { throw ProcessingError.processor(result) }
                        processed += range.count
                    }
                    var start = 0
                    for range in merged { try span(start..<range.lowerBound); start = range.upperBound }
                    try span(start..<microphone.count)
                }
            }
        }
        try Task.checkCancellation()
        return Result(samples: output, report: Report(.applied, correlation: evidence.correlation,
                                                      lagSeconds: Double(evidence.lag_frames)/Resampler.asrRate,
                                                      processedSamples: processed))
    }
}
