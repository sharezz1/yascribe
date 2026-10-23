import MeetNotesNotes
import SwiftUI

/// Stan lokalny zakładki Dictionary (bez `@State`: CLT nie ma SwiftUIMacros). Słownik żyje w `AppModel.dictionary`,
/// tu tylko wyszukiwanie, edytowany Term i komunikaty.
final class DictionaryViewState: ObservableObject {
    @Published var query = ""
    /// Term otwarty w arkuszu (podświetlony na liście).
    @Published var selection: UUID?
    /// Kopia robocza edytowanego Terma; `nil` = arkusz zamknięty.
    @Published var draft: DictionaryTerm?
    @Published var draftIsNew = false
    @Published var newAlias = ""
    /// Komunikaty `DictionaryError` przy polu Terma i przy polu Aliasu w arkuszu.
    @Published var termError: String?
    @Published var aliasError: String?
    @Published var confirmingDelete = false
    @Published var importReport: DictionaryImportReport?
    /// Nazwy zaimportowanych plików (podtytuł raportu).
    @Published var importedNames: [String] = []
    /// Błąd zapisu, importu albo eksportu pod listą; `notice` to potwierdzenie udanego eksportu.
    @Published var error: String?
    @Published var notice: String?
    /// Katalog eksportu czekający na zgodę na nadpisanie istniejących plików.
    @Published var pendingExport: URL?

    func openNew() {
        draft = DictionaryTerm(""); draftIsNew = true; selection = nil; resetEditorMessages()
    }

    func open(_ term: DictionaryTerm) {
        draft = term; draftIsNew = false; selection = term.id; resetEditorMessages()
    }

    func closeEditor() {
        draft = nil; selection = nil; resetEditorMessages()
    }

    private func resetEditorMessages() {
        newAlias = ""; termError = nil; aliasError = nil; confirmingDelete = false
    }

    /// Błąd walidacji słownika po angielsku, przy właściwym polu. Pola Terma: pusty i podwójny Term oraz zarezerwowane znaki w nim samym.
    func show(_ e: DictionaryError, draftText: String) {
        termError = nil; aliasError = nil
        switch e {
        case .emptyTerm: termError = "Give the term a name."
        case .duplicateTerm(let t): termError = "“\(t)” is already in the dictionary."
        case .invalidCharacters(let t):
            let message = "Can’t start with # or contain tabs or line breaks."
            if t.trimmingCharacters(in: .whitespacesAndNewlines) == draftText.trimmingCharacters(in: .whitespacesAndNewlines) { termError = message } else { aliasError = message }
        case .aliasTaken(let a, let by): aliasError = "“\(a)” already belongs to “\(by)”."
        case .aliasIsTerm(let a, let term): aliasError = "“\(a)” is already a term (“\(term)”)."
        case .emptyAlias: aliasError = "Type an alias first."
        }
    }
}
