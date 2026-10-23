import Foundation

/// Urządzenie wejściowe do wyboru w pigułce (menu przy mikrofonie).
public struct InputDevice: Equatable, Sendable {
    public var uid: String
    public var name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Które wejście nagrywa mikrofon: wybrane ręcznie w pigułce, a gdy go nie ma (słuchawki wyłączone w trakcie) albo nic nie wybrano,
/// domyślne wejście systemu. Wybór dotyczy tylko bieżącego nagrania (faza 2.0.2, D2/D3).
enum InputChoice {
    static func resolve(preferred: String?, available: [InputDevice], defaultUID: String?) -> String? {
        if let preferred, available.contains(where: { $0.uid == preferred }) { return preferred }
        return defaultUID
    }

    static func needsReopen(current: String?, preferred: String?, available: [InputDevice], defaultUID: String?) -> Bool {
        resolve(preferred: preferred, available: available, defaultUID: defaultUID) != current
    }
}
