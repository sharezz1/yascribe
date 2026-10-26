import Foundation

public enum LanguageCodeError: Error, Equatable {
    case empty
    /// 🔴 Nigdy `auto` (W§2, rozdz. 14: 62% zmyślonej angielszczyzny).
    case autoIsForbidden
    case malformed(String)
}

/// Kod języka ISO 639-1. Nie da się go zbudować z `auto` ani z pustego napisu —
/// „nigdy auto" jest egzekwowane typem, nie komentarzem.
public struct LanguageCode: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ raw: String) throws {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty else { throw LanguageCodeError.empty }
        guard v != "auto" else { throw LanguageCodeError.autoIsForbidden }
        guard v.count == 2, v.allSatisfy({ $0.isASCII && $0.isLetter }) else { throw LanguageCodeError.malformed(raw) }
        rawValue = v
    }

    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Nazwa po angielsku (do promptów i interfejsu): „Polish"; nieznany kod → sam kod.
    public var englishName: String { Self.selectable.first { $0.code == self }?.name ?? rawValue }

    public static let polish = try! LanguageCode("pl")
    public static let english = try! LanguageCode("en")

    /// Języki do wyboru w presecie, z nazwami po angielsku (interfejs jest po angielsku).
    public static let selectable: [(code: LanguageCode, name: String)] = [
        ("pl", "Polish"), ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("cs", "Czech"), ("sk", "Slovak"),
        ("uk", "Ukrainian"), ("ru", "Russian"), ("sv", "Swedish"), ("da", "Danish"), ("fi", "Finnish"),
    ].map { (try! LanguageCode($0.0), $0.1) }
}
