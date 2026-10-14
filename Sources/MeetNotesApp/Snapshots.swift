import AppKit
import MeetNotesProviders
import SwiftUI

/// Tryb migawek (macos.md §9): `MEETNOTES_SNAPSHOT_DIR=<katalog>` renderuje ekrany do PNG i kończy proces.
/// Dowód w raporcie: „migawka" (ten plik), nie „zrzut na żywo".
enum SnapshotError: Error { case noBitmap, noPNG }

@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MEETNOTES_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    static func render<V: View>(_ name: String, size: CGSize, dark: Bool, model: AppModel,
                                @ViewBuilder _ content: () -> V) throws {
        let host = NSHostingView(rootView: content().environment(model).frame(width: size.width, height: size.height)
            // Spike T0: bez tła okna PNG ma przezroczyste tło — w ciemnym trybie jasny tekst znika na białym podglądzie.
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        // Spike T0: `.titled` + `.toolbar` w widoku dokłada ~28 pt pasa u góry; `.borderless` daje dokładny rozmiar (bez paska narzędzi).
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.noBitmap }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noPNG }
        // `directory!` jest bezpieczne: `render` woła tylko `runAll`, a `runAll` startuje z `init()` dopiero po sprawdzeniu
        // `directory != nil`. Wywołanie `render` z innego miejsca wymaga guarda.
        try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        try png.write(to: directory!.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    /// Fixture: presety i dostawca zapisane do katalogu danych, potem `load()`. Kolejne zadania dopisują sesje i stany.
    static func seed(_ model: AppModel) throws {
        let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        var presets = PresetsFile()
        try presets.upsert(Preset(name: "Polish", language: .polish,
                                  asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2")))
        try JSONFile.save(ProvidersFile(providers: [provider]), to: model.paths.providers)
        try JSONFile.save(presets, to: model.paths.presets)
        model.load()
        model.showSetup = false
    }

    static func runAll(model: AppModel) {
        do {
            try seed(model)
            for dark in [false, true] {
                try render("presets", size: CGSize(width: 900, height: 600), dark: dark, model: model) { PresetsView() }
                try render("meetings", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView() }
                // Pola tekstowe: PresetsView bez wyboru pokazuje tylko „Choose a preset" (wybór jest lokalny w widoku).
                let form = PresetEditorState()
                form.draft = model.presets.presets.first
                try render("preset-form", size: CGSize(width: 700, height: 600), dark: dark, model: model) { PresetForm(state: form) }
            }
            print("snapshots: \(directory!.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshots: \(error)\n".utf8))
            exit(1)
        }
    }
}
