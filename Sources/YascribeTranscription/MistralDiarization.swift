import Foundation
import YascribeProviders
import YascribeSessionFormat

public enum MistralDiarization {
    public static let model = "voxtral-mini-transcribe-3-0"
    public static let pin = "mistral/voxtral-mini-transcribe-3-0/v1"
    public typealias Segment = (speaker: String, start: Double, end: Double)

    public static func plan(trackSeconds: Double, partSeconds: Double = 1800) -> [Range<Double>] {
        guard trackSeconds > 0, trackSeconds.isFinite, partSeconds > 0, partSeconds.isFinite else { return [] }
        var parts: [Range<Double>] = []; var start = 0.0
        while start < trackSeconds { let end = min(start + partSeconds, trackSeconds); parts.append(start..<end); start = end }
        return parts
    }
    public static func validate(part: Range<Double>, response: MistralDiarizationResponse) throws {
        guard response.totalTokens < 65_000 else { throw MistralDiarizationError.cutShort }
        guard response.segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.start < $0.end && $0.end <= part.upperBound - part.lowerBound + 5 && !$0.speakerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MistralDiarizationError.invalidAnswer
        }
    }
    public static func referenceSegments(_ segments: [Segment]) -> [Segment] {
        let groups = Dictionary(grouping: segments, by: \.speaker)
        return groups.compactMap { _, group -> (Segment, Double)? in
            let total = group.reduce(0) { $0 + $1.end - $1.start }
            guard total >= 10, let longest = group.max(by: { $0.end - $0.start < $1.end - $1.start }), longest.end - longest.start >= 4 else { return nil }
            return (longest, total)
        }.sorted { $0.1 == $1.1 ? $0.0.speaker < $1.0.speaker : $0.1 > $1.1 }.prefix(8).map(\.0)
    }
    public static func references(from segments: [Segment], samples: [Int16], rate: Double) -> [String: Data] {
        var result: [String: Data] = [:]
        for s in referenceSegments(segments) {
            let start = max(0, Int(s.start * rate)), end = min(samples.count, Int(min(s.end, s.start + 12) * rate))
            if end > start, Double(end - start) / rate >= 4 { result[s.speaker] = WAVEncoder.wav(Array(samples[start..<end]), rate: rate) }
        }
        return result
    }
    public static func merge(parts: [(range: Range<Double>, response: MistralDiarizationResponse, references: Set<String>)]) -> [Segment] {
        var merged: [Segment] = []; var used = Set<String>()
        for (index, part) in parts.enumerated() {
            var names: [String: String] = [:]
            for s in part.response.segments where names[s.speakerID] == nil {
                var name = s.speakerID
                if index > 0 && !part.references.contains(name) && (part.references.isEmpty || used.contains(name)) {
                    name = "p\(index + 1)-\(name)"
                    while used.contains(name) { name = "p\(index + 1)-\(name)" }
                }
                names[s.speakerID] = name; used.insert(name)
            }
            merged += part.response.segments.map { (names[$0.speakerID]!, part.range.lowerBound + $0.start, part.range.lowerBound + $0.end) }
        }
        return merged
    }
    public static func run(track: URL, client: any MistralDiarizationService, language: LanguageCode?, partSeconds: Double = 1800, progress: @Sendable (Int, Int, Int) -> Void = { _, _, _ in }) async throws -> [Segment] {
        let info = try CAFReader.info(url: track)
        let ranges = plan(trackSeconds: Double(info.frames) / info.sampleRate, partSeconds: partSeconds)
        var parts: [(range: Range<Double>, response: MistralDiarizationResponse, references: Set<String>)] = []
        for (index, range) in ranges.enumerated() {
            try Task.checkCancellation()
            var refs: [String: Data] = [:]
            for segment in referenceSegments(merge(parts: parts)) {
                let start = max(0, Int(segment.start * info.sampleRate))
                let end = min(info.frames, Int(min(segment.end, segment.start + 12) * info.sampleRate))
                guard end > start else { continue }
                let clip = try CAFReader.read(url: track, frames: start..<end)
                let floats = try Resampler.toASR(clip.samples, sampleRate: info.sampleRate, channels: info.channels)
                refs[segment.speaker] = WAVEncoder.wav(floats.map { Int16((max(-1, min(1, $0)) * 32767).rounded()) }, rate: Resampler.asrRate)
            }
            let start = Int(range.lowerBound * info.sampleRate), end = min(info.frames, Int((range.upperBound * info.sampleRate).rounded()))
            let audio = try CAFReader.read(url: track, frames: start..<end)
            let floats = try Resampler.toASR(audio.samples, sampleRate: info.sampleRate, channels: info.channels)
            let wav = WAVEncoder.wav(floats.map { Int16((max(-1, min(1, $0)) * 32767).rounded()) }, rate: Resampler.asrRate)
            let response = try await client.diarize(wav: wav, model: model, language: language, references: refs)
            try Task.checkCancellation()
            try validate(part: range, response: response)
            parts.append((range, response, Set(refs.keys)))
            progress(index + 1, ranges.count, response.totalTokens)
        }
        return merge(parts: parts)
    }
}
