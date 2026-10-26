import YascribeNotes
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
    /// Nieudany zapis na dysk: arkusz zostaje otwarty z tym komunikatem, słownik w pamięci jest cofnięty.
    @Published var saveError: String?
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
        newAlias = ""; termError = nil; aliasError = nil; saveError = nil; confirmingDelete = false
    }

    /// Błąd walidacji słownika po angielsku, przy właściwym polu (`DictionaryEdit.presentation`, testowane w Notes).
    func show(_ e: DictionaryError, draftText: String) {
        let p = DictionaryEdit.presentation(of: e, draftTerm: draftText)
        termError = p.field == .term ? p.message : nil
        aliasError = p.field == .alias ? p.message : nil
    }
}
