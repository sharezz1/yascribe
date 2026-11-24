import Foundation

/// Które grupy diaryzatora to ten sam głos (TASK-126). Czysta logika: odciski liczy wołający, wynik stosuje `SpeakerDiarization.merging`.
public enum SpeakerMerge {
    public struct Group: Sendable, Equatable {
        public var key: String
        public var vector: [Float]
        public var seconds: Double
        public var name: String?
        public init(key: String, vector: [Float], seconds: Double, name: String?) {
            self.key = key; self.vector = vector; self.seconds = seconds; self.name = name
        }
    }

    /// shortcut: wartości startowe jak próg profili; dobrać kalibracją TASK-126 na nagraniach użytkownika.
    public static let mergeThreshold = 0.70
    /// shortcut: krótki odcisk jest szumny; kalibracja TASK-126 mierzy błędne złączenia małych grup.
    public static let smallThreshold = 0.65
    /// Poniżej tylu sekund czystej mowy grupa jest „mała”: tylko dołącza, sama nie przyciąga innych.
    public static let smallSeconds = 5.0
    /// shortcut: o ile kalendarz (więcej grup niż zaproszonych) obniża próg; kalibracja TASK-126.
    public static let hintRelief = 0.05
    /// Kalendarz nigdy nie obniża progu poniżej tej wartości.
    public static let hintFloor = 0.65

    private struct Cluster {
        var target: String
        var members: [String]
        var vector: [Float]
        var seconds: Double
        var name: String?
    }

    /// Źródło → cel (cel zostaje). `expected` = oczekiwana liczba zdalnych mówców (wskazówka, nie limit).
    public static func plan(_ groups: [Group], expected: Int?, mergeThreshold: Double = SpeakerMerge.mergeThreshold) -> [String: String] {
        let sorted = groups.sorted { $0.key < $1.key }
        var clusters = sorted.filter { $0.seconds >= smallSeconds }
            .map { Cluster(target: $0.key, members: [$0.key], vector: VoiceVectors.normalized($0.vector), seconds: $0.seconds, name: $0.name) }
        agglomerate(&clusters, threshold: mergeThreshold)
        if let expected, clusters.count > expected {
            agglomerate(&clusters, threshold: max(mergeThreshold - hintRelief, hintFloor))
        }
        // Małe grupy z imieniem zostają: ręczne imię nie przechodzi na cudzy głos z krótkiego odcisku.
        for small in sorted where small.seconds < smallSeconds && small.name == nil {
            var best: (index: Int, cos: Double)?
            for (i, c) in clusters.enumerated() {
                let cos = VoiceVectors.cosine(small.vector, c.vector)
                if cos >= smallThreshold, cos > (best?.cos ?? -2) { best = (i, cos) }
            }
            if let best { clusters[best.index].members.append(small.key) }
        }
        var result: [String: String] = [:]
        for c in clusters { for m in c.members where m != c.target { result[m] = c.target } }
        return result
    }

    private static func compatible(_ a: Cluster, _ b: Cluster) -> Bool {
        a.name == nil || b.name == nil || a.name == b.name
    }

    /// Najpodobniejsza para ≥ progu, aż żadna nie zostanie. Remis: pierwsza w kolejności kluczy.
    private static func agglomerate(_ clusters: inout [Cluster], threshold: Double) {
        while true {
            var best: (i: Int, j: Int, cos: Double)?
            for i in clusters.indices {
                for j in clusters.indices where j > i && compatible(clusters[i], clusters[j]) {
                    let cos = VoiceVectors.cosine(clusters[i].vector, clusters[j].vector)
                    if cos >= threshold, cos > (best?.cos ?? -2) { best = (i, j, cos) }
                }
            }
            guard let best else { return }
            let a = clusters[best.i], b = clusters[best.j]
            let keepA = a.name != nil && b.name == nil ? true
                : b.name != nil && a.name == nil ? false
                : a.seconds != b.seconds ? a.seconds > b.seconds : a.target < b.target
            let (keep, other) = keepA ? (a, b) : (b, a)
            let total = keep.seconds + other.seconds
            let mixed = zip(keep.vector, other.vector).map { Float((Double($0) * keep.seconds + Double($1) * other.seconds) / total) }
            let merged = Cluster(target: keep.target, members: keep.members + other.members,
                                 vector: VoiceVectors.normalized(mixed), seconds: total, name: keep.name ?? other.name)
            clusters.remove(at: best.j)
            clusters[best.i] = merged
        }
    }
}
