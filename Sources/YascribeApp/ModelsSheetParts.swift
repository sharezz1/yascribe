import SwiftUI

/// Wiersz okna wyboru modelu: etykieta po lewej (text2), kontrolka po prawej; jedna siatka dla obu okien.
struct SheetRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(.mnText2).frame(width: 78, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
    }
}

/// Sekcja okna: tytuł, wiersze, jeden podpis, akcja po prawej. Sekcje rozdziela linia.
struct SheetSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content
        }
    }
}

/// Podpis pod sekcją (jedna–dwie linie, text2).
struct SheetNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Przycisk akcji z powodem wyłączenia obok; wyrównany do prawej, jak „Save" w oknach edycji.
struct SheetAction: View {
    let title: String
    let reason: String?
    let run: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if let reason { Text(reason).font(.subheadline).foregroundStyle(.mnText2) }
            Button(title, action: run).buttonStyle(.pillPrimary).disabled(reason != nil)
        }
    }
}
