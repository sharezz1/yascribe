import Foundation

/// Wykrywanie EFEKTYWNEGO kontekstu lokalnego serwera (spec fazy 2.0 §14 pkt 4). Best effort: każdy błąd, 404 i nieznany
/// kształt odpowiedzi to „brak wykrycia", nigdy błąd dla użytkownika. Wynik tylko obniża budżet (`ContextBudget.resolve`).
/// Endpointy leżą POZA `/v1`. `/api/show` odpada: zwraca maksimum modelu, więc niczego by nie obniżył.
public enum ContextProbe {
    /// Klucz `"*"` = jeden model serwera (llama.cpp `/props`); inaczej nazwa modelu bez `:latest` (Ollama `/api/ps`, tylko załadowane).
    public static func effectiveContexts(client: OpenAICompatibleClient) async -> [String: Int] {
        let path = client.provider.baseURL.path
        guard path.hasSuffix("/v1") || path.hasSuffix("/v1/"),
              var root = URLComponents(url: client.provider.baseURL, resolvingAgainstBaseURL: false) else { return [:] }
        root.path = String(path.dropLast(path.hasSuffix("/") ? 4 : 3))
        root.query = nil
        guard let base = root.url else { return [:] }
        if let props = await get(client, base, "props"),
           let n = (props["default_generation_settings"] as? [String: Any])?["n_ctx"] as? Int {
            return ["*": n]
        }
        guard let models = (await get(client, base, "api/ps"))?["models"] as? [[String: Any]] else { return [:] }
        var out: [String: Int] = [:]
        for m in models {
            guard let name = (m["name"] ?? m["model"]) as? String, let n = m["context_length"] as? Int else { continue }
            out[bare(name)] = n
        }
        return out
    }

    public static func detect(client: OpenAICompatibleClient, model: String) async -> Int? {
        let m = await effectiveContexts(client: client)
        return m["*"] ?? m[bare(model)]
    }

    /// Linia dla „Check" w Settings; `nil` = nic wykrytego.
    public static func describe(_ contexts: [String: Int]) -> String? {
        if let n = contexts["*"] { return "Detected context: \(n) tokens" }
        guard !contexts.isEmpty else { return nil }
        return contexts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value) tokens" }.joined(separator: " · ")
    }

    private static func bare(_ model: String) -> String { model.hasSuffix(":latest") ? String(model.dropLast(7)) : model }

    private static func get(_ client: OpenAICompatibleClient, _ base: URL, _ path: String) async -> [String: Any]? {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "GET"
        r.timeoutInterval = 5
        if let key = client.key { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await client.http.send(r), (200..<300).contains(resp.statusCode) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
