import Foundation
import Testing
@testable import YascribeProviders

private let asr = RoleAssignment(providerID: UUID(), model: "m")

private func validPreset(_ name: String = "Preset", language: LanguageCode? = .polish,
                         rules: PresetRules? = nil) -> Preset {
    Preset(name: name, language: language, asr: asr, rules: rules)
}

@Test func presetJSONWithoutRulesDecodesWithNilRules() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-0000000000AB","name":"Standup","language":"pl",
     "asr":{"providerID":"00000000-0000-0000-0000-000000000001","model":"m"}}
    """
    let p = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
    #expect(p.rules == nil)
    try p.validate()
}

@Test func presetWithRulesRoundTripsThroughJSON() throws {
    let rules = PresetRules(titleContains: ["Standup"], attendeeDomains: ["example.test"], apps: ["com.example.call"])
    let p = validPreset(rules: rules)
    let back = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(p))
    #expect(back == p)
    #expect(back.rules == rules)
}

@Test func titleMatchIgnoresCaseAndDiacritics() {
    let byCase = validPreset(rules: PresetRules(titleContains: ["spotkanie"]))
    let r1 = PresetRuleMatcher.match(presets: [byCase], title: "SPOTKANIE zespołu",
                                     attendeeEmails: [], app: nil)
    #expect(r1?.presetID == byCase.id)
    #expect(r1?.reason == .title("spotkanie"))

    let byDiacritics = validPreset(rules: PresetRules(titleContains: ["zolc"]))
    let r2 = PresetRuleMatcher.match(presets: [byDiacritics], title: "Żółć", attendeeEmails: [], app: nil)
    #expect(r2?.reason == .title("zolc"))
}

@Test func blankTitleFragmentIsIgnored() {
    let p = validPreset(rules: PresetRules(titleContains: ["   "]))
    #expect(PresetRuleMatcher.match(presets: [p], title: "cokolwiek", attendeeEmails: [], app: nil) == nil)
}

@Test func domainMatchesExactlyAndOnSubdomain() {
    let exact = validPreset(rules: PresetRules(attendeeDomains: ["example.test"]))
    #expect(PresetRuleMatcher.match(presets: [exact], title: nil,
                                    attendeeEmails: ["anna@example.test"], app: nil)?.reason == .domain("example.test"))

    let sub = validPreset(rules: PresetRules(attendeeDomains: ["example.test"]))
    #expect(PresetRuleMatcher.match(presets: [sub], title: nil,
                                    attendeeEmails: ["anna@x.example.test"], app: nil)?.reason == .domain("example.test"))

    // Granica kropki: `xexample.test` to inna domena.
    let near = validPreset(rules: PresetRules(attendeeDomains: ["example.test"]))
    #expect(PresetRuleMatcher.match(presets: [near], title: nil,
                                    attendeeEmails: ["anna@xexample.test"], app: nil) == nil)
}

@Test func domainRuleAcceptsAtSignAndCase() {
    let p = validPreset(rules: PresetRules(attendeeDomains: ["@Example.Test"]))
    let match = PresetRuleMatcher.match(presets: [p], title: nil,
                                        attendeeEmails: ["anna@EXAMPLE.TEST"], app: nil)
    #expect(match?.reason == .domain("example.test"))
}

@Test func appMatchesExactly() {
    let p = validPreset(rules: PresetRules(apps: ["com.example.call"]))
    #expect(PresetRuleMatcher.match(presets: [p], title: nil, attendeeEmails: [],
                                    app: "com.example.call")?.reason == .app("com.example.call"))
    #expect(PresetRuleMatcher.match(presets: [p], title: nil, attendeeEmails: [],
                                    app: "com.example.other") == nil)
}

@Test func firstPresetInOrderWins() {
    let first = validPreset("First", rules: PresetRules(titleContains: ["standup"]))
    let second = validPreset("Second", rules: PresetRules(titleContains: ["standup"]))
    let match = PresetRuleMatcher.match(presets: [first, second], title: "Standup",
                                        attendeeEmails: [], app: nil)
    #expect(match?.presetID == first.id)
}

@Test func invalidPresetIsSkippedEvenWhenItMatches() {
    // Bez ASR: validate() rzuca, więc reguła nie może wybrać tego presetu.
    let broken = Preset(name: "Broken", language: .polish, asr: nil,
                        rules: PresetRules(titleContains: ["standup"]))
    let good = validPreset(rules: PresetRules(titleContains: ["standup"]))
    let match = PresetRuleMatcher.match(presets: [broken, good], title: "Standup",
                                        attendeeEmails: [], app: nil)
    #expect(match?.presetID == good.id)
}

@Test func autoLanguagePresetIsNotSkipped() {
    let auto = Preset(name: "Auto", language: nil, asr: asr, languageAuto: true,
                      rules: PresetRules(titleContains: ["weekly sync"]))
    let match = PresetRuleMatcher.match(presets: [auto], title: "Weekly sync",
                                        attendeeEmails: [], app: nil)
    #expect(match?.presetID == auto.id)
}

@Test func noRulesOrEmptyRulesChooseNothing() {
    let noRules = validPreset()
    #expect(PresetRuleMatcher.match(presets: [noRules], title: "Standup",
                                    attendeeEmails: ["anna@example.test"], app: "com.example.call") == nil)

    let empty = validPreset(rules: PresetRules())
    #expect(empty.rules?.isEmpty == true)
    #expect(PresetRuleMatcher.match(presets: [empty], title: "Standup",
                                    attendeeEmails: ["anna@example.test"], app: "com.example.call") == nil)
}

@Test func allNilInputsChooseNothing() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"], attendeeDomains: ["example.test"],
                                           apps: ["com.example.call"]))
    #expect(PresetRuleMatcher.match(presets: [p], title: nil, attendeeEmails: [], app: nil) == nil)
}

@Test func autoStateApplySetsMatch() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.key == "k1")
    #expect(state.match?.presetID == p.id)
}

@Test func autoStateApplySameKeyDoesNotRecompute() {
    let first = validPreset("First", rules: PresetRules(titleContains: ["standup"]))
    let second = validPreset("Second", rules: PresetRules(titleContains: ["weekly"]))
    var state = AutoPresetState()
    state.apply(presets: [first, second], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    // Powtórne `present` z innym tytułem nie może przeliczyć wyniku.
    state.apply(presets: [first, second], key: "k1", title: "Weekly", attendeeEmails: [], app: nil)
    #expect(state.match?.presetID == first.id)
}

@Test func autoStateManualChoiceBlocksLaterApplyForThatKey() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    state.chooseManually(key: "k1")
    #expect(state.match == nil)
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match == nil)
}

@Test func autoStatePageOverrideBlocksEveryKeyUntilConsume() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.chooseManually(key: nil)
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match == nil)
    state.apply(presets: [p], key: "k2", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match == nil)
}

@Test func autoStateConsumeResetsPageOverrideAndClearsMatch() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.chooseManually(key: nil)
    state.consume()
    #expect(state.match == nil)
    #expect(state.key == nil)
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match?.presetID == p.id)
}

@Test func autoStateClearContextKeepsManualChoices() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    state.chooseManually(key: "k1")
    state.clearContext()
    #expect(state.match == nil)
    #expect(state.key == nil)
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match == nil)
}

@Test func autoStateOtherKeyStillMatchesAfterManualChoice() {
    let p = validPreset(rules: PresetRules(titleContains: ["standup"]))
    var state = AutoPresetState()
    state.chooseManually(key: "k1")
    state.apply(presets: [p], key: "k2", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.match?.presetID == p.id)
}

@Test func autoStateNoRulesKeepsKeyWithoutMatch() {
    let p = validPreset()
    var state = AutoPresetState()
    state.apply(presets: [p], key: "k1", title: "Standup", attendeeEmails: [], app: nil)
    #expect(state.key == "k1")
    #expect(state.match == nil)
}

@Test func ruleTextAndLinesRoundTripKeepTrailingNewline() {
    #expect(PresetRules.lines("") == nil)
    #expect(PresetRules.text(nil) == "")
    let text = "Standup\nWeekly\n"
    #expect(PresetRules.text(PresetRules.lines(text)) == text)
    #expect(PresetRules.text(["a", ""]) == "a\n")
}

@Test func makeRulesReturnsNilWhenAllEmpty() {
    #expect(PresetRules.make(titleText: "", domainText: "", apps: nil) == nil)
    #expect(PresetRules.make(titleText: "", domainText: "", apps: []) == nil)
}

@Test func makeRulesWithOnlyApps() throws {
    let rules = try #require(PresetRules.make(titleText: "", domainText: "", apps: ["com.example.call"]))
    #expect(rules.apps == ["com.example.call"])
    #expect(rules.titleContains == nil)
    #expect(rules.attendeeDomains == nil)
}
