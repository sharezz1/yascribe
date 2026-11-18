import Foundation

/// Znaczniki mówców `[[SN]]` w notatce → bieżące nazwy. `keys` to `NoteSummary.speakers` (N → klucz z chwili generowania),
/// `names` imiona z `speakers.json`, `numbers` bieżąca numeracja kluczy (`SpeakerLabels.numbers`).
public struct SpeakerMarkers: Equatable, Sendable {
    public enum Resolution: Equatable, Sendable {
        case speaker(key: String, name: String, number: Int)
        case text(String)
    }

    public static let urlScheme = "yascribe-speaker"

    public let keys: [String: String]?
    public let names: [String: String]
    public let numbers: [String: Int]

    public init(keys: [String: String]?, names: [String: String], numbers: [String: Int]) {
        self.keys = keys
        self.names = names
        self.numbers = numbers
    }

    /// `nil` = znacznik zostaje dosłownie (brak mapy albo N spoza niej). Klucz, którego już nie ma (ponowne wykrycie
    /// mówców), daje sam tekst „Speaker N” — nigdy imienia osoby, która dziś nosi ten numer.
    public func resolve(_ marker: Int) -> Resolution? {
        guard let key = keys?[String(marker)] else { return nil }
        guard let number = numbers[key] else { return .text("Speaker \(marker)") }
        return .speaker(key: key, name: names[key] ?? "Speaker \(number)", number: number)
    }

    /// Tekst z nazwami zamiast znaczników (kopia, archiwum, CLI, tytuł).
    public func resolved(_ text: String) -> String {
        Self.replacing(text) { marker in
            switch resolve(marker) {
            case .speaker(_, let name, _): name
            case .text(let text): text
            case nil: nil
            }
        }
    }

    /// Bloki Markdown z nazwami; rozwiązany mówca dostaje `link` `yascribe-speaker:<bieżące N>` (klik w widoku notatki).
    public func linked(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        blocks.map { block in
            var block = block
            let plain = String(block.text.characters)
            for match in plain.matches(of: Self.pattern).reversed() {
                guard let marker = Int(match.output.1), let resolution = resolve(marker) else { continue }
                let start = block.text.characters.index(block.text.startIndex,
                                                        offsetBy: plain.distance(from: plain.startIndex, to: match.range.lowerBound))
                let end = block.text.characters.index(start, offsetBy: plain[match.range].count)
                var replacement: AttributedString
                switch resolution {
                case .speaker(_, let name, let number):
                    replacement = AttributedString(name, attributes: block.text[start..<end].runs.first?.attributes ?? AttributeContainer())
                    replacement.link = URL(string: "\(Self.urlScheme):\(number)")
                case .text(let text):
                    replacement = AttributedString(text, attributes: block.text[start..<end].runs.first?.attributes ?? AttributeContainer())
                }
                block.text.replaceSubrange(start..<end, with: replacement)
            }
            return block
        }
    }

    /// Tekst bez znaczników (sprawdzanie liczb: `[[S12]]` to nie liczba z notatki).
    public static func stripped(_ text: String) -> String { replacing(text) { _ in "" } }

    private static var pattern: Regex<(Substring, Substring)> { /\[\[S([1-9][0-9]*)\]\]/ }

    private static func replacing(_ text: String, with replacement: (Int) -> String?) -> String {
        guard text.contains("[[S") else { return text }
        var out = ""
        var last = text.startIndex
        for match in text.matches(of: pattern) {
            guard let marker = Int(match.output.1), let value = replacement(marker) else { continue }
            out += text[last..<match.range.lowerBound] + value
            last = match.range.upperBound
        }
        return out + text[last...]
    }
}
