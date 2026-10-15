import AppKit
import SwiftUI

// Język wizualny B (docs/design/macos.md §11): tokeny kolorów, typografia i komponenty wspólne.
// Tylko obszar treści — sidebar, ramka okna, `Toggle`, `Picker`, pola i popovery zostają systemowe.
// Bez makr (CLAUDE.md): stan najechania w `ObservableObject` pod `@StateObject`.

// MARK: - Kolory (§11.1)

/// Kolor dynamiczny w kodzie: `Assets.xcassets` odpada, bo kompiluje go `actool` z Xcode.
/// Increase Contrast (📐 §11.1): `text2` i obwódki dostają ciemniejszy wariant (`hc…`).
private func dynamic(_ light: NSColor, _ dark: NSColor, hcLight: NSColor? = nil, hcDark: NSColor? = nil) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
        case .darkAqua?: dark
        case .accessibilityHighContrastDarkAqua?: hcDark ?? dark
        case .accessibilityHighContrastAqua?: hcLight ?? light
        default: light
        }
    })
}

private func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

extension ShapeStyle where Self == Color {
    static var mnBackground: Color { dynamic(hex(0xF7F6F2), hex(0x1C1C1B)) }
    static var mnCard: Color { dynamic(hex(0xFFFFFF), hex(0x262624)) }
    /// Pole tekstowe i popup: w ciemnym ciemniejsze od karty (`#2E2E2C`), w jasnym jak karta.
    static var mnField: Color { dynamic(hex(0xFFFFFF), hex(0x2E2E2C)) }
    static var mnSunk: Color { dynamic(hex(0xF1EFE9), hex(0x2E2E2C)) }
    static var mnSelection: Color { dynamic(hex(0x3C3214, 0.08), hex(0xFFFFFF, 0.08)) }
    static var mnLine: Color { dynamic(hex(0x3C3214, 0.14), hex(0xFFFFFF, 0.11), hcLight: hex(0x3C3214, 0.45), hcDark: hex(0xFFFFFF, 0.4)) }
    static var mnLine2: Color { dynamic(hex(0x3C3214, 0.08), hex(0xFFFFFF, 0.06), hcLight: hex(0x3C3214, 0.3), hcDark: hex(0xFFFFFF, 0.3)) }
    static var mnText: Color { dynamic(hex(0x22211E), hex(0xECEBE6)) }
    static var mnText2: Color { dynamic(hex(0x666259), hex(0x9A978F), hcLight: hex(0x4A463F), hcDark: hex(0xC4C1B9)) }
    /// Tylko kontrolki nieaktywne (2,3–3,1:1). Placeholdery mają kolor systemowy.
    static var mnText3: Color { dynamic(hex(0xA8A49A), hex(0x6B6963)) }
    static var mnPrimary: Color { dynamic(hex(0x22211E), hex(0xECEBE6)) }
    static var mnOnPrimary: Color { dynamic(hex(0xFFFFFF), hex(0x1C1C1B)) }
    static var mnAccent: Color { dynamic(hex(0x2F6B4F), hex(0x7CC39C)) }
    static var mnRec: Color { dynamic(hex(0xC4271C), hex(0xFF6B5E)) }
    static var mnWarn: Color { dynamic(hex(0x8A5A00), hex(0xE0B050)) }
    /// Kropka nagrywania: stała systemRed, poza paletą.
    static var mnRecDot: Color { Color(nsColor: hex(0xFF3B30)) }
}

// MARK: - Typografia i układ (§11.2, §11.3)

/// Tytuł strony (Meetings, Presets, Settings): New York 30, jedyne miejsce szeryfu obok tytułu spotkania.
struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 30, design: .serif)).tracking(-0.3).foregroundStyle(.mnText)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Tytuł spotkania (New York 28) — działa na `Text` i na edytowalnym `TextField`.
    func documentTitle() -> some View {
        font(.system(size: 28, design: .serif)).tracking(-0.3).foregroundStyle(.mnText)
    }

    /// Kolumna treści wyśrodkowana w obszarze szczegółów (580 lista, 640 spotkanie/Settings, 700 Presets) na tle `mnBackground`.
    /// Górny margines 24 zamiast 54 z makiety: okno ma pasek tytułu, makieta go nie ma.
    func contentColumn(_ width: CGFloat) -> some View {
        frame(maxWidth: width, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Tło obszaru treści (sidebar zostaje systemowy).
    func contentBackground() -> some View {
        background(Color.mnBackground.ignoresSafeArea())
    }
}

/// Nagłówek sekcji / karty: SF 13 Semibold, opcjonalny dopisek („— optional”) i kontrolka po prawej.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var note: String?
    var trailing: Trailing

    init(_ title: String, note: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.note = note; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
                + Text(note.map { "  \($0)" } ?? "").font(.system(size: 13)).foregroundStyle(.mnText2)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 2)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, note: String? = nil) { self.init(title, note: note) { EmptyView() } }
}

/// Karta: `card` + obwódka 0,5 pt + promień 12, bez cienia. Wiersze rozdziela `RowDivider`.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(.mnCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Separator wierszy w karcie (`line2`, wcięty 16 pt).
struct RowDivider: View {
    var inset: CGFloat = 16
    var body: some View { Rectangle().fill(.mnLine2).frame(height: 0.5).padding(.horizontal, inset) }
}

/// Wiersz formularza: etykieta 130 pt (`text2`) + kontrolka; pod kontrolką opcjonalny podpis 11 pt (`rec` przy błędzie).
struct FormRow<Content: View>: View {
    let label: String
    var caption: String?
    var isError = false
    var labelWidth: CGFloat = 130
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.mnText2).frame(width: labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                if let caption {
                    Text(caption).font(.subheadline).foregroundStyle(isError ? .mnRec : .mnText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }
}

/// Jedna linia metadanych: „Oct 15, 11:29 · 42 min · Preset Polish”.
struct MetaLine: View {
    let parts: [String]
    init(_ parts: [String]) { self.parts = parts }
    var body: some View {
        Text(parts.filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.callout).monospacedDigit().foregroundStyle(.mnText2).lineLimit(1)
    }
}

// MARK: - Stany (§11.4): zawsze ikona + słowo, nigdy sam kolor

struct StateLabel: View {
    enum Kind: Equatable { case ok, bad, live, neutral, progress(Double?) }
    let kind: Kind
    let text: String
    init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }

    var body: some View {
        HStack(spacing: 4) {
            switch kind {
            case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            case .bad: Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            case .live: Circle().fill(.mnRecDot).frame(width: 8, height: 8).accessibilityHidden(true)
            case .neutral: EmptyView()
            case .progress(let f?):
                ZStack(alignment: .leading) {
                    Capsule().fill(.mnLine)
                    Capsule().fill(.mnText2).frame(width: 38 * min(max(f, 0), 1))
                }
                .frame(width: 38, height: 4)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
            case .progress(nil): ProgressView().controlSize(.mini)
            }
            Text(text).fontWeight(kind == .live ? .semibold : .regular).monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch kind {
        case .ok: .mnAccent
        case .bad, .live: .mnRec
        case .neutral, .progress: .mnText2
        }
    }
}

/// Ostrzeżenie (np. język Auto, „Recovered”): trójkąt + słowa w `warn`; zawija długie zdania.
struct WarnLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 10, weight: .bold))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.mnWarn)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Popupy jak pole (D8, §11.4 `FieldMenuStyle`)

/// Popup wyglądający jak pole: `field`, obwódka 0,5, promień 7, mały ⌄. Pod spodem standardowe `Menu`;
/// wybór z listy to `Picker(...).pickerStyle(.inline)` w treści menu (zaznaczenie ✓ robi system).
struct FieldMenu<Content: View>: View {
    /// Nazwa dla VoiceOver („Language”).
    let label: String
    /// Bieżąca wartość widoczna w polu.
    let value: String
    /// Dopisek przed wartością w `text2` (jak dostawca w `ModelField`).
    var prefix: String?
    var width: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            HStack(spacing: 6) {
                if let prefix { Text("\(prefix)  ·").foregroundStyle(.mnText2).fixedSize() }
                Text(value).foregroundStyle(.mnText).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.mnText2)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(minWidth: width, maxWidth: width, minHeight: 28, maxHeight: 28)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Przyciski-pigułki (§11.4, odstępstwo 7: pigułka nigdy nie jest przełącznikiem)

final class HoverState: ObservableObject {
    @Published var hovering = false
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, small }
    var kind: Kind = .secondary
    /// Większa pigułka (32 pt) dla Record na karcie.
    var large = false
    /// Mały primary (24 pt): tylko „Save & verify” w formularzu dostawcy (D4).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, large: large, small: kind == .small || compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let large: Bool
        let small: Bool
        @StateObject private var hover = HoverState()
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        private var height: CGFloat { small ? 24 : large ? 32 : 28 }

        var body: some View {
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, small ? 10 : large ? 16 : 13)
                .frame(height: height)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5).opacity(kind == .primary && isEnabled ? 0 : 1))
                // Fokus z klawiatury: własny pierścień w kolorze systemowym (własny ButtonStyle nie zawsze dostaje systemowy).
                .overlay(Capsule().inset(by: -3).strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3).opacity(isFocused ? 1 : 0))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Capsule())
                .onHover { hover.hovering = $0 }
        }

        private var foreground: Color {
            guard isEnabled else { return .mnText3 }
            return kind == .primary ? .mnOnPrimary : .mnText
        }

        private var background: Color {
            if kind == .primary { return isEnabled ? .mnPrimary : .mnSunk }
            return hover.hovering && isEnabled ? .mnSunk : .mnCard
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pill: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillSmall: PillButtonStyle { PillButtonStyle(kind: .small) }
    static var pillSmallPrimary: PillButtonStyle { PillButtonStyle(kind: .primary, compact: true) }
}
