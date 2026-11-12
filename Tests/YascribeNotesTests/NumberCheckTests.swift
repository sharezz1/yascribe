import Foundation
import Testing
@testable import YascribeNotes
@testable import YascribeTranscription

@Suite struct NumberCheckTests {
    @Test func numberMissingFromTheSourcesIsListed() {
        #expect(NumberCheck.unverified(in: "Zgłoszenie (ID 770) pozostaje otwarte.", sources: ["zgłoszenie jest otwarte"]) == ["770"])
    }

    @Test func separatorsDoNotMatter() {
        #expect(NumberCheck.unverified(in: "Spotkanie o 13:30, kwota 3.8960.", sources: ["o 13.30", "wyszło 3,8960"]).isEmpty)
    }

    @Test func rangesAreCheckedPerNumberAndSingleDigitsAreSkipped() {
        #expect(NumberCheck.unverified(in: "Defekty: 130-150, dwa serwery: 2.", sources: ["było 130 parę i 150 par"]).isEmpty)
        #expect(NumberCheck.unverified(in: "Defekty: 130-170.", sources: ["było 130 parę i 150 par"]) == ["170"])
    }

    @Test func listMarkersAndRepeatsAreNotReported() {
        #expect(NumberCheck.unverified(in: "10. Pierwszy punkt\n12) drugi", sources: ["tekst"]).isEmpty)
        #expect(NumberCheck.unverified(in: "ID 770, potem znowu 770", sources: ["nic"]) == ["770"])
    }

    @Test func fullHourMatchesTheShortSpokenForm() {
        #expect(NumberCheck.unverified(in: "Spotkanie o 11:00.", sources: ["to chyba na 11 jakieś krótkie połączenie"]).isEmpty)
        #expect(NumberCheck.unverified(in: "Spotkanie o 11.", sources: ["o 11:00"]).isEmpty)
        #expect(NumberCheck.unverified(in: "Spotkanie o 12:00.", sources: ["na 11"]) == ["12:00"])
    }

    @Test func numberFromMyNotesOrContextCounts() {
        #expect(NumberCheck.unverified(in: "Ticket 4521", sources: ["transkrypt", "ticket 4521 z mojej notatki"]).isEmpty)
    }
}
