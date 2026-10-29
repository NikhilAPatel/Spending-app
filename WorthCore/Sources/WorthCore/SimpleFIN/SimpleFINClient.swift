import Foundation

public enum SimpleFINError: Error, LocalizedError, Equatable {
    case invalidSetupToken
    case tokenAlreadyClaimed
    case invalidAccessURL
    case authenticationFailed
    case paymentRequired
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSetupToken:
            "That doesn't look like a SimpleFIN setup token. Copy the whole token from SimpleFIN Bridge."
        case .tokenAlreadyClaimed:
            "SimpleFIN rejected this setup token. Each token works once; create a new one in SimpleFIN Bridge."
        case .invalidAccessURL:
            "The saved SimpleFIN connection is invalid. Reconnect with a new setup token."
        case .authenticationFailed:
            "SimpleFIN access was revoked or expired. Reconnect with a new setup token."
        case .paymentRequired:
            "Your SimpleFIN Bridge subscription needs attention (payment required)."
        case let .server(code):
            "SimpleFIN returned an error (HTTP \(code)). Try again later."
        }
    }
}

/// Talks to a SimpleFIN server (normally SimpleFIN Bridge). Read-only by design:
/// the protocol has no way to move money.
public struct SimpleFINClient: Sendable {
    /// SimpleFIN Bridge asks apps to stay at or under 24 requests a day and 90 days per request.
    public static let maxHistoryDays = 90

    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// A setup token is a base64-encoded claim URL.
    public static func claimURL(fromSetupToken token: String) throws -> URL {
        let cleaned = token.filter { !$0.isWhitespace }
        var base64 = cleaned
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard
            let data = Data(base64Encoded: base64),
            let string = String(data: data, encoding: .utf8),
            let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https", url.host != nil
        else {
            throw SimpleFINError.invalidSetupToken
        }
        return url
    }

    /// Exchanges a one-time setup token for a long-lived access URL (which embeds credentials).
    public func claim(setupToken: String) async throws -> String {
        let url = try Self.claimURL(fromSetupToken: setupToken)
        let response = try await http.send(HTTPRequest(url: url, method: .post, headers: ["Content-Length": "0"]))
        switch response.status {
        case 200..<300:
            let accessURL = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try Self.parseAccessURL(accessURL)
            return accessURL
        case 403:
            throw SimpleFINError.tokenAlreadyClaimed
        default:
            throw SimpleFINError.server(response.status)
        }
    }

    public struct AccessURLParts: Equatable, Sendable {
        public var baseURL: URL
        public var authorizationHeader: String
    }

    /// Splits `https://user:pass@host/simplefin` into a credential-free base URL and a Basic auth header.
    public static func parseAccessURL(_ accessURL: String) throws -> AccessURLParts {
        guard
            var components = URLComponents(string: accessURL),
            components.scheme == "https",
            components.host != nil,
            let user = components.user,
            let password = components.password
        else {
            throw SimpleFINError.invalidAccessURL
        }
        components.user = nil
        components.password = nil
        components.query = nil
        if components.path.hasSuffix("/") { components.path.removeLast() }
        guard let base = components.url else { throw SimpleFINError.invalidAccessURL }
        let credentials = Data("\(user):\(password)".utf8).base64EncodedString()
        return AccessURLParts(baseURL: base, authorizationHeader: "Basic \(credentials)")
    }

    /// Fetches all accounts with transactions posted on or after `startDate`.
    public func fetchAccounts(accessURL: String, startDate: Date?, now: Date = Date()) async throws -> SimpleFINAccountSet {
        let parts = try Self.parseAccessURL(accessURL)
        var components = URLComponents(url: parts.baseURL.appendingPathComponent("accounts"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "pending", value: "1")]
        if let startDate {
            let earliest = now.addingTimeInterval(-Double(Self.maxHistoryDays) * 86_400)
            let start = max(startDate, earliest)
            query.append(URLQueryItem(name: "start-date", value: String(Int(start.timeIntervalSince1970))))
        }
        components.queryItems = query
        let request = HTTPRequest(url: components.url!, headers: ["Authorization": parts.authorizationHeader])

        let response = try await http.send(request)
        switch response.status {
        case 200..<300:
            return try JSONDecoder().decode(SimpleFINAccountSet.self, from: response.body)
        case 401, 403:
            throw SimpleFINError.authenticationFailed
        case 402:
            throw SimpleFINError.paymentRequired
        default:
            throw SimpleFINError.server(response.status)
        }
    }
}
