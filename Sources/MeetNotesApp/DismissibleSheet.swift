import SwiftUI

/// Okno modalne w oknie aplikacji zamiast `.sheet`: natywny arkusz macOS nie zamyka się po kliknięciu poza nim,
/// a tu kliknięcie w przyciemnione tło woła `onDismiss` (u wywołującego = to samo co Cancel, bez zapisu).
private struct DismissibleSheet<Sheet: View>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPresented: Bool
    let onDismiss: () -> Void
    let sheet: () -> Sheet

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPresented)
            .disabled(isPresented) // blokuje też klawiaturę i fokus pod przyciemnieniem
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    GeometryReader { geo in
                        ZStack {
                            Color.black.opacity(0.28)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onDismiss)
                                .accessibilityHidden(true)
                            sheet()
                                .frame(maxHeight: max(240, geo.size.height - 48))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
                                .accessibilityAddTraits(.isModal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isPresented)
    }
}

extension View {
    func dismissibleSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: @escaping () -> Void,
                                         @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(DismissibleSheet(isPresented: isPresented.wrappedValue, onDismiss: onDismiss, sheet: content))
    }
}
