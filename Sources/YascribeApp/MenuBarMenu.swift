import AppKit
import YascribeMeetings
import SwiftUI

/// Wyciąga okno główne na wierzch albo otwiera je na nowo, gdy użytkownik je zamknął (aplikacja żyje bez okna).
@MainActor
enum MainWindow {
    static func show(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        if let w = NSApp.windows.first(where: { !($0 is NSPanel) && !$0.isSheet && ($0.canBecomeMain || $0.isMiniaturized) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless() // gdyby system odmówił aktywacji (Teams na pierwszym planie) — okno i tak na wierzch
        } else {
            openWindow(id: "main")
        }
    }
}

/// Menu w pasku menu (faza 1.6, spec §4.8): stan wykrywania, otwarcie okna, wyjście (które wyłącza wykrywanie).
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var status: String {
        let m = model.settings.meetings
        let problem: DetectionStatus.CalendarProblem? = switch model.monitor.state {
        case .calendarDenied: .denied
        case .calendarSelectionStale: .selectionStale
        default: nil
        }
        return model.monitor.state == .off
            ? "Detection off"
            : DetectionStatus.text(calls: m?.detectCallsOrDefault ?? true, calendar: m?.appleCalendarOrDefault ?? false, problem: problem)
    }

    /// Wyjście w trakcie nagrywania: najpierw Stop (sesja zamknięta czysto, nie "Recovered"), po potwierdzeniu.
    /// ponytail: transkrypcja nie startuje przed wyjściem; wznawia się ręcznie po następnym uruchomieniu.
    private func quit() {
        guard model.terminationDecision() != .cancel else { return }
        NSApplication.shared.terminate(nil)
    }

    var body: some View {
        Text(status)
        Divider()
        Button("Open Yascribe") { MainWindow.show(openWindow) }
        Button("Quit Yascribe") { quit() }
        Text("Quitting turns off detection")
    }
}
