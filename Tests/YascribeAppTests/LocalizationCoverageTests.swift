import Foundation
import Testing

private let localizationRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func polishLocalizationEntriesAreNotBlank() throws {
    let data = try Data(contentsOf: localizationRoot.appendingPathComponent("Resources/pl.lproj/Localizable.strings"))
    let table = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    #expect(!table.isEmpty)
    for (key, value) in table {
        #expect(!key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty localization key")
        #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty translation: \(key)")
    }
}

@Test func staticFoundationLocalizationKeysExistInPolish() throws {
    let data = try Data(contentsOf: localizationRoot.appendingPathComponent("Resources/pl.lproj/Localizable.strings"))
    let table = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    let sources = localizationRoot.appendingPathComponent("Sources")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    let pattern = #"(?:String\s*\(\s*localized\s*:|NSLocalizedString\s*\()\s*\"((?:\\.|[^\"\\])*)\""#
    let regex = try NSRegularExpression(pattern: pattern)
    for case let file as URL in files where file.pathExtension == "swift" && file.pathComponents.contains(where: { $0.hasPrefix("Yascribe") }) {
        let source = try String(contentsOf: file, encoding: .utf8)
        let ns = source as NSString
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let literal = ns.substring(with: match.range(at: 1))
            // Interpolacje wymagają osobnego czytnika składni Swift.
            if literal.contains(#"\("#) { continue }
            let key = literal.replacingOccurrences(of: #"\""#, with: "\"")
                .replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\\"#, with: #"\"#)
            let line = ns.substring(to: match.range.location).filter { $0 == "\n" }.count + 1
            #expect(table[key] != nil, "\(file.path):\(line): missing key \(key)")
        }
    }
}
