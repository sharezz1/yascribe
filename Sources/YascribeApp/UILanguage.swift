import AppKit
import Foundation

enum UILanguage: String, CaseIterable {
    case auto, pl, en

    static func current(in defaults: UserDefaults = .standard) -> UILanguage {
        defaults.string(forKey: "uiLanguage").flatMap(UILanguage.init(rawValue:)) ?? .auto
    }

    @discardableResult
    func select(in defaults: UserDefaults = .standard,
                domain: String = Bundle.main.bundleIdentifier ?? "io.github.sharezz1.yascribe") -> Bool {
        let preferences = defaults.persistentDomain(forName: domain) ?? [:]
        let selection = preferences["uiLanguage"] as? String
        let languages = preferences["AppleLanguages"]
        let selectionMatches = selection == rawValue || (self == .auto && preferences["uiLanguage"] == nil)
        let languagesMatch = self == .auto ? languages == nil : (languages as? [String]) == [rawValue]
        guard !selectionMatches || !languagesMatch else { return false }
        defaults.set(rawValue, forKey: "uiLanguage")
        switch self {
        case .auto: defaults.removeObject(forKey: "AppleLanguages")
        case .pl, .en: defaults.set([rawValue], forKey: "AppleLanguages")
        }
        return true
    }
}

@MainActor
final class LanguageSelection: ObservableObject {
    @Published var showRestart = false

    func select(_ language: UILanguage) {
        guard language.select() else { return }
        showRestart = true
    }
}

@MainActor
final class LanguageRestart {
    var requested = false

    func request(ifIdle idle: Bool, terminate: () -> Void) {
        guard idle else { return }
        requested = true
        terminate()
    }

    func consume(ifIdle idle: Bool, launch: () throws -> Void) -> Bool {
        guard requested else { return false }
        requested = false
        guard idle else { return false }
        do { try launch(); return true } catch { return false }
    }

    static func launch() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            if /bin/ps -axww -o comm= | /usr/bin/grep -Fxq -- "$2"; then exit 0; fi
            exec "$2"
            """, "yascribe-restart", String(ProcessInfo.processInfo.processIdentifier), executable.path]
        try process.run()
    }
}
