import AppKit

/// Słownik systemowy dla `CorrectionGuard`: słowo jest błędne, gdy jest błędne w polskim I w angielskim słowniku.
/// shortcut: tylko pl i en (główne języki spotkań); w innych językach oryginał też jest „błędny", więc kontrola nic nie cofa.
enum SystemSpelling {
    static let languages = ["pl", "en"]

    /// `NSSpellChecker` używamy na głównym wątku (korekta działa poza nim; z głównego nie czekamy sami na siebie).
    @Sendable static func isMisspelled(_ word: String) -> Bool {
        func check() -> Bool {
            let checker = NSSpellChecker.shared
            return languages.allSatisfy {
                checker.checkSpelling(of: word, startingAt: 0, language: $0, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
                    .location != NSNotFound
            }
        }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }
}
