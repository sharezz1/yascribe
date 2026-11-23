import Foundation

/// Dopasowanie mówców spotkania do profili głosów (TASK-117). Ostrożnie: fałszywe imię jest gorsze niż „Speaker 1”.
public enum VoiceMatcher {
    public struct Speaker: Equatable, Sendable {
        public var key: String
        public var vector: [Float]
        public var seconds: Double
        public init(key: String, vector: [Float], seconds: Double) { self.key = key; self.vector = vector; self.seconds = seconds }
    }

    public struct Match: Equatable, Sendable {
        public var key: String
        public var profileID: UUID
        public var similarity: Double
        public init(key: String, profileID: UUID, similarity: Double) { self.key = key; self.profileID = profileID; self.similarity = similarity }
    }

    /// Mniej mowy = niepewny odcisk: nie dopasowujemy i nie uczymy.
    public static let minSeconds = 20.0
    /// Przewaga nad drugim profilem; remis to brak imienia.
    public static let margin = 0.10

    /// Próg cosinusa dla modelu; `nil` = model bez kalibracji, nie dopasowujemy.
    /// shortcut: 0,70 z praktyki innych aplikacji (inny model); skalibrować na prawdziwych nagraniach, CAM++ dostanie próg dopiero wtedy.
    public static func threshold(model: String) -> Double? { model.hasPrefix("diarizer/") ? 0.70 : nil }

    public static func match(speakers: [Speaker], profiles: [VoiceProfile], model: String,
                             rejected: [String: [UUID]], skip: Set<String>) -> [Match] {
        guard let threshold = threshold(model: model) else { return [] }
        let vectors = profiles.compactMap { p in p.vector(model: model).map { (id: p.id, vector: $0) } }
        var pairs: [Match] = []
        for speaker in speakers where speaker.seconds >= minSeconds && !skip.contains(speaker.key) {
            let blocked = Set(rejected[speaker.key] ?? [])
            let scored = vectors.filter { !blocked.contains($0.id) }
                .map { (id: $0.id, score: VoiceVectors.cosine(speaker.vector, $0.vector)) }
                .sorted { $0.score > $1.score }
            guard let best = scored.first, best.score >= threshold,
                  best.score - (scored.dropFirst().first?.score ?? -1) >= margin else { continue }
            pairs.append(Match(key: speaker.key, profileID: best.id, similarity: best.score))
        }
        // Zachłannie 1:1 od najpewniejszej pary; mówca, którego profil już zajęto, zostaje bez imienia.
        var taken = Set<UUID>()
        return pairs.sorted { $0.similarity != $1.similarity ? $0.similarity > $1.similarity : $0.key < $1.key }
            .filter { taken.insert($0.profileID).inserted }
    }
}
