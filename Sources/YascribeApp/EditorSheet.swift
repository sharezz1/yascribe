import SwiftUI

struct FooterButton: Equatable {
    enum Role { case cancel, save, close }
    enum Shortcut { case escape, commandReturn, commandS }
    let title: String
    let role: Role
    let shortcuts: [Shortcut]
}

enum EditorSheetFooter: Equatable {
    case saveCancel, closeOnly
    case closeAction(String)

    var buttons: [FooterButton] {
        switch self {
        case .saveCancel:
            [FooterButton(title: "Cancel", role: .cancel, shortcuts: [.escape]),
             FooterButton(title: "Save", role: .save, shortcuts: [.commandReturn, .commandS])]
        case .closeOnly:
            [FooterButton(title: "Close", role: .close, shortcuts: [.escape])]
        case .closeAction(let title):
            [FooterButton(title: "Close", role: .close, shortcuts: [.escape]),
             FooterButton(title: title, role: .save, shortcuts: [])]
        }
    }
}

/// Okno edycji (faza 2.1 „okna", wzorzec `DictionaryTermSheet`): nagłówek, przewijana treść, stały pasek na dole.
/// Po lewej paska akcje `leading`, po prawej Cancel (Esc) i Save (⌘S, ⌘↩); błąd zapisu nad paskiem, nie w przewijanej treści.
/// Return celowo nie zapisuje: skrót klawiszowy wygrywa z polem wieloliniowym (instrukcje presetu i szablonu),
/// więc Return zapisałby niedokończony formularz i zamknął okno zamiast wstawić nową linię.
struct EditorSheet<Leading: View, Content: View>: View {
    let title: String
    let dirty: Bool
    let error: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    let footer: EditorSheetFooter
    let actionReason: String?
    /// `nil` = wysokość treści (okna Models są krótkie); formularze zostają przy 640, żeby długie pola miały miejsce.
    let idealHeight: CGFloat?
    let leading: Leading
    let content: Content

    init(title: String, dirty: Bool, error: String?, onCancel: @escaping () -> Void,
         footer: EditorSheetFooter = .saveCancel, actionReason: String? = nil, onSave: @escaping () -> Void = {}, idealHeight: CGFloat? = 640,
         @ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
        self.title = title; self.dirty = dirty; self.error = error
        self.onCancel = onCancel; self.onSave = onSave; self.footer = footer; self.actionReason = actionReason; self.idealHeight = idealHeight
        self.leading = leading(); self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.mnText)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 20)
            }
            if let error {
                StateLabel(.bad, error).wrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
            }
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 12)
                if let actionReason { Text(actionReason).font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true) }
                ForEach(Array(footer.buttons.enumerated()), id: \.offset) { _, button in
                    footerButton(button)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
            // Drugi skrót zapisu (⌘S): przycisk ma jeden `keyboardShortcut`, więc niewidoczny bliźniak; `.hidden()` wyłączyłby skrót; ramka 0×0 zamiast `allowsHitTesting(false)`, żeby bliźniak nie łapał kliknięć, a skrót zostawał.
            .background {
                ForEach(Array(footer.buttons.enumerated()), id: \.offset) { _, button in
                    ForEach(Array(button.shortcuts.dropFirst().enumerated()), id: \.offset) { _, shortcut in
                        shortcutButton(button, shortcut: shortcut)
                            .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(width: 560)
        .frame(minHeight: 360, idealHeight: idealHeight)
        .background(.mnCard)
        .tint(.mnAccent) // arkusz nie dziedziczy akcentu z okna (macos.md §10, odstępstwo 5)
    }

    @ViewBuilder private func footerButton(_ button: FooterButton) -> some View {
        if button.role != .save {
            shortcutButton(button, shortcut: button.shortcuts.first).buttonStyle(.pill)
        } else {
            shortcutButton(button, shortcut: button.shortcuts.first).buttonStyle(.pillPrimary)
        }
    }

    private func shortcutButton(_ button: FooterButton, shortcut: FooterButton.Shortcut?) -> some View {
        Button(button.title, action: button.role == .save ? onSave : onCancel)
            .keyboardShortcut(shortcut.map {
                switch $0 {
                case .escape: KeyboardShortcut(.escape, modifiers: [])
                case .commandReturn: KeyboardShortcut(.return, modifiers: .command)
                case .commandS: KeyboardShortcut("s", modifiers: .command)
                }
            })
            .disabled(button.role == .save && !dirty)
    }
}

extension EditorSheet where Leading == EmptyView {
    init(title: String, dirty: Bool, error: String?, onCancel: @escaping () -> Void,
         footer: EditorSheetFooter = .saveCancel, actionReason: String? = nil, onSave: @escaping () -> Void = {}, idealHeight: CGFloat? = 640,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, dirty: dirty, error: error, onCancel: onCancel, footer: footer, actionReason: actionReason, onSave: onSave,
                  idealHeight: idealHeight, leading: { EmptyView() }, content: content)
    }
}

/// Wiersz listy w karcie (jak `DictionaryRow`): nazwa 13 Medium, podpis 11 pt `text2`, `trailing` po prawej.
struct EditorListRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String, trailing: Trailing) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension EditorListRow where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle, trailing: EmptyView()) }
}
