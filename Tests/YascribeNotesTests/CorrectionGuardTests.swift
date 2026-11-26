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

    @Test func termInBaseFormKeepsTheHeardCaseEnding() {
        // Model poprawia pisownię Termu, ale gubi końcówkę (spike A/B korekty: 13 razy w 4 przebiegach).
        let t = ["Genesys", "Citrix", "Lekta"]
        func termed(_ o: String, _ c: String) -> CorrectionGuard.Result { CorrectionGuard.apply(original: o, corrected: c, terms: t) }
        let r = termed("tą grupę na Genesisa czy raczej nie?", "tą grupę na Genesys, czy raczej nie?")
        #expect(r.text == "tą grupę na Genesysa, czy raczej nie?" && r.reverted == 1)
        #expect(termed("już jest w Genesisie tam", "już jest w Genesys tam").text == "już jest w Genesysie tam")
        #expect(termed("też chcą mieć Genesysa, tylko", "też chcą mieć Genesys, tylko").text == "też chcą mieć Genesysa, tylko")
        #expect(termed("pracujemy w Citriksie", "pracujemy w Citrix.").text == "pracujemy w Citrixie.")
        // Bez końcówki w oryginale, Term kończący się tą samą literą, krótszy oryginał albo forma odmieniona: bez zmian.
        for (o, c) in [("tam Genesis 3", "tam Genesys 3"), ("związanych z Elekta.", "związanych z Lekta."),
                       ("u Genesa jest", "u Genesys jest"), ("od Lecty a propos", "od Lekty a propos")] {
            let r = termed(o, c)
            #expect(r.text == c && r.reverted == 0, "\(o) → \(c)")
        }
    }

    @Test func deletedWordsAreRestoredButFillersMayGo() {
        // Spike A/B korekty: model usuwa urwany początek („wrzucić tam wrzucamy") albo słowo („jeszcze").
        let f = ["yyy", "eee", "mhm"]
        func deleted(_ o: String, _ c: String) -> CorrectionGuard.Result { CorrectionGuard.apply(original: o, corrected: c, fillerWords: f) }
        // Urwany początek zostaje usunięty tylko przy włączonym usuwaniu przerywników i gdy jego pierwsze słowo wraca zaraz potem.
        let r = deleted("no to wrzucić tam wrzucamy na listę", "No to wrzucamy na listę")
        #expect(r.text == "No to wrzucamy na listę" && r.reverted == 0)
        #expect(deleted("Wasielewski miał tam Wasilewski miał tam", "Wasilewski miał tam").reverted == 0)
        let noFillers = CorrectionGuard.apply(original: "no to wrzucić tam wrzucamy na listę", corrected: "No to wrzucamy na listę")
        #expect(noFillers.text == "No to wrzucić tam wrzucamy na listę" && noFillers.reverted == 1)
        // Pierwsze słowo bloku nie wraca albo blok jest długi: zostaje oryginał.
        #expect(deleted("no to trzeba tam wrzucamy na listę", "No to wrzucamy na listę").text == "No to trzeba tam wrzucamy na listę")
        #expect(deleted("wrzucić jedno drugie trzecie czwarte wrzucamy", "Wrzucamy").text == "wrzucić jedno drugie trzecie czwarte Wrzucamy")
        #expect(deleted("trzeba było jeszcze oprócz tego", "trzeba było oprócz tego").text == "trzeba było jeszcze oprócz tego")
        // Przerywniki z listy (także rozciągnięte) i same znaki mogą zniknąć.
        for (o, c) in [("to yyy jest eeee dobre", "To jest dobre"), ("wiem -- mhm, tak", "Wiem, tak"),
                       ("I, i, no i chłopaki", "No i chłopaki"), ("Nie kojarzę, kojarzę, żeby", "Nie kojarzę, żeby")] { // + powtórzenie sąsiada
            let k = deleted(o, c)
            #expect(k.text == c && k.reverted == 0, "\(o) → \(c)")
        }
        // Bez listy przerywników usunięte „yyy" też wraca: użytkownik nie chciał ich usuwać.
        #expect(CorrectionGuard.apply(original: "to yyy jest", corrected: "to jest").text == "to yyy jest")
    }
}
