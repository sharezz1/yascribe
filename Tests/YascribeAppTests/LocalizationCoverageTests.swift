import Foundation
import SwiftUI
import Testing

private let localizationRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private struct SwiftLiteral {
    let spelling: String
    let parts: [String]
    let specifiers: [String?]
    let line: Int
}

private struct SwiftToken {
    var text = ""
    var literal: SwiftLiteral? = nil
}

// Czytnik zachowuje granice argumentów i osobno skanuje kod wewnątrz interpolacji.
private struct SwiftLiteralReader {
    let source: [Character]
    var index = 0
    var line = 1
    var interpolations: [[SwiftToken]] = []

    init(_ source: String) { self.source = Array(source) }

    private var current: Character? { index < source.count ? source[index] : nil }

    private func at(_ text: String) -> Bool {
        source[index...].starts(with: text)
    }

    @discardableResult
    private mutating func take() -> Character {
        let character = source[index]
        index += 1
        if character.isNewline { line += 1 }
        return character
    }

    mutating func tokens(untilClosingParen: Bool = false) -> [SwiftToken] {
        var tokens: [SwiftToken] = []
        var depth = 0
        while let character = current {
            if character.isWhitespace {
                take()
            } else if at("//") {
                while let character = current, !character.isNewline { take() }
            } else if at("/*") {
                var nesting = 1
                index += 2
                while current != nil, nesting > 0 {
                    if at("/*") { nesting += 1; index += 2 }
                    else if at("*/") { nesting -= 1; index += 2 }
                    else { take() }
                }
            } else {
                let start = index
                while current == "#" { take() }
                if current == "\"" {
                    tokens.append(SwiftToken(literal: literal(hashes: String(source[start..<index]))))
                    continue
                }
                index = start
                if character == ")" && untilClosingParen && depth == 0 { take(); break }
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if character.isLetter || character.isNumber || character == "_" {
                    while let character = current, character.isLetter || character.isNumber || character == "_" { take() }
                } else if at("??") || at("==") || at("!=") || at("?.") {
                    index += 2
                } else {
                    take()
                }
                let text = String(source[start..<index])
                let postfixQuestion = text == "?" && start > 0 && !source[start - 1].isWhitespace
                tokens.append(SwiftToken(text: postfixQuestion ? "postfix?" : text))
            }
        }
        return tokens
    }

    private mutating func literal(hashes: String) -> SwiftLiteral {
        let startLine = line
        let quote = at("\"\"\"") ? "\"\"\"" : "\""
        let delimiter = quote + hashes
        let escape = "\\" + hashes
        index += quote.count
        let start = index
        var parts: [String] = []
        var specifiers: [String?] = []
        var part = ""
        while let character = current, !at(delimiter) {
            if at(escape) {
                index += escape.count
                guard current != nil else { break }
                switch take() {
                case "(":
                    parts.append(part)
                    part = ""
                    let nested = tokens(untilClosingParen: true)
                    specifiers.append(Self.specifier(for: nested))
                    interpolations.append(nested)
                case "n": part += "\n"
                case "r": part += "\r"
                case "t": part += "\t"
                case "0": part += "\0"
                case "u" where current == "{":
                    take()
                    let digits = index
                    while let character = current, character.isHexDigit { take() }
                    if let value = UInt32(String(source[digits..<index]), radix: 16),
                       let scalar = Unicode.Scalar(value) { part.unicodeScalars.append(scalar) }
                    if current == "}" { take() }
                case let escaped where escaped.isNewline:
                    while current == " " || current == "\t" { take() }
                case let escaped: part.append(escaped)
                }
            } else {
                part.append(character)
                take()
            }
        }
        parts.append(part)
        let spelling = String(source[start..<index])
        if quote.count == 3, let newline = parts[parts.count - 1].lastIndex(where: \.isNewline) {
            let indentation = String(parts[parts.count - 1].suffix(from: parts[parts.count - 1].index(after: newline)))
            parts[parts.count - 1].removeSubrange(newline...)
            for i in parts.indices {
                // Wcięcie usuwa się tylko na początku wiersza, nie po interpolacji.
                parts[i] = parts[i].replacingOccurrences(of: "\n" + indentation, with: "\n")
            }
            if parts[0].hasPrefix("\n") { parts[0].removeFirst() }
        }
        if at(delimiter) { index += delimiter.count }
        return SwiftLiteral(spelling: spelling, parts: parts, specifiers: specifiers, line: startLine)
    }

    private static func specifier(for expression: [SwiftToken]) -> String? {
        let words = expression.map(\.text)
        if expression.count == 1, expression[0].literal != nil { return "%@" }
        if words.first == "count", words.count == 1 { return "%lld" }
        if words.last == "count", words.dropLast().last == ".",
           words.allSatisfy({ $0 == "." || $0.first?.isLetter == true || $0.first == "_" }) {
            return "%lld"
        }
        guard words.dropFirst().first == "(", words.last == ")" else { return nil }
        switch words.first {
        case "Int", "Int64": return "%lld"
        case "String": return "%@"
        default: return nil
        }
    }
}

private struct LocalizationUse {
    enum Lookup: Equatable { case localized, plain, verbatim, canonical }
    let literal: SwiftLiteral
    let api: String
    let lookup: Lookup
}

private struct LocalizationScanner {
    let tokens: [SwiftToken]
    let groups: [Int: Int]

    init(_ tokens: [SwiftToken]) {
        self.tokens = tokens
        var groups: [Int: Int] = [:]
        var stack: [Int] = []
        let opening = ["(": ")", "[": "]", "{": "}"]
        for i in tokens.indices {
            if opening[tokens[i].text] != nil {
                stack.append(i)
            } else if let start = stack.last, opening[tokens[start].text] == tokens[i].text {
                groups[start] = i
                stack.removeLast()
            }
        }
        self.groups = groups
    }

    private func text(_ i: Int) -> String { tokens.indices.contains(i) ? tokens[i].text : "" }

    private func topLevel(_ range: Range<Int>) -> [Int] {
        var indices: [Int] = []
        var i = range.lowerBound
        while i < range.upperBound {
            indices.append(i)
            i = groups[i].map { $0 + 1 } ?? (i + 1)
        }
        return indices
    }

    private func pieces(_ range: Range<Int>) -> [Range<Int>] {
        var start = range.lowerBound
        var pieces: [Range<Int>] = []
        for i in topLevel(range) where text(i) == "," {
            pieces.append(start..<i)
            start = i + 1
        }
        if start < range.upperBound { pieces.append(start..<range.upperBound) }
        return pieces
    }

    private func literals(_ range: Range<Int>, api: String, lookup: LocalizationUse.Lookup) -> [LocalizationUse] {
        guard let first = range.first else { return [] }
        let indices = topLevel(range)
        if text(first) == "(", groups[first] == range.upperBound - 1 {
            return literals((first + 1)..<(range.upperBound - 1), api: api, lookup: lookup)
        }
        if let question = indices.first(where: { text($0) == "?" }) {
            var depth = 0
            for i in indices where i > question {
                if text(i) == "?" { depth += 1 }
                if text(i) == ":" {
                    if depth == 0 {
                        return literals((question + 1)..<i, api: api, lookup: lookup)
                            + literals((i + 1)..<range.upperBound, api: api, lookup: lookup)
                    }
                    depth -= 1
                }
            }
        }
        let separators = indices.filter { ["??", "+"].contains(text($0)) }
        if !separators.isEmpty {
            let mode = lookup == .localized ? .plain : lookup
            let starts = [first] + separators.map { $0 + 1 }
            return zip(starts, separators + [range.upperBound]).flatMap { literals($0..<$1, api: api, lookup: mode) }
        }
        guard let literal = tokens[first].literal else { return [] }
        return [LocalizationUse(literal: literal, api: api, lookup: lookup)]
    }

    private static let swiftUICalls: Set = [
        "Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField", "Menu", "CommandMenu",
        "ContentUnavailableView", "ProgressView", "LabeledContent", "WindowGroup", "Window", "MenuBarExtra"
    ]
    private static let modifiers: Set = [
        "help", "alert", "confirmationDialog", "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue"
    ]
    private static let plainArguments: [String: Set<String>] = [
        "PageTitle": ["0"], "SectionHeader": ["0", "note"], "FormRow": ["label", "caption"],
        "StateLabel": ["1"], "WarnLabel": ["0"], "FieldMenu": ["label", "value", "prefix"],
        "EditorSheet": ["title", "error", "actionReason"], "EditorListRow": ["0", "subtitle"],
        "LinkButton": ["0"], "EditorNameField": ["placeholder"], "RoleSection": ["title"], "ErrorLine": ["message"],
        "SheetRow": ["label"], "SheetSection": ["title"], "SheetNote": ["0"], "SheetAction": ["title", "reason"],
        "PillIconButton": ["label"], "NSMenuItem": ["title"], "addButton": ["withTitle"]
    ]
    private static let errorArguments: [String: Set<String>] = [
        "ModelStoreError": ["message"], "DiarizerModelStoreError": ["message"],
        "WAVDecodeError": ["message"], "ClientProblem": ["message"], "Unavailable": ["reason"]
    ]

    func uses(inApp: Bool) -> [LocalizationUse] {
        var uses: [LocalizationUse] = []
        for i in tokens.indices {
            let api = text(i)
            if api == "errorDescription", text(i - 1) == "var", text(i + 1) == ":",
               text(i + 2) == "String" {
                let body = i + (text(i + 3) == "postfix?" ? 4 : 3)
                if text(body) == "{", let end = groups[body] {
                    uses += returnedLiterals((body + 1)..<end)
                } else if text(body) == "=" {
                    let expression = (body + 1)..<tokens.count
                    uses += literals(expression.lowerBound..<expressionEnd(expression), api: api, lookup: .plain)
                }
            }
            let isPanelProperty = ["prompt", "message", "title"].contains(api) && text(i - 2) == "panel"
            let isLastErrorLiteral = api == "lastError" && tokens.indices.contains(i + 2) && tokens[i + 2].literal != nil
            if inApp, (["messageText", "informativeText", "placeholderString"].contains(api) || isPanelProperty || isLastErrorLiteral),
               text(i + 1) == "=" {
                let start = i + 2
                let end = expressionEnd(start..<tokens.count)
                uses += literals(start..<end, api: api, lookup: .plain)
            }
            guard text(i + 1) == "(", let end = groups[i + 1] else { continue }
            let localized: Set<String>
            if api == "String" { localized = ["localized"] }
            else if api == "NSLocalizedString" || api == "localizedString" { localized = [api == "NSLocalizedString" ? "0" : "forKey"] }
            else if inApp && api == "accessibilityAction" && text(i - 1) == "." { localized = ["named"] }
            else if inApp && (Self.swiftUICalls.contains(api) || (Self.modifiers.contains(api) && text(i - 1) == ".")) {
                localized = ["0"]
            } else { localized = [] }
            let plain = inApp ? Self.plainArguments[api, default: []] : []
            let canonical = Self.errorArguments[api, default: []]
            let arguments = pieces((i + 2)..<end)
            let hasDisplayMessage = arguments.contains { text($0.lowerBound) == "displayMessage" && text($0.lowerBound + 1) == ":" }
            for (position, argument) in arguments.enumerated() {
                let first = argument.lowerBound
                let labeled = text(first + 1) == ":"
                let label = labeled ? text(first) : String(position)
                let range = (first + (labeled ? 2 : 0))..<argument.upperBound
                if localized.contains(label) {
                    uses += literals(range, api: api, lookup: .localized)
                } else if canonical.contains(label) {
                    let paired = api == "ClientProblem"
                        || ["ModelStoreError", "DiarizerModelStoreError"].contains(api) && hasDisplayMessage
                    uses += literals(range, api: api, lookup: paired ? .canonical : .plain)
                } else if plain.contains(label) || label == "errorDescription" || (inApp && label == "message") {
                    uses += literals(range, api: label == "errorDescription" ? "errorDescription" : api, lookup: .plain)
                } else if api == "Text", label == "verbatim" {
                    uses += literals(range, api: api, lookup: .verbatim)
                }
            }
        }
        return uses
    }

    private func expressionEnd(_ range: Range<Int>) -> Int {
        topLevel(range).first { [";", "}", "return", "case", "default", "else", "let", "var"].contains(text($0)) }
            ?? range.upperBound
    }

    private func returnedLiterals(_ body: Range<Int>) -> [LocalizationUse] {
        let indices = topLevel(body)
        var uses: [LocalizationUse] = []
        var inCase = false
        for i in indices {
            switch text(i) {
            case "case", "default": inCase = true
            case "return",
                 ":" where inCase:
                inCase = false
                let expression = (i + 1)..<body.upperBound
                uses += literals(expression.lowerBound..<expressionEnd(expression), api: "errorDescription", lookup: .plain)
            case "{":
                if let end = groups[i] { uses += returnedLiterals((i + 1)..<end) }
            default:
                if i == body.lowerBound {
                    uses += literals(body.lowerBound..<expressionEnd(body), api: "errorDescription", lookup: .plain)
                }
            }
        }
        return uses
    }
}

private func scanLocalization(_ source: String, inApp: Bool) -> [LocalizationUse] {
    var reader = SwiftLiteralReader(source)
    let tokens = reader.tokens()
    return ([tokens] + reader.interpolations).flatMap { LocalizationScanner($0).uses(inApp: inApp) }
}

private enum LocalizationFormat {
    static let conversion = #"(?:hh|ll|[hljztLq])?[@diouxXfFeEgGaAcCsSp]"#
    static let specification = #"%(?:[1-9][0-9]*\$)?[-+#0']*[0-9]*(?:\.[0-9]+)?"# + conversion
    private static let regex = try! NSRegularExpression(
        pattern: #"%%|%(?:([1-9][0-9]*)\$)?[-+#0']*[0-9]*(?:\.[0-9]+)?("# + conversion + ")"
    )

    struct Signature: Equatable {
        let arguments: [Int: [String]]
        let percentSigns: Int
    }

    static func signature(_ format: String) -> Signature {
        let string = format as NSString
        var arguments: [Int: [String]] = [:]
        var next = 1
        var percentSigns = 0
        for match in regex.matches(in: format, range: NSRange(location: 0, length: string.length)) {
            guard match.range(at: 2).location != NSNotFound else {
                percentSigns += 1
                continue
            }
            let position = match.range(at: 1).location == NSNotFound ? nil : Int(string.substring(with: match.range(at: 1)))
            let conversion = string.substring(with: match.range(at: 2))
            let type = switch conversion.last {
            case "i", "d": String(conversion.dropLast()) + "d"
            case "u", "o", "x", "X": String(conversion.dropLast()) + "u"
            case "a", "A", "e", "E", "f", "F", "g", "G": conversion.hasPrefix("L") ? "long double" : "double"
            default: conversion
            }
            arguments[position ?? next, default: []].append(type)
            if position == nil { next += 1 }
        }
        return Signature(arguments: arguments.mapValues { $0.sorted() }, percentSigns: percentSigns)
    }

    static func matches(_ literal: SwiftLiteral, keys: Set<String>) -> Bool {
        if literal.parts.count == 1 { return keys.contains(literal.parts[0]) }
        let parts = literal.parts.map { NSRegularExpression.escapedPattern(for: $0.replacingOccurrences(of: "%", with: "%%")) }
        var pattern = "\\A" + parts[0]
        for (specifier, part) in zip(literal.specifiers, parts.dropFirst()) {
            pattern += (specifier ?? "(?:" + specification + ")") + part
        }
        pattern += "\\z"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return keys.contains { key in
            regex.firstMatch(in: key, range: NSRange(key.startIndex..<key.endIndex, in: key)) != nil
        }
    }
}

private struct LocalizationTables {
    let strings: [String: String]
    let plurals: [String: [String: Any]]

    init(root: URL) throws {
        let polish = root.appendingPathComponent("Resources/pl.lproj")
        func read<T>(_ file: String, as type: T.Type) throws -> T {
            let data = try Data(contentsOf: polish.appendingPathComponent(file))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let value = plist as? T else { throw CocoaError(.propertyListReadCorrupt) }
            return value
        }
        strings = try read("Localizable.strings", as: [String: String].self)
        plurals = try read("Localizable.stringsdict", as: [String: [String: Any]].self)
    }

    func problems() -> [String] {
        var problems: [String] = []
        if strings.isEmpty || plurals.isEmpty { problems.append("Empty Polish localization table") }
        for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("Blank Polish key or translation: \(key.debugDescription)")
            }
            if LocalizationFormat.signature(key) != LocalizationFormat.signature(value) {
                problems.append("Format specifiers differ: \(key.debugDescription) → \(value.debugDescription)")
            }
        }
        for key in plurals.keys.sorted() {
            guard let entry = plurals[key],
                  let format = entry["NSStringLocalizedFormatKey"] as? String,
                  let variable = format.range(of: #"^%#@[A-Za-z_][A-Za-z_0-9]*@$"#, options: .regularExpression),
                  let rule = entry[String(format[variable].dropFirst(3).dropLast())] as? [String: String],
                  rule["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType",
                  let type = rule["NSStringFormatValueTypeKey"],
                  ["d", "i", "ld", "li", "lld", "lli", "u", "lu", "llu"].contains(type),
                  LocalizationFormat.signature("%" + type).arguments == LocalizationFormat.signature(key).arguments else {
                problems.append("Invalid Polish plural rule: \(key.debugDescription)")
                continue
            }
            if strings[key] == nil { problems.append("Missing Polish base entry for plural: \(key.debugDescription)") }
            for category in ["one", "few", "many", "other"] {
                guard let value = rule[category], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      LocalizationFormat.signature(value) == LocalizationFormat.signature(key) else {
                    problems.append("Missing or invalid Polish plural variant \(category): \(key.debugDescription)")
                    continue
                }
            }
        }
        return problems
    }
}

private func isAllowed(_ use: LocalizationUse, in file: String) -> Bool {
    let literal = use.literal.spelling
    switch (use.api, literal) {
    case (_, "Yascribe"): return true // Nazwa aplikacji.
    case ("Text", "Polski"), ("Text", "English"): return true // Endonimy w menu języka.
    case ("Text", "00:00:00"), ("Text", "—"), ("Text", " ·"): return true // Zegar i separatory.
    case ("Text", ""), ("Toggle", ""), ("Button", ""), ("SheetRow", ""), ("help", ""), ("FormRow", ""):
        return use.lookup != .verbatim // Puste etykiety, podpisy i dymki techniczne.
    default: break
    }
    switch (file, use.api, literal) {
    case ("Sources/YascribeApp/DictionaryView.swift", "Text", "Roky, Rokm"),
         ("Sources/YascribeApp/DictionaryView.swift", "Text", "Nimbu"):
        return true // Przykładowe nazwy i aliasy słownika.
    case ("Sources/YascribeApp/SettingsView.swift", "TextField", "yyy, eee, mhm"),
         ("Sources/YascribeApp/SettingsView.swift", "TextField", "/opt/homebrew/bin/codex"),
         ("Sources/YascribeApp/SettingsView.swift", "TextField", "https://example.com/v1"):
        return true // Przykładowe dane wejściowe, ścieżka i URL.
    case ("Sources/YascribeApp/Snapshots.swift", "Text", "openrouter.ai"),
         ("Sources/YascribeApp/Snapshots.swift", "Button", "Ollama"):
        return true // Adres i nazwa dostawcy w danych galerii.
    case ("Sources/YascribeApp/ArchiveModel.swift", "Failure",
          #"\(prefix) \(provider.name): \(Self.reason(error, model: model, provider: provider, transport: transport, maxTokens: maxTokens))"#):
        return true // Zapis rozmowy; ArchivePresentation rozpoznaje prefiks i tłumaczy cały komunikat.
    case ("Sources/YascribeLocalASR/Diarization/DiarizerModelGate.swift", "DiarizerModelStoreError", "model missing, run with --download"):
        return true // DiarizerModelGate.decide: składnia CLI.
    case ("Sources/YascribeLocalASR/WAVDecoder.swift", "WAVDecodeError", "Not a WAV file."),
         ("Sources/YascribeLocalASR/WAVDecoder.swift", "WAVDecodeError", "Malformed WAV fmt chunk."),
         ("Sources/YascribeLocalASR/WAVDecoder.swift", "WAVDecodeError", "WAV data before fmt chunk."),
         ("Sources/YascribeLocalASR/WAVDecoder.swift", "WAVDecodeError", #"Expected 16 kHz mono 16-bit PCM, got \(f.rate) Hz, \(f.channels) ch, \(f.bits) bit."#),
         ("Sources/YascribeLocalASR/WAVDecoder.swift", "WAVDecodeError", "WAV has no data chunk."):
        return true // WAVDecoder.samples: diagnostyka CLI i ChunkFailure.error.
    case ("Sources/YascribeTranscription/SpeakerDiarizationStats.swift", "errorDescription",
          #"--sensitivity \(value): use \(SpeakerSensitivity.allCases.map(\.rawValue).joined(separator: "|"))"#):
        return true // SpeakerSensitivityError.errorDescription: składnia CLI.
    default: return false
    }
}

private func isCanonicalPresentation(_ use: LocalizationUse, in file: String) -> Bool {
    switch (file, use.api, use.literal.spelling) {
    case ("Sources/YascribeApp/ArchiveModel.swift", "Failure", "Meetings are being moved to a new folder. Ask again when that finishes."),
         ("Sources/YascribeApp/ArchiveModel.swift", "Failure", "Open a meeting first, or choose All meetings."):
        return true // Zapis rozmowy, lookup w ArchivePresentation.
    case ("Sources/YascribeNotes/ArchiveIndex.swift", "errorDescription", "The embedding model returned vectors of a different size than the archive index uses."),
         ("Sources/YascribeNotes/ArchiveIndex.swift", "errorDescription", "The embedding model returned an unusable vector."),
         ("Sources/YascribeNotes/ArchiveIndex.swift", "errorDescription", "The model's Context window is too small to answer from your meetings."):
        return true // ArchiveError.errorDescription: zapis rozmowy, lookup w ArchivePresentation.
    case ("Sources/YascribeTranscription/CloudDiarization.swift", "errorDescription", "Recording too long for speaker detection."),
         ("Sources/YascribeTranscription/CloudDiarization.swift", "errorDescription", "Could not encode audio for speaker detection."):
        return true // CloudDiarizationError.errorDescription: CLI, lookup w displayMessage.
    default: return false
    }
}

private func localizationProblems(root: URL, tables: LocalizationTables) throws -> [String] {
    let sources = root.appendingPathComponent("Sources")
    let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
    let keys = Set(tables.strings.keys).union(tables.plurals.keys)
    var problems: [String] = []
    for module in files.sorted(by: { $0.path < $1.path }) where module.lastPathComponent.hasPrefix("Yascribe") {
        guard let sources = FileManager.default.enumerator(at: module, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: module.path])
        }
        for case let file as URL in sources where file.pathExtension == "swift" {
            let path = String(file.path.dropFirst(root.path.count + 1))
            let source = try String(contentsOf: file, encoding: .utf8)
            for use in scanLocalization(source, inApp: module.lastPathComponent == "YascribeApp") where !isAllowed(use, in: path) {
                let description = "\(path):\(use.literal.line): \(use.api) \(use.literal.spelling.debugDescription)"
                if use.lookup == .verbatim || (use.lookup == .plain && !isCanonicalPresentation(use, in: path)) {
                    problems.append("\(description): bypasses localization")
                } else if !LocalizationFormat.matches(use.literal, keys: keys) {
                    problems.append("\(description): missing Polish key")
                }
            }
        }
    }
    return problems.sorted()
}

@Test func polishLocalizationEntriesAndFormatsAreValid() throws {
    let tables = try LocalizationTables(root: localizationRoot)
    for problem in tables.problems() { Issue.record(Comment(rawValue: problem)) }
}

@Test func polishLocalizationCoversUIAndLibraryLiterals() throws {
    let tables = try LocalizationTables(root: localizationRoot)
    for problem in try localizationProblems(root: localizationRoot, tables: tables) {
        Issue.record(Comment(rawValue: problem))
    }
}

@Test func localizationScannerFindsEachUIArgumentFamily() {
    let calls: [(String, String, LocalizationUse.Lookup)] = [
        (#"Text("Literal")"#, "Text", .localized),
        (#"Text(verbatim: "Literal")"#, "Text", .verbatim),
        (#"Button("Literal", role: .cancel, action: close)"#, "Button", .localized),
        (#"Label("Literal", systemImage: "ignored")"#, "Label", .localized),
        (#"Toggle("Literal", isOn: $enabled)"#, "Toggle", .localized),
        (#"Picker("Literal", selection: $choice) {}"#, "Picker", .localized),
        (#"TextField("Literal", text: $value)"#, "TextField", .localized),
        (#"SecureField("Literal", text: $secret)"#, "SecureField", .localized),
        (#"Menu("Literal") {}"#, "Menu", .localized),
        (#"CommandMenu("Literal") {}"#, "CommandMenu", .localized),
        (#"ContentUnavailableView("Literal", systemImage: "ignored")"#, "ContentUnavailableView", .localized),
        (#"view.help("Literal")"#, "help", .localized),
        (#"view.alert("Literal", isPresented: $show) {}"#, "alert", .localized),
        (#"view.confirmationDialog("Literal", isPresented: $show) {}"#, "confirmationDialog", .localized),
        (#"view.navigationTitle("Literal")"#, "navigationTitle", .localized),
        (#"view.accessibilityLabel("Literal")"#, "accessibilityLabel", .localized),
        (#"view.accessibilityHint("Literal")"#, "accessibilityHint", .localized),
        (#"view.accessibilityValue("Literal")"#, "accessibilityValue", .localized),
        (#"view.accessibilityAction(named: "Literal") {}"#, "accessibilityAction", .localized),
        (#"String(localized: "Literal")"#, "String", .localized),
        (#"NSLocalizedString("Literal", comment: "ignored")"#, "NSLocalizedString", .localized),
        (#"alert.messageText = "Literal""#, "messageText", .plain),
        (#"alert.informativeText = "Literal""#, "informativeText", .plain),
        (#"alert.addButton(withTitle: "Literal")"#, "addButton", .plain),
        (#"NSMenuItem(title: "Literal", action: nil, keyEquivalent: "ignored")"#, "NSMenuItem", .plain),
        (#"field.placeholderString = "Literal""#, "placeholderString", .plain),
        (#"panel.prompt = "Literal""#, "prompt", .plain),
        (#"panel.message = "Literal""#, "message", .plain),
        (#"model.lastError = "Literal""#, "lastError", .plain),
        (#"Problem(message: "Literal")"#, "Problem", .plain),
        (#".failure(Problem(message: "Literal"))"#, "Problem", .plain),
        (#".failure(ClientProblem(message: "Literal"))"#, "ClientProblem", .canonical),
        (#"PageTitle("Literal")"#, "PageTitle", .plain),
        (#"SectionHeader(heading, note: "Literal")"#, "SectionHeader", .plain),
        (#"FormRow(label: "Literal") {}"#, "FormRow", .plain),
        (#"StateLabel(kind, "Literal")"#, "StateLabel", .plain),
        (#"WarnLabel("Literal")"#, "WarnLabel", .plain),
        (#"FieldMenu(label: "Literal", value: number) {}"#, "FieldMenu", .plain),
        (#"EditorSheet(title: "Literal", dirty: false) {}"#, "EditorSheet", .plain)
    ]
    for (source, api, lookup) in calls {
        let uses = scanLocalization(source, inApp: true)
        #expect(uses.map(\.literal.spelling) == ["Literal"], Comment(rawValue: source))
        #expect(uses.first?.api == api)
        #expect(uses.first?.lookup == lookup)
    }
}

@Test func localizationScannerReadsBranchesAndNestedInterpolation() throws {
    let source = ##"""
        // Text("ignored")
        /* nested /* Text("ignored") */ Button("ignored") */
        let raw = #"Text("ignored")"#
        .help(
            id == "ignored" ? ("First") : ready ? "Second" : "Third"
        )
        Text("File \"\(name ?? String(localized: "Unknown"))\"\n\(size(value: (1, 2))) at \(speed)%")
        """##
    let uses = scanLocalization(source, inApp: true)
    #expect(uses.filter { $0.api == "help" }.map(\.literal.spelling) == ["First", "Second", "Third"])
    let displayed = try #require(uses.first { $0.api == "Text" }?.literal)
    #expect(displayed.line == 7)
    #expect(displayed.parts == ["File \"", "\"\n", " at ", "%"])
    #expect(LocalizationFormat.matches(displayed, keys: ["File \"%@\"\n%lld at %.1f%%"]))
    #expect(!LocalizationFormat.matches(displayed, keys: ["File \"%@\"\n%lld at %.1f%"]))
    #expect(!LocalizationFormat.matches(displayed, keys: ["File \"%@\"\n%lld at %lld %.1f%%"]))
    #expect(uses.filter { $0.api == "String" }.map(\.literal.spelling) == ["Unknown"])
    #expect(uses.count == 5)
}

@Test func localizationScannerFindsLibraryDescriptions() {
    let source = #"""
        var errorDescription: String? {
            switch self {
            case .a: "Implicit"
            case .b: return "Explicit"
            default: return special ? "Special" : "Default"
            }
        }
        let failure = SomeError(code: 4, errorDescription: "Initializer")
        let wav = WAVDecodeError(message: "Forwarded")
        let localized = String(localized: "Key")
        let foundation = NSLocalizedString("Other", comment: "ignored")
        let view = Text("ignored")
        """#
    let uses = scanLocalization(source, inApp: false)
    #expect(uses.map(\.literal.spelling) == ["Implicit", "Explicit", "Special", "Default", "Initializer", "Forwarded", "Key", "Other"])
    #expect(uses.filter { $0.lookup == .plain }.count == 6)
}

@Test func localizationFormatComparesTypesPositionsAndPercentSigns() {
    let expected = LocalizationFormat.signature("%@ / %lld / %.1f%%")
    #expect(expected == LocalizationFormat.signature("%3$.1lf%% %2$lli %1$@"))
    #expect(expected != LocalizationFormat.signature("%3$.1f%% %2$d %1$@"))
    #expect(expected != LocalizationFormat.signature("%3$.1f %2$lld %1$@"))
    #expect(expected != LocalizationFormat.signature("%3$.1f%% %2$lld %1$@ %1$@"))
    #expect(expected != LocalizationFormat.signature("%@ / %@ / %.1f%%"))
}

@Test func localizationScannerRequiresKnownInterpolationTypes() throws {
    let source = #"""
        Text("Count: \(count)")
        Text("Count: \(rows.count)")
        String(localized: "Count: \(Int64(value))")
        String(localized: "Count: \(Int(value))")
        Text("Name: \(String(value))")
        """#
    let literals = scanLocalization(source, inApp: true).map(\.literal)
    #expect(literals.count == 5)
    for literal in literals.prefix(4) {
        #expect(LocalizationFormat.matches(literal, keys: ["Count: %lld"]))
        #expect(!LocalizationFormat.matches(literal, keys: ["Count: %@"]))
    }
    let name = try #require(literals.last)
    #expect(LocalizationFormat.matches(name, keys: ["Name: %@"]))
    #expect(!LocalizationFormat.matches(name, keys: ["Name: %lld"]))
}

@Test @MainActor func swiftUIAndFoundationLookUpStringAndIntInterpolations() throws {
    let pl = try #require(Bundle(url: localizationRoot.appendingPathComponent("Resources/pl.lproj")))
    let name: String = "Settings"
    let count: Int = 22
    var environment = EnvironmentValues()
    environment.locale = Locale(identifier: "pl")
    #expect(Text("Appearance: \(name)", bundle: pl)._resolveText(in: environment) == "Wygląd: Settings")
    #expect(Text("\(count) terms", bundle: pl)._resolveText(in: environment) == "22 terminy")
    #expect(String(localized: "Appearance: \(name)", bundle: pl, locale: environment.locale) == "Wygląd: Settings")
    #expect(String(localized: "\(count) terms", bundle: pl, locale: environment.locale) == "22 terminy")
}

/// Teksty kanoniczne (zapis, CLI, cache sond, porównania): w procesie testów `Bundle.main` nie ma `pl.lproj`,
/// więc test wyniku nie złapie przypadkowej lokalizacji. Pilnujemy źródła: literał musi mieć wystąpienie bez lookupu.
@Test func canonicalLiteralsStayOutsideLocalization() throws {
    let canonical: [(String, String)] = [
        ("Sources/YascribeLocalASR/RunGate.swift", #"RunGateRefusal(message: "The on-device speech model failed its check: "#), // RunGate.check
        ("Sources/YascribeTranscription/CloudDiarization.swift", #""Recording too long for speaker detection.""#), // opis kanoniczny
        ("Sources/YascribeProviders/ProviderSetup.swift", #""The reply was cut off before the end.""#), // ProviderCheck.describe → ProbeResult
        ("Sources/YascribeProviders/ProviderSetup.swift", #""Invalid API key.""#), // ProviderCheck.describe
        ("Sources/YascribeNotes/NoteTitle.swift", #"static let untitled = "Untitled meeting""#), // AutoTitle.clean
    ]
    for (file, literal) in canonical {
        let source = try String(contentsOf: localizationRoot.appendingPathComponent(file), encoding: .utf8)
        let plain = source.split(separator: "\n").filter { $0.contains(literal) && !$0.contains("localized") && !$0.contains("Localized") }
        #expect(!plain.isEmpty, "\(file): \(literal) is localized or gone")
    }
}
