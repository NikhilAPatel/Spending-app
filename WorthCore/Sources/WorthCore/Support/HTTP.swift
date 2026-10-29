import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }

    public var url: URL
    public var method: Method
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: Method = .get, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public static func postJSON(_ url: URL, _ object: Any) throws -> HTTPRequest {
        HTTPRequest(
            url: url,
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: object)
        )
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var text: String { String(decoding: body, as: UTF8.self) }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum HTTPError: Error, LocalizedError, Equatable {
    case status(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .status(code, body):
            let snippet = body.prefix(200)
            return snippet.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(snippet)"
        }
    }
}

extension HTTPClient {
    /// Sends the request and decodes a 2xx JSON body; throws `HTTPError.status` otherwise.
    func json<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) async throws -> T {
        let response = try await send(request)
        guard (200..<300).contains(response.status) else {
            throw HTTPError.status(response.status, response.text)
        }
        return try JSONDecoder().decode(T.self, from: response.body)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: 30)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }
}
