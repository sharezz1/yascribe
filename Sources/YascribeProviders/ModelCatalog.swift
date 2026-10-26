import Foundation

/// Która lista modeli należy do jakiej roli i jak ją zawęzić wyszukiwaniem (spec 1.5 §5.4).
/// STT i embeddingi mają osobne listy modalności; korekta i podsumowanie to modele tekstowe.
public enum ModelCatalog {
    /// Wartość `output_modalities` dla zapytania do `/models`; `nil` = lista domyślna.
    public static func outputFilter(for role: Role) -> String? {
        switch role {
        case .asr: "transcription"
        case .embedding: "embeddings"
        case .correction, .summary: nil
        }
    }

    /// Modele widoczne w pickerze: modalność roli (gdy odpowiedź ją niesie — model bez modalności zostaje)
    /// i fragment `id` bez względu na wielkość liter.
    public static func visible(_ models: [ModelInfo], role: Role, query: String) -> [ModelInfo] {
        let wanted = outputFilter(for: role) ?? "text"
        let q = query.trimmingCharacters(in: .whitespaces)
        return models.filter { m in
            (m.outputModalities.map { $0.contains(wanted) } ?? true)
                && (q.isEmpty || m.id.localizedCaseInsensitiveContains(q))
        }
    }
}
