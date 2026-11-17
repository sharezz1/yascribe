public enum SpeakerSensitivity: String, Codable, Sendable, CaseIterable {
    case low, medium, high

    public var fa: Double {
        switch self { case .low: 0.07; case .medium: 0.15; case .high: 0.30 }
    }
    public var fb: Double {
        switch self { case .low, .high: 0.8; case .medium: 0.4 }
    }
    public static let defaultValue: SpeakerSensitivity = .medium
}
