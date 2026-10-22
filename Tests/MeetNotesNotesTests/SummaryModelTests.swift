import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes

private let prov = RoleAssignment(providerID: UUID(), model: "m")
private func preset(_ name: String, summary: String?) -> Preset {
    Preset(name: name, language: .polish, asr: prov, summary: summary.map { RoleAssignment(providerID: prov.providerID, model: $0) })
}

@Test func frozenPresetSummaryWinsAndIsNotLabelledAsFallback() {
    let frozen = preset("Polski", summary: "own-model")
    let other = preset("Default", summary: "default-model")
    let c = SummaryModel.resolve(frozen: frozen, defaultPresetID: other.id, presets: [frozen, other])
    #expect(c?.assignment.model == "own-model")
    #expect(c?.isFallback == false)
    #expect(c?.label == nil)
}

@Test func defaultPresetSummaryIsUsedWhenTheFrozenOneHasNone() {
    let frozen = preset("English", summary: nil)
    let other = preset("Polski", summary: "default-model")
    let c = SummaryModel.resolve(frozen: frozen, defaultPresetID: other.id, presets: [frozen, other])
    #expect(c?.assignment.model == "default-model")
    #expect(c?.label == "Using default-model from preset Polski")
}

@Test func anyPresetWithASummaryIsTheLastResortAndNoneMeansNoNotes() {
    let frozen = preset("English", summary: nil)
    let noSummary = preset("Default", summary: nil)
    let third = preset("Third", summary: "third-model")
    #expect(SummaryModel.resolve(frozen: frozen, defaultPresetID: noSummary.id, presets: [frozen, noSummary, third])?.assignment.model == "third-model")
    #expect(SummaryModel.resolve(frozen: frozen, defaultPresetID: noSummary.id, presets: [frozen, noSummary]) == nil)
    #expect(SummaryModel.resolve(frozen: preset("Blank", summary: "  "), defaultPresetID: nil, presets: []) == nil) // pusty model to brak modelu
}

@Test func overrideWinsOverFrozenPresetAndCarriesThinking() {
    let frozen = preset("Polski", summary: "own-model")
    let o = RoleOverride(providerID: UUID(), model: "picked", thinking: false)
    let c = SummaryModel.resolve(frozen: frozen, override: o, defaultPresetID: nil, presets: [frozen])
    #expect(c?.isOverride == true)
    #expect(c?.assignment.model == "picked")
    #expect(c?.assignment.providerID == o.providerID)
    #expect(c?.thinking == false)
    #expect(c?.presetName == "Polski")
    #expect(c?.label == nil)
}

@Test func overrideWorksWhenNoPresetHasASummary() {
    let o = RoleOverride(providerID: UUID(), model: "picked")
    let c = SummaryModel.resolve(frozen: nil, override: o, defaultPresetID: nil, presets: [])
    #expect(c?.assignment.model == "picked")
    #expect(c?.presetName == "")
    #expect(c?.thinking == nil)
}

@Test func noOverrideKeepsTheOldResult() {
    let frozen = preset("Polski", summary: "own-model")
    let c = SummaryModel.resolve(frozen: frozen, override: nil, defaultPresetID: nil, presets: [frozen])
    #expect(c?.assignment.model == "own-model")
    #expect(c?.isOverride == false)
    #expect(c?.thinking == nil)
}
