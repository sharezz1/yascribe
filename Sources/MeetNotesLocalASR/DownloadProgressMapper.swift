import Foundation

/// Zamienia surowe zdarzenia postępu FluidAudio 0.17.7 na pasek monotoniczny (F20 S0 §7.3): `fractionCompleted`
/// spada 3x przy kompilacji, a „pobrane" kończy się na 0,5. Bez typów FluidAudio w sygnaturze — testowalne bez sieci.
/// `nil` = postęp nieokreślony („Preparing model…"); nie zeruje paska.
public struct DownloadProgressMapper: Sendable {
    public enum Phase: Equatable, Sendable {
        case listing
        case downloading(fraction: Double)
        case compiling
    }

    private var highest = 0.0

    public init() {}

    public mutating func map(_ phase: Phase) -> Double? {
        switch phase {
        case .listing, .compiling:
            return nil
        case .downloading(let fraction):
            // ponytail: skala 0,5 to zachowanie FluidAudio 0.17.7 (S0 §7.3) — przy zmianie upstreamu pasek będzie nieładny, nie niemonotoniczny.
            highest = max(highest, min(1, fraction / 0.5))
            return highest
        }
    }
}
