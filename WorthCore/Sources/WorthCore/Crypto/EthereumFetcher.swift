import Foundation

/// ETH and ERC-20 balances with prices from Ethplorer. The public "freekey" works for
/// personal use; a free personal key from ethplorer.io can be added for higher limits.
struct EthereumFetcher: Sendable {
    let http: HTTPClient
    var apiKey: String = "freekey"

    struct Price: Decodable {
        let rate: Decimal

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let rate = c.lenientDecimal(forKey: .rate) else {
                throw DecodingError.dataCorruptedError(forKey: .rate, in: c, debugDescription: "no rate")
            }
            self.rate = rate
        }

        private enum CodingKeys: String, CodingKey { case rate }
    }

    struct EthBalance: Decodable {
        let balance: Decimal?
        let rawBalance: String?
        let price: Price?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            balance = c.lenientDecimal(forKey: .balance)
            rawBalance = try? c.decodeIfPresent(String.self, forKey: .rawBalance)
            price = try? c.decodeIfPresent(Price.self, forKey: .price)
        }

        private enum CodingKeys: String, CodingKey { case balance, rawBalance, price }
    }

    struct TokenInfo: Decodable {
        let address: String?
        let name: String?
        let symbol: String?
        let decimals: Int
        /// Ethplorer sends `false` instead of an object when it has no price.
        let price: Price?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            address = try? c.decodeIfPresent(String.self, forKey: .address)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
            decimals = c.lenientDecimal(forKey: .decimals).map { NSDecimalNumber(decimal: $0).intValue } ?? 0
            price = try? c.decodeIfPresent(Price.self, forKey: .price)
        }

        private enum CodingKeys: String, CodingKey { case address, name, symbol, decimals, price }
    }

    struct Token: Decodable {
        let tokenInfo: TokenInfo
        let balance: Decimal?
        let rawBalance: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tokenInfo = try c.decode(TokenInfo.self, forKey: .tokenInfo)
            balance = c.lenientDecimal(forKey: .balance)
            rawBalance = try? c.decodeIfPresent(String.self, forKey: .rawBalance)
        }

        private enum CodingKeys: String, CodingKey { case tokenInfo, balance, rawBalance }
    }

    struct AddressInfo: Decodable {
        let ETH: EthBalance?
        let tokens: [Token]?
        let error: APIError?

        struct APIError: Decodable {
            let message: String?
        }
    }

    func holdings(address: String) async throws -> [CryptoHolding] {
        var components = URLComponents(string: "https://api.ethplorer.io/getAddressInfo/\(address)")!
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        let response = try await http.send(HTTPRequest(url: components.url!))
        let info = try? JSONDecoder().decode(AddressInfo.self, from: response.body)
        if let message = info?.error?.message ?? (response.status >= 300 ? response.text : nil) {
            throw HTTPError.status(response.status, message)
        }
        guard let info else { throw HTTPError.status(response.status, "Unexpected response from Ethplorer") }
        return Self.holdings(from: info)
    }

    static func holdings(from info: AddressInfo) -> [CryptoHolding] {
        var holdings: [CryptoHolding] = []
        if let eth = info.ETH {
            let quantity = eth.rawBalance.flatMap(Decimal.init(apiString:))?.shifted(byDecimalPlaces: 18) ?? eth.balance ?? 0
            if quantity > 0 {
                holdings.append(CryptoHolding(symbol: "ETH", name: "Ether", quantity: quantity, priceUSD: eth.price?.rate, priceBySymbol: true))
            }
        }
        for token in info.tokens ?? [] {
            let raw = token.rawBalance.flatMap(Decimal.init(apiString:)) ?? token.balance ?? 0
            let quantity = raw.shifted(byDecimalPlaces: token.tokenInfo.decimals)
            guard quantity > 0 else { continue }
            let symbol = token.tokenInfo.symbol?.trimmingCharacters(in: .whitespaces).uppercased() ?? "?"
            // Only trust Ethplorer's price. Scam airdrops often reuse names like "USDC",
            // so a symbol alone is never enough to price a token.
            holdings.append(CryptoHolding(symbol: symbol, name: token.tokenInfo.name, quantity: quantity, priceUSD: token.tokenInfo.price?.rate))
        }
        return holdings
    }
}
