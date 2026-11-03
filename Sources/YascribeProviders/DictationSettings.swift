import Foundation

public enum DictationTriggerMode: String, Codable, Sendable { case hold, toggle }

/// `flags` = maska `CGEventFlags.rawValue` wymaganych modyfikatorów (0 dla samego modyfikatora i dla klawisza bez modyfikatorów).
public struct DictationHotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var flags: UInt64
    public var isModifierOnly: Bool

    public init(keyCode: UInt16, flags: UInt64 = 0, isModifierOnly: Bool) {
        self.keyCode = keyCode
        self.flags = flags
        self.isModifierOnly = isModifierOnly
    }

    public static let fn = DictationHotkey(keyCode: 63, isModifierOnly: true)
}

public struct DictationCorrectionSettings: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var model: RoleAssignment?

    public init(enabled: Bool? = nil, model: RoleAssignment? = nil) {
        self.enabled = enabled
        self.model = model
    }
}

/// Wszystkie pola opcjonalne (E6): stary `settings.json` ich nie ma. Czytaj przez właściwości `…OrDefault`.
public struct DictationSettings: Codable, Equatable, Sendable {
    public var hotkey: DictationHotkey?
    public var triggerMode: DictationTriggerMode?
    public var asr: RoleAssignment?
    /// Jawny język dyktowania; `nil` = język aktywnego presetu, a gdy go brak — odmowa. Nigdy Auto.
    public var language: LanguageCode?
    public var correction: DictationCorrectionSettings?
    public var showLauncher: Bool?
    public var launcherOriginX: Double?

    public init(hotkey: DictationHotkey? = nil, triggerMode: DictationTriggerMode? = nil, asr: RoleAssignment? = nil,
                language: LanguageCode? = nil, correction: DictationCorrectionSettings? = nil,
                showLauncher: Bool? = nil, launcherOriginX: Double? = nil) {
        self.hotkey = hotkey
        self.triggerMode = triggerMode
        self.asr = asr
        self.language = language
        self.correction = correction
        self.showLauncher = showLauncher
        self.launcherOriginX = launcherOriginX
    }

    public var hotkeyOrDefault: DictationHotkey { hotkey ?? .fn }
    public var triggerModeOrDefault: DictationTriggerMode { triggerMode ?? .hold }
    public var correctionEnabled: Bool { correction?.enabled ?? false }
    public var showLauncherOrDefault: Bool { showLauncher ?? true }
}
