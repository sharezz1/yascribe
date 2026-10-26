import Foundation

/// Nagranie próbne o znanej treści. Dane: `ProbeClips+Data.swift` (wygenerowane).
public struct ProbeClip: Sendable {
    public let language: LanguageCode
    public let wav: Data
    public let expectedWords: [String]
}

public enum ProbeClips {
    public static let polish = ProbeClip(language: .polish, wav: Data(base64Encoded: polishBase64)!,
                                         expectedWords: ["raz", "dwa", "trzy"])
    public static let english = ProbeClip(language: .english, wav: Data(base64Encoded: englishBase64)!,
                                          expectedWords: ["one", "two", "three"])

    public static func clip(for language: LanguageCode) -> ProbeClip? {
        switch language {
        case .polish: polish
        case .english: english
        default: nil
        }
    }

    /// Nagranie w **innym** języku niż preset — do sondy honorowania języka.
    public static func mismatched(for language: LanguageCode) -> ProbeClip {
        language == .english ? polish : english
    }

    /// Czy transkrypt zawiera co najmniej 2 z 3 oczekiwanych słów.
    public static func matches(_ text: String, _ clip: ProbeClip) -> Bool {
        let words = Set(normalize(text).split(separator: " ").map(String.init))
        return clip.expectedWords.filter { words.contains($0) }.count >= 2
    }

    public static func normalize(_ s: String) -> String {
        s.lowercased()
            .unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}
