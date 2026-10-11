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
