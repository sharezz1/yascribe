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

/// Znak marki (pióro i słupki) jako obraz-szablon: system barwi go na jasnym i ciemnym pasku (TASK-106).
/// Źródło: docs/design/marka/zloz-pasek.py. Bez pakietu (`swift run`) zostaje dawny symbol.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let img = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: nil)!
        img.size = NSSize(width: 16 * 220 / 292, height: 16)
        img.isTemplate = true
        return img
    }()
}

/// Menu w pasku menu (faza 1.6, spec §4.8; TASK-106 bez szarych linii stanu): otwarcie okna, aktualizacje, wyjście.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    /// Wyjście w trakcie nagrywania: najpierw Stop (sesja zamknięta czysto, nie "Recovered"), po potwierdzeniu.
    /// ponytail: transkrypcja nie startuje przed wyjściem; wznawia się ręcznie po następnym uruchomieniu.
    private func quit() {
        guard model.terminationDecision() != .cancel else { return }
        NSApplication.shared.terminate(nil)
    }

    var body: some View {
        Button("Open Yascribe") { MainWindow.show(openWindow) }
        CheckForUpdatesButton(updater: model.updater)
        Button("Quit Yascribe") { quit() }
    }
}
