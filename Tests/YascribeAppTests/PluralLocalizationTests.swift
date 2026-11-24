import Foundation
import Testing

@Test func pluralLookupsUseInterfaceLanguageForAllCounts() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let counts = [0, 1, 2, 5, 12, 22, 25]
    let cases: [(String, [String], [String])] = [
        ("%lld meetings", ["meetings", "meeting", "meetings", "meetings", "meetings", "meetings", "meetings"], ["spotkań", "spotkanie", "spotkania", "spotkań", "spotkań", "spotkania", "spotkań"]),
        ("%lld meetings (from)", ["meetings", "meeting", "meetings", "meetings", "meetings", "meetings", "meetings"], ["spotkań", "spotkania", "spotkań", "spotkań", "spotkań", "spotkań", "spotkań"]),
        ("%lld days", ["days", "day", "days", "days", "days", "days", "days"], ["dni", "dzień", "dni", "dni", "dni", "dni", "dni"]),
        ("%lld terms", ["terms", "term", "terms", "terms", "terms", "terms", "terms"], ["terminów", "termin", "terminy", "terminów", "terminów", "terminy", "terminów"]),
        ("%lld aliases", ["aliases", "alias", "aliases", "aliases", "aliases", "aliases", "aliases"], ["aliasów", "alias", "aliasy", "aliasów", "aliasów", "aliasy", "aliasów"]),
        ("%lld samples", ["samples", "sample", "samples", "samples", "samples", "samples", "samples"], ["próbek", "próbka", "próbki", "próbek", "próbek", "próbki", "próbek"]),
        ("Partial — %lld gaps", ["gaps", "gap", "gaps", "gaps", "gaps", "gaps", "gaps"], ["luk", "luka", "luki", "luk", "luk", "luki", "luk"]),
    ]
    for (key, english, polish) in cases {
        for (language, words) in [("en", english), ("pl", polish)] {
            let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/\(language).lproj")))
            let format = bundle.localizedString(forKey: key, value: nil, table: nil)
            for (count, word) in zip(counts, words) {
                let actual = String(format: format, locale: Locale(identifier: language), Int64(count))
                let prefix = key.hasPrefix("Partial") ? (language == "pl" ? "Częściowo — " : "Partial — ") : ""
                #expect(actual == "\(prefix)\(count) \(word)", "\(language) \(key) \(count): \(actual)")
            }
        }
    }
}

@Test func pluralResourcesHaveRequiredFormsAndBaseKeys() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let plStrings = try Data(contentsOf: root.appendingPathComponent("Resources/pl.lproj/Localizable.strings"))
    let base = try #require(PropertyListSerialization.propertyList(from: plStrings, format: nil) as? [String: String])
    var keys: Set<String> = []
    for language in ["en", "pl"] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(language).lproj/Localizable.stringsdict"))
        let table = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]])
        if language == "en" { keys = Set(table.keys) } else { #expect(Set(table.keys) == keys) }
        for (key, entry) in table {
            #expect(base[key]?.isEmpty == false, "Missing base key: \(key)")
            #expect(entry["NSStringLocalizedFormatKey"] as? String == "%#@count@")
            let count = try #require(entry["count"] as? [String: String])
            #expect(count["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType")
            #expect(count["NSStringFormatValueTypeKey"] == "lld")
            for form in language == "pl" ? ["one", "few", "many", "other"] : ["one", "other"] {
                #expect(count[form]?.contains("%lld") == true, "\(language) \(key) \(form)")
            }
        }
    }
}

@Test func everyPluralLookupMatchesItsLanguageRules() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for (language, locale) in [("en", "en_PL"), ("pl", "pl_US")] {
        let directory = root.appendingPathComponent("Resources/\(language).lproj")
        let bundle = try #require(Bundle(url: directory))
        let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.stringsdict"))
        let table = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]])
        for (key, entry) in table {
            let forms = try #require(entry["count"] as? [String: String])
            let format = bundle.localizedString(forKey: key, value: nil, table: nil)
            for n in [0, 1, 2, 5, 12, 22, 25] {
                let category = n == 1 ? "one" : (language == "en" ? "other" : ((2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "few" : "many"))
                let expectedFormat = try #require(forms[category])
                let expected = String(format: expectedFormat, locale: Locale(identifier: locale), Int64(n))
                let actual = String(format: format, locale: Locale(identifier: locale), Int64(n))
                #expect(actual == expected, "\(language) \(key) \(n): \(actual)")
            }
        }
    }
}
