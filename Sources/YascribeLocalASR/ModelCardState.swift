import Foundation
import YascribeProviders

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

    /// Nazwa karty Parakeeta (bez zmian od F20).
    public static let parakeetName = "Parakeet TDT v3"
    /// Folder modelu w magazynie (jedyny, który „Remove…" kasuje).
    public static let folder = ModelManifest.parakeetV3.model
    /// Układ FluidAudio sprzed pinu 0.17.7 — nieużywany, nietykany (decyzja Opusa 2).
    public static let legacyFolder = "parakeet-tdt-0.6b-v3-coreml"

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
    /// R12: nazwa, licencja, folder i potwierdzenia należą do modelu tej karty, nie zawsze do Parakeeta.
    public var name: String
    public var license: String?
    /// Podpis lokalizacji magazynu pod kartą.
    public var folderLabel: String
    public var removeMessage: String
    public var repairMessage: String
    /// Bramka języka w edytorze presetu (Cohere z Auto odmówi przy starcie); ustawia `role(...)`.
    public var languageWarning: String?

    public init(status: ModelStatus, activity: ModelActivity, model: LocalASRModel = .parakeetV3, manifest: ModelManifest? = nil) {
        let parakeet = model == .parakeetV3
        size = Self.sizeText((manifest ?? model.manifest).totalBytes)
        name = parakeet ? Self.parakeetName : LocalASRModels.cohereTranscribe6bitName
        meta = parakeet ? "Multilingual · \(size)" : "14 languages · \(size)"
        license = parakeet ? nil : "License: model GPL-3.0, on-device port Apache-2.0."
        folderLabel = parakeet ? "Shared FluidAudio folder" : "Yascribe folder"
        removeMessage = parakeet
            ? "Remove \(name) (\(size)) from the shared FluidAudio folder? Other apps that use FluidAudio may use this copy too."
            : "Remove \(name) (\(size)) from this Mac? Only Yascribe uses this copy. macOS frees the space used by its compiled copy on its own."
        repairMessage = parakeet
            ? "The damaged copy in the shared FluidAudio folder is deleted first, then \(size) is downloaded."
            : "The damaged copy of \(name) is deleted first, then \(size) is downloaded."
        languageWarning = nil
        note = parakeet ? nil : "Needs a fixed language. Uses about 5 GB RAM. May produce text on silence — such parts are flagged."
        primary = nil
        primaryLabel = nil
        roleWarning = nil
        switch activity {
        case .downloading(let p):
            tone = .progress(p)
            title = p.map { "Downloading \(Int(($0 * 100).rounded()))%" } ?? "Downloading…"
            description = "Downloading \(size). The app stays usable meanwhile."
        case .preparing:
            tone = .progress(nil)
            title = "Preparing…"
            description = "Preparing model… the first run on this Mac can take up to a minute."
        case .idle:
            switch status {
            case .missing:
                tone = .neutral
                title = "Not downloaded"
                description = "Transcribes speech on this Mac, with no network. Nothing is downloaded until you click Download."
                if parakeet { note = "Copies saved by older FluidAudio versions (\(Self.legacyFolder)) can't be used and are left untouched." }
                primary = .download
                primaryLabel = "Download (\(size))"
                roleWarning = "Model not downloaded"
            case .ready:
                tone = .ready
                title = "Ready"
                description = "Transcription runs on this Mac and needs no network."
                primary = .remove
                primaryLabel = "Remove…"
            case .invalid(let reason):
                tone = .warning
                title = "Needs repair"
                description = "The model files failed their check: \(reason)."
                primary = .downloadAgain
                primaryLabel = "Download again"
                roleWarning = "Model files failed the check"
            case .unknownVariant(let reason):
                tone = .warning
                title = "Different variant"
                description = "Another app stored a different variant of this model: \(reason). Yascribe leaves it untouched."
                roleWarning = "Different model variant found"
            }
        }
    }

    /// Wiersz roli ASR w edytorze presetu (N4): stan magazynu WYBRANEGO modelu; id spoza rejestru (puste, wpisane) = Parakeet jak dotąd.
    public static func role(modelID: String, language: LanguageCode?, autoLanguage: Bool,
                            status: (LocalASRModel) -> ModelStatus, activity: (LocalASRModel) -> ModelActivity) -> ModelCardState {
        let model = (try? LocalASRModel(id: modelID)) ?? .parakeetV3
        var card = ModelCardState(status: status(model), activity: activity(model), model: model)
        // Nieustawiony język to osobny błąd presetu; ostrzeżenie Cohere tylko przy Auto albo języku spoza listy.
        if language != nil || autoLanguage { card.languageWarning = RunGate.checkLanguage(model: model, language: language)?.message }
        return card
    }

    /// Dziesiętne MB/GB jak w Finderze: 483 257 242 B = „483 MB".
    public static func sizeText(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : "\(Int((Double(bytes) / 1e6).rounded())) MB"
    }
}
