import YascribeMeetings
import SwiftUI

/// Stany pigułki bez nagrywania (faza 1.6, spec §4.4). Stały rozmiar treści, szkło i rogi jak rozwinięta pigułka nagrania.
/// Okno nie jest oknem klucza (`orderFrontRegardless`), więc nic nie ma fokusu; Tab wchodzi do przycisków.
/// Stan niesie tekst i ikona, nie sam kolor; bez animacji, więc Reduce Motion nic tu nie zmienia.
struct PillOfferView: View {
    let offer: Offer
    @ObservedObject var pill: PillState
    @Environment(AppModel.self) private var model

    private var kind: (icon: String, label: String) {
        switch offer.source {
        case .calendar: ("calendar", "Calendar")
        case .call: ("phone", "Call")
        case .calendarAndCall: ("calendar", "Calendar + call")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.icon).font(.system(size: 14)).foregroundStyle(.mnText2).frame(width: 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.title).font(.callout.weight(.semibold)).foregroundStyle(.mnText).lineLimit(2)
                    Text(kind.label).font(.callout).foregroundStyle(.mnText2).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            // Język spotkania jest jawny (W§): wybór presetu w ofercie to ten sam `activePresetID` co na stronie Meetings.
            FieldMenu(label: "Preset", value: model.activePreset.map(AppModel.label) ?? "No preset", prefix: "Preset", width: 292) {
                ForEach(model.presets.presets) { p in
                    Button(AppModel.label(p)) { model.activePresetID = p.id }
                }
            }
            HStack(spacing: 8) {
                Button { pill.onSecondary() } label: { Text("Not a meeting").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(kind: .secondary, large: true))
                Button { pill.onPrimary() } label: { Text("Start").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(kind: .primary, large: true))
            }
        }
        .padding(14).frame(width: 320).pillGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PillEndPromptView: View {
    @ObservedObject var pill: PillState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle").font(.system(size: 14)).foregroundStyle(.mnText2).frame(width: 18).accessibilityHidden(true)
                Text("Meeting ended?").font(.callout.weight(.semibold)).foregroundStyle(.mnText).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { pill.onSecondary() } label: { Text("Continue").frame(maxWidth: .infinity) }.buttonStyle(PillButtonStyle(kind: .secondary, large: true))
                Button("Stop") { pill.onPrimary() }.buttonStyle(StopButtonStyle(fill: true)).keyboardShortcut(".", modifiers: .command)
            }
        }
        .padding(14).frame(width: 320).pillGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
