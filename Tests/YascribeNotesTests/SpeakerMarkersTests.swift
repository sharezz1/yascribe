import Foundation
import Testing
import AppKit
@testable import YascribeNotes

private let two = SpeakerMarkers(keys: ["1": "a", "2": "b"], names: ["a": "Ala"], numbers: ["a": 1, "b": 2])

@Test func speakerMarkersWithoutMapLeaveTextUnchanged() {
    let none = SpeakerMarkers(keys: nil, names: ["a": "Ala"], numbers: ["a": 1])
    #expect(none.resolved("Hi [[S1]]") == "Hi [[S1]]")
    #expect(two.resolved("No markers here.") == "No markers here.")
}

@Test func speakerMarkersResolveNamedAndUnnamed() {
    #expect(two.resolved("[[S1]] i [[S2]]") == "Ala i Speaker 2")
    #expect(two.resolve(1) == .speaker(key: "a", name: "Ala", number: 1))
}

@Test func speakerMarkersLeaveUnknownMarkerVerbatim() {
    #expect(two.resolved("[[S9]] and [[S0]] and [[S01]]") == "[[S9]] and [[S0]] and [[S01]]")
    #expect(two.resolve(9) == nil)
}

@Test func speakerMarkersFallBackToNumberWhenKeyIsGone() {
    let redetected = SpeakerMarkers(keys: ["1": "old"], names: ["new": "Ola"], numbers: ["new": 1])
    #expect(redetected.resolved("[[S1]]") == "Speaker 1")
    #expect(redetected.resolve(1) == .text("Speaker 1"))
}

@Test func speakerMarkersUseCurrentNumber() {
    #expect(SpeakerMarkers(keys: ["1": "b"], names: [:], numbers: ["b": 3]).resolved("[[S1]]") == "Speaker 3")
}

@Test func speakerMarkersLinkBlocks() throws {
    let blocks = two.linked(MarkdownBlocks.group("- [[S1]] said hi"))
    let text = try #require(blocks.first?.text)
    #expect(String(text.characters) == "Ala said hi")
    let link = text.runs.first { $0.link != nil }
    #expect(link?.link == URL(string: "yascribe-speaker:1"))
    #expect(String(text[try #require(link).range].characters) == "Ala")
    let renamed = SpeakerMarkers(keys: ["1": "a"], names: ["a": "Ola"], numbers: ["a": 1])
    #expect(renamed.linked(MarkdownBlocks.group("- [[S1]] said hi")) != blocks)
}

@Test func speakerMarkersSurviveMarkdownParsing() {
    #expect(String(MarkdownBlocks.group("**[[S1]]** ok")[0].text.characters).contains("[[S1]]"))
}

@Test func speakerMarkersStripped() {
    #expect(SpeakerMarkers.stripped("[[S12]] said 12") == " said 12")
}

@Test func noteTextKeepsOnlySpeakerLinks() {
    var style = NoteStyle()
    style.speakerColor = { _ in .systemRed }
    let blocks = two.linked(MarkdownBlocks.group("[[S1]] see [site](https://example.com)"))
    let text = MarkdownBlocks.attributed(blocks, style: style)
    let ala = (text.string as NSString).range(of: "Ala")
    #expect(text.attribute(.link, at: ala.location, effectiveRange: nil) as? URL == URL(string: "yascribe-speaker:1"))
    #expect(text.attribute(.foregroundColor, at: ala.location, effectiveRange: nil) as? NSColor == .systemRed)
    let site = (text.string as NSString).range(of: "site")
    #expect(text.attribute(.link, at: site.location, effectiveRange: nil) == nil)
}
