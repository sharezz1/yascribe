import SwiftUI

/// Wysokość karty = naturalna (ideał treści), ale nie więcej niż pole minus 48 pt (min. 240); wtedy wewnętrzny ScrollView przewija.
/// Jedna instancja treści (bez `ViewThatFits`), żeby zmiana rozmiaru okna nie zerowała stanu ani fokusu.
private struct CardHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let v = subviews.first else { return .zero }
        let ideal = v.sizeThatFits(.unspecified)
        let avail = max(240, (proposal.height ?? .infinity) - 48)
        return CGSize(width: ideal.width, height: min(ideal.height, avail))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

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
                    ZStack {
                        Color.black.opacity(0.28)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onDismiss)
                            .accessibilityHidden(true)
                        CardHeight {
                            sheet()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
                                .accessibilityAddTraits(.isModal)
                        }
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
