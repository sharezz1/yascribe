import AppKit
import SwiftUI
import YascribeDictation
import YascribeProviders

final class DictationViewUI: ObservableObject {
    @Published var confirmingClear = false
    /// Wpisy rozwinięte ponad 3 linie.
    @Published var expanded: Set<UUID> = []

    func toggle(_ id: UUID) {
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }
}

/// Sekcja Dictation: stan uprawnień, skrót i historia dyktowań (tylko tekst).
struct DictationView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var ui = DictationViewUI()

    private static let inputMonitoringPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    private static let accessibilityPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    private var dictation: DictationController { model.dictation }
    private var settings: DictationSettings { model.settings.dictationOrDefault }

    var body: some View {
        ScrollPage(640) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    PageTitle("Dictation")
                    Spacer()
                    if !dictation.history.entries.isEmpty {
                        Button("Clear all…") { ui.confirmingClear = true }.buttonStyle(.pill)
                    }
                }
                .padding(.bottom, 14)
                shortcutLine
                banners
                if dictation.history.entries.isEmpty { emptyState } else { list }
            }
        }
        .contentBackground()
        .navigationTitle("Dictation")
        .onAppear { recheck() }
        // Zgodę nadaje się w Ustawieniach systemu: po powrocie sprawdzamy stan i uruchamiamy nasłuch skrótu.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
        .confirmationDialog("Clear all dictation history?", isPresented: $ui.confirmingClear) {
            Button("Clear All", role: .destructive) { dictation.clearHistory() }
        } message: {
            Text("This removes every dictation from this list. Text already inserted elsewhere is not affected.")
        }
    }

    private func recheck() {
        dictation.refreshPermissions()
        if dictation.permissions.inputMonitoring, !dictation.monitorRunning { dictation.applySettings() }
    }

    // MARK: Skrót i uprawnienia

    private var shortcutLine: some View {
        let hotkey = settings.hotkeyOrDefault
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Shortcut: \(HotkeyCapture.label(hotkey)) · \(settings.triggerModeOrDefault == .hold ? "hold to talk" : "press to toggle").")
                Button("Change in Settings") { model.section = .settings }.buttonStyle(.plain).foregroundStyle(.mnAccent)
            }
            if hotkey == .fn { Text(DictationPresentation.fnHint) }
        }
        .font(.system(size: 12)).foregroundStyle(.mnText2)
        .padding(.leading, 2).padding(.bottom, 12)
    }

    @ViewBuilder private var banners: some View {
        let p = dictation.permissions
        VStack(alignment: .leading, spacing: 8) {
            if !p.inputMonitoring {
                Banner(text: "Dictation needs Input Monitoring to hear its shortcut.") {
                    Button("Allow Input Monitoring") { dictation.requestInputMonitoring(); dictation.applySettings() }.buttonStyle(.pillSmallPrimary)
                    Button("Open System Settings") { open(Self.inputMonitoringPane) }.buttonStyle(.pillSmall)
                }
            } else if !dictation.monitorRunning {
                Banner(text: "The shortcut isn't listening. Another app may be blocking it.") {
                    Button("Try Again") { dictation.applySettings() }.buttonStyle(.pillSmall)
                }
            }
            if !p.accessibility {
                Banner(text: "Without Accessibility access, dictated text is only copied to the clipboard.") {
                    Button("Allow Accessibility") { dictation.requestAccessibility() }.buttonStyle(.pillSmallPrimary)
                    Button("Open System Settings") { open(Self.accessibilityPane) }.buttonStyle(.pillSmall)
                }
            }
            if !p.microphone {
                Banner(text: "Dictation needs microphone access.") {
                    Button("Check Permissions…") { model.showSetup = true }.buttonStyle(.pillSmall)
                }
            }
        }
        .padding(.bottom, 14)
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: Historia

    private var emptyState: some View {
        Card {
            Text(DictationPresentation.emptyHint(hotkey: settings.hotkeyOrDefault, mode: settings.triggerModeOrDefault))
                .font(.callout).foregroundStyle(.mnText2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
    }

    private var list: some View {
        let calendar = Calendar.current
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(dictation.history.days(calendar: calendar).enumerated()), id: \.offset) { _, group in
                SectionHeader(DictationDayLabel.text(for: group.day, now: now, calendar: calendar))
                Card {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { RowDivider() }
                        DictationRow(entry: entry, expanded: ui.expanded.contains(entry.id), onToggle: { ui.toggle(entry.id) })
                    }
                }
            }
        }
    }
}

private struct Banner<Actions: View>: View {
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            WarnLabel(text)
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.mnSunk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DictationRow: View {
    @Environment(AppModel.self) private var model
    let entry: DictationEntry
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.mnText2)
                .frame(width: 64, alignment: .leading).padding(.top, 2)
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.text).font(.system(size: 13)).foregroundStyle(.mnText)
                        .lineLimit(expanded ? nil : 3).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    let meta = DictationPresentation.metaLine(entry) { model.modelDisplayName($0) }
                    if !meta.isEmpty { Text(meta).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle) }
                    ForEach(DictationPresentation.notes(for: entry), id: \.self) { WarnLabel($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Collapse" : "Expand")
            MoreMenu {
                Button("Copy") { model.dictation.copy(entry) }
                if DictationPresentation.hasDistinctOriginal(entry) {
                    Button("Copy original") { var original = entry; original.text = entry.raw; model.dictation.copy(original) }
                }
                Divider()
                Button("Delete", role: .destructive) { model.dictation.deleteEntry(entry.id) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
