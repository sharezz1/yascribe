import Foundation

public enum SpeakerLabels {
    public static let nearestRadius = 1.0

    public static func labels(for t: Transcript, diarization: SpeakerDiarization?) -> [String?] {
        guard let diarization else { return Array(repeating: nil, count: t.utterances.count) }
        var totals: [String: Double] = [:]
        var first: [String: Double] = [:]
        for segment in diarization.segments {
            totals[segment.speaker, default: 0] += segment.end - segment.start
            first[segment.speaker] = min(first[segment.speaker] ?? segment.start, segment.start)
        }
        let segments = diarization.segments.filter { totals[$0.speaker, default: 0] >= (diarization.minClusterSeconds ?? 10) }
        var assigned: [String?] = Array(repeating: nil, count: t.utterances.count)
        for (index, utterance) in t.utterances.enumerated() where utterance.speaker == .them {
            var overlap: [String: Double] = [:]
            for segment in segments {
                let amount = min(utterance.end, segment.end) - max(utterance.start, segment.start)
                if amount > 0 { overlap[segment.speaker, default: 0] += amount }
            }
            if !overlap.isEmpty {
                assigned[index] = overlap.keys.sorted {
                    if overlap[$0] != overlap[$1] { return overlap[$0]! > overlap[$1]! }
                    if first[$0] != first[$1] { return first[$0]! < first[$1]! }
                    return $0 < $1
                }.first
            } else {
                let distances: [(distance: Double, speaker: String)] = segments.map { segment in
                    (max(segment.start - utterance.end, utterance.start - segment.end), segment.speaker)
                }
                let nearest = distances.filter { $0.distance <= nearestRadius }.sorted { a, b in
                    a.distance == b.distance ? a.speaker < b.speaker : a.distance < b.distance
                }
                assigned[index] = nearest.first?.speaker
            }
        }
        var names: [String: String] = [:]
        for index in t.utterances.indices.sorted(by: {
            t.utterances[$0].start == t.utterances[$1].start ? $0 < $1 : t.utterances[$0].start < t.utterances[$1].start
        }) {
            guard let speaker = assigned[index], names[speaker] == nil else { continue }
            let n = names.count
            names[speaker] = n < 26 ? String(UnicodeScalar(65 + n)!) : String(n + 1)
        }
        return assigned.map { $0.flatMap { names[$0] } }
    }
}

public extension Transcript {
    func withSpeakerLabels(_ diarization: SpeakerDiarization?) -> Transcript {
        var result = self
        for (index, label) in SpeakerLabels.labels(for: self, diarization: diarization).enumerated() {
            result.utterances[index].speakerLabel = label
        }
        return result
    }
}
