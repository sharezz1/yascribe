import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes

private let p = UUID()
private let q = UUID()

@Test func oldMetaWithoutOverridesStillDecodes() throws {
    let meta = try JSONDecoder().decode(NoteMeta.self, from: Data(#"{"manualTitle":"A"}"#.utf8))
    #expect(meta.manualTitle == "A")
    #expect(meta.modelOverrides == nil)
}

@Test func overridesRoundTripThroughMetaJSON() throws {
    var meta = NoteMeta()
    meta.setOverride(.summary, RoleOverride(providerID: p, model: "m", thinking: false))
    let back = try JSONDecoder().decode(NoteMeta.self, from: JSONEncoder().encode(meta))
    #expect(back.modelOverrides?.summary == RoleOverride(providerID: p, model: "m", thinking: false))
    #expect(back.modelOverrides?.correction == nil)
}

@Test func usableDropsEmptyModelAndUnknownProvider() {
    let o = ModelOverrides(summary: RoleOverride(providerID: p, model: "m"), correction: RoleOverride(providerID: p, model: "  "))
    #expect(o.usable(.summary, knownProviders: [p])?.model == "m")
    #expect(o.usable(.summary, knownProviders: [q]) == nil)
    #expect(o.usable(.correction, knownProviders: [p]) == nil)
    #expect(o.usable(.asr, knownProviders: [p]) == nil)
    #expect(o.raw(.summary) == RoleOverride(providerID: p, model: "m"))
}

@Test func resettingOneRoleKeepsTheOtherAndResettingBothClearsTheField() {
    let x = RoleOverride(providerID: p, model: "x")
    let y = RoleOverride(providerID: q, model: "y")
    var meta = NoteMeta()
    meta.setOverride(.summary, x)
    meta.setOverride(.correction, y)
    meta.setOverride(.summary, nil)
    #expect(meta.modelOverrides?.correction == y)
    #expect(meta.modelOverrides?.summary == nil)
    meta.setOverride(.correction, nil)
    #expect(meta.modelOverrides == nil)
}

@Test func correctionOverrideWinsAndKeepsThePresetPrompt() {
    let preset = Preset(name: "P", language: .polish, asr: RoleAssignment(providerID: p, model: "a"),
                        correction: RoleAssignment(providerID: p, model: "old", prompt: "P"))
    let r = CorrectionModel.resolve(frozen: preset, override: RoleOverride(providerID: q, model: "new"))
    #expect(r == RoleAssignment(providerID: q, model: "new", prompt: "P"))
    #expect(CorrectionModel.resolve(frozen: preset, override: nil) == preset.correction)
}

@Test func correctionOverrideWorksWhenPresetHasNoCorrection() {
    let preset = Preset(name: "P", language: .polish, asr: RoleAssignment(providerID: p, model: "a"))
    let r = CorrectionModel.resolve(frozen: preset, override: RoleOverride(providerID: q, model: "new"))
    #expect(r == RoleAssignment(providerID: q, model: "new", prompt: nil))
    #expect(CorrectionModel.resolve(frozen: preset, override: nil) == nil)
}

@Test func staleMeansSavedButNotUsable() {
    let o = ModelOverrides(summary: RoleOverride(providerID: p, model: "m"))
    #expect(o.isStale(.summary, knownProviders: [q]))
    #expect(!o.isStale(.summary, knownProviders: [p]))
    #expect(!o.isStale(.correction, knownProviders: [q]))
}
