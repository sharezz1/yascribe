import Foundation

public enum SpeakerLabels {
    public static let nearestRadius = 1.0

    public static func labels(for t: Transcript, diarization: SpeakerDiarization?) -> [String?] {
        let keys = speakerKeys(for: t, diarization: diarization)
        let numbered = numbers(keys: keys, in: t)
        return keys.map { $0.flatMap { key in diarization?.names?[key] ?? numbered[key].map { "Speaker \($0)" } } }
    }

    /// Klucz mówcy → N z „Speaker N” (kolejność pierwszej wypowiedzi) dla transkryptu po `withSpeakerLabels`.
    public static func numbers(for t: Transcript) -> [String: Int] {
        numbers(keys: t.utterances.map(\.speakerKey), in: t)
    }

    private static func numbers(keys: [String?], in t: Transcript) -> [String: Int] {
        var numbered: [String: Int] = [:]
        for index in t.utterances.indices.sorted(by: {
            t.utterances[$0].start == t.utterances[$1].start ? $0 < $1 : t.utterances[$0].start < t.utterances[$1].start
        }) {
            guard let key = keys[index], numbered[key] == nil else { continue }
            numbered[key] = numbered.count + 1
        }
        return numbered
    }

    /// Odcinki bez okruchów (klucz z mniej niż `minClusterSeconds` mowy) i początek pierwszego odcinka każdego klucza (remisy).
    private static func usable(_ diarization: SpeakerDiarization) -> (segments: [SpeakerDiarization.Segment], first: [String: Double]) {
        var totals: [String: Double] = [:]
        var first: [String: Double] = [:]
        for segment in diarization.segments {
            totals[segment.speaker, default: 0] += segment.end - segment.start
            first[segment.speaker] = min(first[segment.speaker] ?? segment.start, segment.start)
        }
        return (diarization.segments.filter { totals[$0.speaker, default: 0] >= (diarization.minClusterSeconds ?? 10) }, first)
    }

    /// Klucz z największym pokryciem; remis: wcześniejsze pierwsze wystąpienie, potem nazwa.
    private static func most(_ overlap: [String: Double], first: [String: Double]) -> String? {
        overlap.keys.sorted {
            if overlap[$0] != overlap[$1] { return overlap[$0]! > overlap[$1]! }
            if first[$0] != first[$1] { return first[$0]! < first[$1]! }
            return $0 < $1
        }.first
    }

    private static func overlap(_ start: Double, _ end: Double, _ segments: [SpeakerDiarization.Segment]) -> [String: Double] {
        var overlap: [String: Double] = [:]
        for segment in segments {
            let amount = min(end, segment.end) - max(start, segment.start)
            if amount > 0 { overlap[segment.speaker, default: 0] += amount }
        }
        return overlap
    }

    static func speakerKeys(for t: Transcript, diarization: SpeakerDiarization?) -> [String?] {
        guard let diarization else { return Array(repeating: nil, count: t.utterances.count) }
        let (segments, first) = usable(diarization)
        var assigned: [String?] = Array(repeating: nil, count: t.utterances.count)
        for (index, utterance) in t.utterances.enumerated() where utterance.speaker == .them {
            let overlap = overlap(utterance.start, utterance.end, segments)
            if !overlap.isEmpty {
                assigned[index] = most(overlap, first: first)
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
        return assigned
    }

    /// Część krótsza (w słowach) dołącza do sąsiedniej: pojedyncze słowo na granicy to zwykle drganie diaryzacji.
    public static let minPartWords = 2

    /// Podział wypowiedzi `them` na granicach mówców według czasów słów (TASK-127); `[]` = bez podziału.
    /// Bez znaczników słów (`approximateTiming`) nie dzielimy. Tekst tnie wyrównanie kluczy słów i tokenów, bo korekta, poprawka
    /// ręczna i Replacement zmieniają tylko `text`. Granica w środku zmienionego bloku tnie go proporcjonalnie, więc podział
    /// (i numeracja „Speaker N”) nie zależy od tekstu; bez podziału tylko, gdy tokenów jest mniej niż części.
    static func split(_ u: Utterance, index: Int, diarization: SpeakerDiarization) -> [Utterance] {
        guard u.speaker == .them, !u.approximateTiming, u.words.count >= 2 * minPartWords else { return [] }
        let (segments, first) = usable(diarization)
        var keys = u.words.map { most(overlap($0.start, $0.end, segments), first: first) }
        // Słowo w ciszy diaryzacji dziedziczy klucz poprzednika (przodujące — następnika).
        guard let known = keys.firstIndex(where: { $0 != nil }) else { return [] }
        for i in keys.indices where keys[i] == nil { keys[i] = i < known ? keys[known] : keys[i - 1] }
        var runs: [(key: String, words: Range<Int>)] = []
        for (i, key) in keys.enumerated() {
            if let last = runs.last, last.key == key { runs[runs.count - 1].words = last.words.lowerBound..<(i + 1) }
            else { runs.append((key!, i..<(i + 1))) }
        }
        while runs.count > 1, let short = runs.firstIndex(where: { $0.words.count < minPartWords }) {
            let into = short > 0 ? short - 1 : 1
            runs[into].words = min(runs[into].words.lowerBound, runs[short].words.lowerBound)..<max(runs[into].words.upperBound, runs[short].words.upperBound)
            runs.remove(at: short)
            var i = 1
            while i < runs.count {
                if runs[i].key == runs[i - 1].key {
                    runs[i - 1].words = runs[i - 1].words.lowerBound..<runs[i].words.upperBound
                    runs.remove(at: i)
                } else { i += 1 }
            }
        }
        guard runs.count > 1 else { return [] }
        let tokens = u.text.split(separator: " ").map(String.init)
        let steps = TokenAlign.align(u.words.map { TokenAlign.key($0.text) }, tokens.map(TokenAlign.key))
        var cuts = [0]
        for run in runs.dropFirst() { cuts.append(tokenCut(run.words.lowerBound, steps)) }
        cuts.append(tokens.count)
        guard zip(cuts, cuts.dropFirst()).allSatisfy({ $0 < $1 }) else { return [] }
        return runs.enumerated().map { n, run in
            var part = u
            part.words = Array(u.words[run.words])
            part.start = n == 0 ? u.start : part.words[0].start
            part.end = n == runs.count - 1 ? u.end : part.words[part.words.count - 1].end
            part.text = tokens[cuts[n]..<cuts[n + 1]].joined(separator: " ")
            part.speakerKey = run.key
            part.part = UtterancePart(index: index, start: u.start, text: u.text, isFirst: n == 0)
            return part
        }
    }

    /// Pierwszy token części zaczynającej się słowem `word`. Granica w środku zmienionego bloku: miejsce proporcjonalne do słów.
    static func tokenCut(_ word: Int, _ steps: [TokenAlign.Step]) -> Int {
        var end = 0
        for step in steps {
            switch step {
            case .same(let i, let j):
                if i >= word { return j }
                end = j + 1
            case .changed(let words, let tokens):
                if words.lowerBound >= word { return tokens.lowerBound }
                if words.upperBound > word {
                    return tokens.lowerBound + Int((Double(word - words.lowerBound) * Double(tokens.count) / Double(words.count)).rounded())
                }
                end = tokens.upperBound
            }
        }
        return end
    }
}

public extension Transcript {
    /// Klucze i etykiety mówców; wypowiedź `them` obejmująca kilku mówców staje się częściami (`Utterance.part`, TASK-127).
    /// Numeracja „Speaker N” po podziale — ta sama w widoku i w znacznikach `[[SN]]`.
    func withSpeakerLabels(_ diarization: SpeakerDiarization?) -> Transcript {
        let keys = SpeakerLabels.speakerKeys(for: self, diarization: diarization)
        var result = self
        result.utterances = []
        for (index, u) in utterances.enumerated() {
            let parts = diarization.map { SpeakerLabels.split(u, index: index, diarization: $0) } ?? []
            if parts.isEmpty {
                var whole = u
                whole.speakerKey = keys[index]
                result.utterances.append(whole)
            } else {
                result.utterances += parts
            }
        }
        let numbered = SpeakerLabels.numbers(for: result)
        for i in result.utterances.indices {
            result.utterances[i].speakerLabel = result.utterances[i].speakerKey.flatMap { key in
                diarization?.names?[key] ?? numbered[key].map { "Speaker \($0)" }
            }
        }
        return result
    }
}
