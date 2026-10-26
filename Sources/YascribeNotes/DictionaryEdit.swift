import Foundation

/// Decyzje zakładki Dictionary bez widoku (testowalne): publikacja z cofnięciem przy nieudanym zapisie i miejsce błędu walidacji (F21, R22).
public enum DictionaryEdit {
    /// Publikuje `proposed`, zapisuje; gdy zapis się nie uda, przywraca `previous` i zwraca komunikat (`nil` = zapisano).
    /// Dzięki temu pamięć nigdy nie rozchodzi się z dyskiem, a ponowna próba zaczyna od tego samego stanu.
    @discardableResult
    public static func commit(_ proposed: UserDictionary, replacing previous: UserDictionary,
                              set: (UserDictionary) -> Void, save: () -> String?) -> String? {
        set(proposed)
        guard let failure = save() else { return nil }
        set(previous)
        return failure
    }

    public enum Field: Equatable, Sendable { case term, alias }

    /// Pole, przy którym pokazać błąd `upsert`, i krótki komunikat po angielsku. `aliasIsTerm` ma dwa źródła: Alias równy cudzemu Termowi
    /// (pole Aliasu) albo nazwa edytowanego Terma równa cudzemu Aliasowi (pole Terma) — rozróżnia je porównanie z nazwą Terma w szkicu.
    public static func presentation(of e: DictionaryError, draftTerm: String) -> (field: Field, message: String) {
        func same(_ a: String, _ b: String) -> Bool {
            UserDictionary.key(a.trimmingCharacters(in: .whitespacesAndNewlines)) == UserDictionary.key(b.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        switch e {
        case .emptyTerm: return (.term, "Give the term a name.")
        case .duplicateTerm(let t): return (.term, "“\(t)” is already in the dictionary.")
        case .invalidCharacters(let t):
            return (same(t, draftTerm) ? .term : .alias, "Can’t start with # or contain tabs or line breaks.")
        case .aliasTaken(let a, let by): return (.alias, "“\(a)” already belongs to “\(by)”.")
        case .aliasIsTerm(let a, let owner):
            return same(a, draftTerm) ? (.term, "“\(a)” is already an alias of “\(owner)”.") : (.alias, "“\(a)” is already a term, so it can’t be an alias.")
        case .emptyAlias: return (.alias, "Type an alias first.")
        }
    }
}
