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
}
