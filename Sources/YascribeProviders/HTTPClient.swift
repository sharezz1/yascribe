import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (d, r) = try await URLSession.shared.data(for: request)
        guard let h = r as? HTTPURLResponse else { throw ProviderError.badResponse("not HTTP") }
        return (d, h)
    }
}

/// Ciało odpowiedzi 2xx albo `ProviderError.http` z treścią bez klucza. Najpierw usuń klucz z całej treści,
/// dopiero potem przytnij — inaczej przycięcie w połowie klucza zostawiłoby jego fragment (ChatGPT #11).
func checkedBody(_ data: Data, _ resp: HTTPURLResponse, key: String?) throws -> Data {
    guard (200..<300).contains(resp.statusCode) else {
        var body = String(decoding: data, as: UTF8.self)
        if let key, !key.isEmpty { body = body.replacingOccurrences(of: key, with: "••••") }
        throw ProviderError.http(resp.statusCode, String(body.prefix(300)))
    }
    return data
}
