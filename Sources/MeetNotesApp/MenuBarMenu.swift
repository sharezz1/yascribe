import AppKit
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
        switch model.monitor.state {
        case .off: "Detection off"
        case .watching: "Detecting meetings"
        case .calendarDenied: "Detecting calls (calendar access off)"
        case .calendarSelectionStale: "Selected calendars not found — re-select in Settings"
        }
    }

    var body: some View {
        Text(status)
        Divider()
        Button("Open MeetNotes") { MainWindow.show(openWindow) }
        Button("Quit MeetNotes") { NSApplication.shared.terminate(nil) }
        Text("Quitting turns off detection")
    }
}
