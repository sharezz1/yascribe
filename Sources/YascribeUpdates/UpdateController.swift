import Foundation
import Sparkle

/// Cienka warstwa na `SPUStandardUpdaterController`: callbacki delegata trafiają do `RestartGate`.
/// Kolejność callbacków (spike S0): `userDidMake(.install)` → … → `shouldPostponeRelaunch` → `willInstallUpdate` → restart.
@MainActor
public final class UpdateController: ObservableObject {
    private let delegate: Delegate
    private let controller: SPUStandardUpdaterController

    /// `start: false` (uruchomienia deweloperskie, migawki): Sparkle nie startuje i nie sprawdza aktualizacji.
    public init(gate: RestartGate, start: Bool = true) {
        let d = Delegate(gate: gate)
        delegate = d
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: d, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    /// Odzwierciedla `SPUUpdater.canCheckForUpdates` (KVO), żeby przycisk w menu i Settings wygasał w trakcie sprawdzania.
    @Published public private(set) var canCheck = false
    private var observation: NSKeyValueObservation?

    public func checkForUpdates() { controller.checkForUpdates(nil) }

    /// „0.1.0 (12)" z `CFBundleShortVersionString` i `CFBundleVersion`.
    public var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private final class Delegate: NSObject, SPUUpdaterDelegate {
        let gate: RestartGate
        init(gate: RestartGate) { self.gate = gate }

        func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                     untilInvokingBlock installHandler: @escaping @Sendable () -> Void) -> Bool {
            MainActor.assumeIsolated { gate.shouldPostpone { installHandler() } }
        }

        func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem,
                     state: SPUUserUpdateState) {
            guard choice == .install else { return }
            MainActor.assumeIsolated { gate.installationStarted() }
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            MainActor.assumeIsolated { gate.installationEnded() }
        }

        func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
            MainActor.assumeIsolated { gate.installationEnded() }
        }
    }
}
