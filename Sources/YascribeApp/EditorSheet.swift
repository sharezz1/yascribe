import SwiftUI

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
    let leading: Leading
    let content: Content

    init(title: String, dirty: Bool, error: String?, onCancel: @escaping () -> Void, onSave: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
        self.title = title; self.dirty = dirty; self.error = error
        self.onCancel = onCancel; self.onSave = onSave
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
                Button("Cancel", action: onCancel).buttonStyle(.pill).keyboardShortcut(.cancelAction)
                Button("Save", action: onSave).buttonStyle(.pillPrimary).keyboardShortcut(.return, modifiers: .command).disabled(!dirty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
            // Drugi skrót zapisu (⌘S): przycisk ma jeden `keyboardShortcut`, więc niewidoczny bliźniak; `.hidden()` wyłączyłby skrót; ramka 0×0 zamiast `allowsHitTesting(false)`, żeby bliźniak nie łapał kliknięć, a skrót zostawał.
            .background { Button("Save", action: onSave).keyboardShortcut("s", modifiers: .command).disabled(!dirty).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
        }
        .frame(width: 560)
        .frame(minHeight: 360, idealHeight: 640)
        .background(.mnCard)
        .tint(.mnAccent) // arkusz nie dziedziczy akcentu z okna (macos.md §10, odstępstwo 5)
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
