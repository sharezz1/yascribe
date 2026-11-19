import Foundation

/// Co aplikacja robi z modelem w tej chwili (pobieranie, pierwsze ładowanie). Trzyma ją `LocalASRSupport` (T6).
public enum ModelActivity: Equatable, Sendable {
    case idle
    /// `nil` = postęp nieokreślony; wartość nie maleje w trakcie jednego pobrania.
    case downloading(Double?)
    /// Pierwsze ładowanie modelu przy starcie przebiegu (kompilacja ANE).
    case preparing
}

/// Karta modelu w Settings i ostrzeżenie w edytorze presetu (F20 T7): z pary (status magazynu, aktywność) wynikają teksty
/// i jedyna akcja główna. Czysta funkcja — aplikacja nie ma testów, więc cała logika stanu jest tu. Teksty po angielsku (UI).
public struct ModelCardState: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case download
        /// Naprawa uszkodzonej kopii: `ModelStore.download(force:)` kasuje folder modelu, więc UI pyta o zgodę.
        case downloadAgain
        case remove

        public var needsConfirmation: Bool { self != .download }
    }

    public enum Tone: Equatable, Sendable {
        case ready, neutral, warning
        /// `nil` = nieokreślony.
        case progress(Double?)
    }

    /// Układ FluidAudio sprzed pinu 0.17.7 (tylko v3) — nieużywany, nietykany (decyzja Opusa 2).
    public static let legacyFolder = "parakeet-tdt-0.6b-v3-coreml"

    public var name: String
    /// Folder modelu w magazynie (jedyny, który „Remove…" kasuje).
    public var folder: String
    public var meta: String
    public var title: String
    public var tone: Tone
    public var description: String
    public var note: String?
    public var primary: Action?
    public var primaryLabel: String?
    /// Linia ostrzeżenia w edytorze presetu; `nil` = model gotowy (albo trwa pobieranie).
    public var roleWarning: String?
    /// Rozmiar pobrania z manifestu, np. „483 MB".
    public var size: String

    public init(status: ModelStatus, activity: ModelActivity, variant: LocalASRVariant = .parakeetV3) {
        name = variant.displayName
        folder = variant.manifest.model
        size = Self.sizeText(variant.manifest.totalBytes)
        meta = String(localized: "Multilingual · \(size)")
        note = nil
        primary = nil
        primaryLabel = nil
        roleWarning = nil
        switch activity {
        case .downloading(let p):
            tone = .progress(p)
            title = p.map { String(localized: "Downloading \(Int(($0 * 100).rounded()))%") } ?? String(localized: "Downloading…")
            description = String(localized: "Downloading \(size). The app stays usable meanwhile.")
        case .preparing:
            tone = .progress(nil)
            title = String(localized: "Preparing…")
            description = String(localized: "Preparing model… the first run on this Mac can take up to a minute.")
        case .idle:
            switch status {
            case .missing:
                tone = .neutral
                title = String(localized: "Not downloaded")
                description = String(localized: "Transcribes speech on this Mac, with no network. Nothing is downloaded until you click Download.")
                if variant == .parakeetV3 {
                    note = String(localized: "Copies saved by older FluidAudio versions (\(Self.legacyFolder)) can't be used and are left untouched.")
                }
                primary = .download
                primaryLabel = String(localized: "Download (\(size))")
                roleWarning = String(localized: "Model not downloaded")
            case .ready:
                tone = .ready
                title = String(localized: "Ready")
                description = String(localized: "Transcription runs on this Mac and needs no network.")
                primary = .remove
                primaryLabel = String(localized: "Remove…")
            case .invalid(let reason):
                tone = .warning
                title = String(localized: "Needs repair")
                description = String(localized: "The model files failed their check: \(ModelStatus.displayReason(reason)).")
                primary = .downloadAgain
                primaryLabel = String(localized: "Download again")
                roleWarning = String(localized: "Model files failed the check")
            case .unknownVariant(let reason):
                tone = .warning
                title = String(localized: "Different variant")
                description = String(localized: "Another app stored a different variant of this model: \(ModelStatus.displayReason(reason)). Yascribe leaves it untouched.")
                roleWarning = String(localized: "Different model variant found")
            }
        }
    }

    /// Dziesiętne MB/GB jak w Finderze: 483 257 242 B = „483 MB".
    public static func sizeText(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : "\(Int((Double(bytes) / 1e6).rounded())) MB"
    }
}
