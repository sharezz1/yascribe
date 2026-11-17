import Foundation
import YascribeProviders

public struct KnownPeople: Codable, Sendable {
    public var names: [String] = []

    public init(names: [String] = []) { self.names = names }

    public mutating func use(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        names.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        names.insert(name, at: 0)
        if names.count > 200 { names.removeLast(names.count - 200) }
    }

    public static func load(root: URL) -> KnownPeople {
        (try? JSONFile.load(KnownPeople.self, from: root.appendingPathComponent("people.json"), default: KnownPeople())) ?? KnownPeople()
    }

    public func save(root: URL) throws {
        try JSONFile.save(self, to: root.appendingPathComponent("people.json"))
    }
}
