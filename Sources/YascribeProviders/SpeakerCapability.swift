import Foundation

public enum SpeakerCapability {
    public static func supports(api: ProviderKind, model: String) -> Bool {
        (api == .openAICompatible && model == "elevenlabs/scribe-v2") || (api == .elevenLabs && model == "scribe_v2")
    }
    public static func pin(api: ProviderKind, model: String) -> String {
        "\(api == .openAICompatible ? "openrouter" : api.rawValue)/\(model)/diarize-v1"
    }
    public static let pins: Set<String> = [pin(api: .openAICompatible, model: "elevenlabs/scribe-v2"), pin(api: .elevenLabs, model: "scribe_v2")]
}

public struct DiarizedWord: Equatable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double
    public init(speaker: String, start: Double, end: Double) { self.speaker = speaker; self.start = start; self.end = end }
}

public protocol DiarizationClient: Sendable {
    func diarize(m4a: Data, model: String, language: LanguageCode?) async throws -> [DiarizedWord]
}

func parseDiarizedWords(_ data: Data, speakerKey: String, filterType: Bool) throws -> [DiarizedWord] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let words = object["words"] as? [[String: Any]] else { throw ProviderError.badResponse("no speakers") }
    return try words.filter { !filterType || $0["type"] as? String == "word" }.map { word in
        guard let speaker = word[speakerKey] as? String, !speaker.isEmpty,
              let start = (word["start"] as? NSNumber)?.doubleValue, start.isFinite,
              let end = (word["end"] as? NSNumber)?.doubleValue, end.isFinite else { throw ProviderError.badResponse("no speakers") }
        return DiarizedWord(speaker: speaker, start: start, end: end)
    }
}
