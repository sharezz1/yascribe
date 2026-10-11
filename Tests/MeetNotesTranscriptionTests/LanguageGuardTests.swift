import Testing
import MeetNotesProviders
@testable import MeetNotesTranscription

// Zdania z rozdz. 14: polskie spotkanie, a model zwrócił płynną angielszczyznę.
@Test(arguments: [
    "Mr. President, I am very happy to be here in the next few days. Thank you for your attention.",
    "I think there is a problem with the production of the products.",
    "The only thing that I can do is to take a look at the people who are not in the same boat.",
])
func confabulatedEnglishInPolishMeetingIsFlagged(_ text: String) {
    #expect(LanguageGuard.mismatch(text, expected: .polish) == .english)
}

@Test func realPolishIsNotFlagged() {
    #expect(LanguageGuard.mismatch("No, dobra. Słuchajcie, dzisiaj mamy spotkanie, by sobie przekazać wiedzę.", expected: .polish) == nil)
    #expect(LanguageGuard.mismatch("Chociaż mieliśmy wczoraj some things do omówienia", expected: .polish) == nil)
}

@Test func tooShortToJudge() {
    #expect(LanguageGuard.mismatch("Thank you", expected: .polish) == nil)
}

@Test func unsupportedLanguageStaysSilent() throws {
    #expect(LanguageGuard.mismatch("the and is to of you that it", expected: try LanguageCode("de")) == nil)
}
