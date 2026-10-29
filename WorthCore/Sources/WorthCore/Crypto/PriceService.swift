import Foundation

/// USD prices for coins by ticker symbol, from Kraken's public market data (no API key).
/// Results are cached for the lifetime of the service, i.e. one refresh.
public actor PriceService {
    public static let stablecoins: Set<String> = [
        "USD", "USDC", "USDT", "DAI", "PYUSD", "USDP", "TUSD", "FDUSD", "GUSD", "USDS", "USDG",
    ]

    private let http: HTTPClient
    private var cache: [String: Decimal] = [:]
    private var misses: Set<String> = []

    public init(http: HTTPClient) {
        self.http = http
    }

    /// Lets other sources (Ethplorer, Hyperliquid) share prices they already returned.
    public func seed(_ symbol: String, _ price: Decimal) {
        cache[symbol.uppercased()] = price
    }

    public func usdPrice(for rawSymbol: String) async -> Decimal? {
        let symbol = rawSymbol.uppercased()
        if Self.stablecoins.contains(symbol) { return 1 }
        if let cached = cache[symbol] { return cached }
        if misses.contains(symbol) { return nil }

        let base = Self.krakenBase(for: symbol)
        for quote in ["USD", "USDT"] {
            if let price = try? await krakenTicker(pair: base + quote) {
                cache[symbol] = price
                return price
            }
        }
        misses.insert(symbol)
        return nil
    }

    /// Kraken still uses XBT for bitcoin and XDG for dogecoin in pair names.
    static func krakenBase(for symbol: String) -> String {
        switch symbol {
        case "BTC": "XBT"
        case "DOGE": "XDG"
        default: symbol
        }
    }

    private struct TickerResponse: Decodable {
        struct Ticker: Decodable {
            /// Last trade: [price, lot volume].
            let c: [String]
        }
        let error: [String]
        let result: [String: Ticker]?
    }

    private func krakenTicker(pair: String) async throws -> Decimal? {
        var components = URLComponents(string: "https://api.kraken.com/0/public/Ticker")!
        components.queryItems = [URLQueryItem(name: "pair", value: pair)]
        let response = try await http.json(TickerResponse.self, HTTPRequest(url: components.url!))
        guard response.error.isEmpty, let ticker = response.result?.values.first, let last = ticker.c.first else {
            return nil
        }
        return Decimal(apiString: last)
    }
}
