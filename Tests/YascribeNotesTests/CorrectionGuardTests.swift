import Foundation
import Testing
@testable import YascribeNotes

@Suite struct CorrectionGuardTests {
    private func apply(_ o: String, _ c: String) -> CorrectionGuard.Result { CorrectionGuard.apply(original: o, corrected: c) }

    @Test func timeSeparatorChangeIsReverted() {
        let r = apply("między 13.30 i 14.30.", "między 13:30 i 14:30.")
        #expect(r.text == "między 13.30 i 14.30." && r.reverted == 2)
    }

    @Test func spokenNumberBecomingDigitsOrBackIsReverted() {
        #expect(apply("tak, do dwunastej.", "Tak, do 12:00.").text == "Tak, do dwunastej.")
        #expect(apply("mamy 2 serwery", "mamy dwa serwery").text == "mamy 2 serwery")
    }

    @Test func otherCorrectionsInTheSameLineSurviveTheRevert() {
        // „Tak," (wielka litera) i „pętla" zostają, cofnięta tylko godzina.
        let r = apply("tak, ale pętka o 13.30", "Tak, ale pętla o 13:30")
        #expect(r.text == "Tak, ale pętla o 13.30" && r.reverted == 1)
    }

    @Test func artifactWordsAreReverted() {
        #expect(apply("już tam podepnąć docelowo", "już tam podepnąą docelowo").text == "już tam podepnąć docelowo") // zdublowany ogonek
        #expect(apply("mam je czwartek, piątek", "mam je czwartek, piąt_ek").text == "mam je czwartek, piątek")      // znak _
        #expect(apply("no tak", "no taaak").text == "no tak")                                                       // trzy takie same litery
    }

    @Test func insertionOfTwoNewWordsIsRevertedButOneWordIsKept() {
        #expect(apply("nie wiem czy to działa", "nie wiem czy to jest tak działa").text == "nie wiem czy to działa")
        let one = apply("nie wiem czy to działa", "nie wiem czy to dobrze działa")
        #expect(one.text == "nie wiem czy to dobrze działa" && one.reverted == 0)
    }

    @Test func ordinaryCorrectionsAreUntouched() {
        // Terminy, fleksja, wielkość liter, interpunkcja, poprawione słowa: nic nie jest cofane, tekst zwracany bez zmian.
        for (o, c) in [("to wojsbot dzwoni", "To Voicebot dzwoni."), ("tak, ale pętka", "Tak, ale pętla"),
                       ("przesta nam", "przestanie nam"), ("z lektą i cytriksa", "z Lektą i Citrixa"), ("około 25, około 25", "Około 25, około 25.")] {
            let r = apply(o, c)
            #expect(r.text == c && r.reverted == 0, "\(o) → \(c)")
        }
    }

    @Test func emptySidesAreReturnedUnchanged() {
        #expect(apply("", "x").text == "x" && apply("x", "").text == "")
    }

    // Kontrola pisowni: słownik podstawiony (w aplikacji NSSpellChecker).
    private static let polish: Set<String> = ["oddziałów", "oddział", "mamy", "dobry", "plan", "spotkanie", "piątek", "Michał"]
    private let speller: @Sendable (String) -> Bool = { !CorrectionGuardTests.polish.contains($0) }
    private func spelled(_ o: String, _ c: String, terms: [String] = []) -> CorrectionGuard.Result {
        CorrectionGuard.apply(original: o, corrected: c, isMisspelled: speller, terms: terms)
    }

    @Test func correctWordBecomingMisspelledIsReverted() {
        let r = spelled("z help desk oddziałów mamy plan", "Z help desk odziałów mamy plan")
        #expect(r.text == "Z help desk oddziałów mamy plan" && r.reverted == 1) // wielka litera zostaje, błędne słowo wraca
    }

    @Test func misspelledOriginalMayBecomeAnyWordAndWithoutCheckerNothingIsReverted() {
        // Oryginał też błędny (błąd ASR): poprawka zostaje, nawet jeśli nowe słowo nie jest w słowniku.
        #expect(spelled("spotkanie w piontek", "spotkanie w piątkek").reverted == 0)
        #expect(CorrectionGuard.apply(original: "z oddziałów mamy plan", corrected: "z odziałów mamy plan").reverted == 0)
    }

    @Test func termsAndTheirInflectedFormsAreNotMisspellings() {
        // „mamy" → „Lekcie": nowe słowo nie jest w słowniku, ale to odmieniony Term.
        #expect(spelled("spotkanie mamy dobry", "spotkanie Lekcie dobry", terms: ["Lekta"]).reverted == 0)
        #expect(spelled("spotkanie mamy dobry", "spotkanie Lekcie dobry").reverted == 1)
    }

    @Test func shortWordsAbbreviationsAndNonLettersAreNotChecked() {
        #expect(spelled("spotkanie mamy dobry", "spotkanie HTTPS dobry").reverted == 0)   // skrót wielkimi
        #expect(spelled("spotkanie mamy dobry", "spotkanie ab dobry").reverted == 0)     // za krótkie
        #expect(spelled("spotkanie mamy dobry", "spotkanie e-mail dobry").reverted == 0) // nie same litery
    }
}
