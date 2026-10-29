import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct KrakenCredentials: Codable, Sendable, Equatable {
    public var apiKey: String
    public var privateKey: String

    public init(apiKey: String, privateKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.privateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum KrakenError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidPrivateKey
    case unsupportedPlatform
    case api([String])

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Kraken API key is missing. Remove this wallet and add it again."
        case .invalidPrivateKey: "The Kraken private key isn't valid base64. Copy it again from Kraken."
        case .unsupportedPlatform: "Kraken signing needs CryptoKit (iOS/macOS)."
        case let .api(errors):
            errors.contains { $0.contains("Invalid key") || $0.contains("Permission denied") }
                ? "Kraken rejected the API key. It needs the \"Query Funds\" permission only."
                : "Kraken: \(errors.joined(separator: ", "))"
        }
    }
}

/// Kraken account balances via the private REST API. Use a key with only "Query Funds"
/// permission so it can't trade or withdraw.
struct KrakenFetcher: Sendable {
    let http: HTTPClient
    var baseURL = URL(string: "https://api.kraken.com")!

    private struct BalanceResponse: Decodable {
        let error: [String]
        let result: [String: String]?
    }

    func holdings(credentials: KrakenCredentials, nonce: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) async throws -> [CryptoHolding] {
        let path = "/0/private/Balance"
        let postData = "nonce=\(nonce)"
        let signature = try Self.signature(path: path, nonce: String(nonce), postData: postData, privateKey: credentials.privateKey)
        let request = HTTPRequest(
            url: baseURL.appendingPathComponent(path),
            method: .post,
            headers: [
                "API-Key": credentials.apiKey,
                "API-Sign": signature,
                "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
            ],
            body: Data(postData.utf8)
        )
        let response = try await http.json(BalanceResponse.self, request)
        guard response.error.isEmpty, let result = response.result else {
            throw KrakenError.api(response.error)
        }
        return Self.holdings(from: result)
    }

    static func holdings(from balances: [String: String]) -> [CryptoHolding] {
        balances
            .compactMap { code, amount -> CryptoHolding? in
                guard let quantity = Decimal(apiString: amount), quantity > 0 else { return nil }
                let symbol = normalize(code)
                return CryptoHolding(symbol: symbol, name: code == symbol ? nil : code, quantity: quantity, priceBySymbol: true)
            }
            .sorted { $0.symbol < $1.symbol }
    }

    /// Maps Kraken asset codes to common tickers: XXBT -> BTC, ZUSD -> USD, ETH2.S -> ETH, SOL.F -> SOL.
    static func normalize(_ code: String) -> String {
        let asset = String(code.split(separator: ".").first ?? Substring(code)).uppercased()
        let legacy: [String: String] = [
            "XXBT": "BTC", "XBT": "BTC", "XETH": "ETH", "ETH2": "ETH", "XXDG": "DOGE", "XDG": "DOGE",
            "XLTC": "LTC", "XXRP": "XRP", "XXLM": "XLM", "XXMR": "XMR", "XZEC": "ZEC", "XETC": "ETC",
            "XMLN": "MLN", "XREP": "REP", "ZUSD": "USD", "ZEUR": "EUR", "ZGBP": "GBP", "ZCAD": "CAD",
            "ZJPY": "JPY", "ZAUD": "AUD", "ZCHF": "CHF",
        ]
        return legacy[asset] ?? asset
    }

    /// API-Sign = base64(HMAC-SHA512(base64decode(privateKey), path + SHA256(nonce + postData)))
    static func signature(path: String, nonce: String, postData: String, privateKey: String) throws -> String {
        guard let secret = Data(base64Encoded: privateKey) else { throw KrakenError.invalidPrivateKey }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data((nonce + postData).utf8))
        var message = Data(path.utf8)
        message.append(contentsOf: digest)
        let mac = HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        return Data(mac).base64EncodedString()
        #else
        _ = secret
        throw KrakenError.unsupportedPlatform
        #endif
    }
}
