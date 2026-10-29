import Foundation

/// SOL and SPL token balances from a Solana JSON-RPC node, with token prices from Jupiter.
struct SolanaFetcher: Sendable {
    let http: HTTPClient
    var rpcURL = URL(string: "https://api.mainnet-beta.solana.com")!
    /// Optional key from portal.jup.ag; without one the free lite endpoint is used.
    var jupiterAPIKey: String?

    static let tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    static let token2022Program = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    /// Mints we can label and, for stablecoins, price without an API. Keyed by mint address
    /// because token names and symbols are trivially spoofed.
    static let knownMints: [String: (symbol: String, name: String, stable: Bool)] = [
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": ("USDC", "USD Coin", true),
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": ("USDT", "Tether", true),
        "So11111111111111111111111111111111111111112": ("SOL", "Wrapped SOL", false),
        "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": ("JUP", "Jupiter", false),
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": ("BONK", "Bonk", false),
        "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn": ("JITOSOL", "Jito Staked SOL", false),
        "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So": ("MSOL", "Marinade Staked SOL", false),
        "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm": ("WIF", "dogwifhat", false),
    ]

    private struct RPCResponse<T: Decodable>: Decodable {
        struct RPCError: Decodable { let message: String }
        let result: T?
        let error: RPCError?
    }

    private struct BalanceResult: Decodable {
        let value: UInt64
    }

    private struct TokenAccountsResult: Decodable {
        struct Entry: Decodable {
            struct Account: Decodable {
                struct DataField: Decodable {
                    struct Parsed: Decodable {
                        struct Info: Decodable {
                            struct Amount: Decodable {
                                let amount: String
                                let decimals: Int
                                let uiAmountString: String?
                            }
                            let mint: String
                            let tokenAmount: Amount
                        }
                        let info: Info
                    }
                    let parsed: Parsed
                }
                let data: DataField
            }
            let account: Account
        }
        let value: [Entry]
    }

    private func rpc<T: Decodable>(_ method: String, _ params: [Any], as type: T.Type) async throws -> T {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        let response = try await http.json(RPCResponse<T>.self, try .postJSON(rpcURL, body))
        if let error = response.error { throw HTTPError.status(200, error.message) }
        guard let result = response.result else { throw HTTPError.status(200, "Empty response from Solana RPC") }
        return result
    }

    func holdings(address: String) async throws -> [CryptoHolding] {
        let lamports = try await rpc("getBalance", [address], as: BalanceResult.self).value
        var holdings: [CryptoHolding] = []
        let sol = Decimal(lamports).shifted(byDecimalPlaces: 9)
        if sol > 0 { holdings.append(CryptoHolding(symbol: "SOL", name: "Solana", quantity: sol, priceBySymbol: true)) }

        var byMint: [String: Decimal] = [:]
        for program in [Self.tokenProgram, Self.token2022Program] {
            let result = try await rpc(
                "getTokenAccountsByOwner",
                [address, ["programId": program], ["encoding": "jsonParsed"]],
                as: TokenAccountsResult.self
            )
            for entry in result.value {
                let info = entry.account.data.parsed.info
                let amount = info.tokenAmount.uiAmountString.flatMap(Decimal.init(apiString:))
                    ?? Decimal(apiString: info.tokenAmount.amount)?.shifted(byDecimalPlaces: info.tokenAmount.decimals)
                    ?? 0
                if amount > 0 { byMint[info.mint, default: 0] += amount }
            }
        }

        let prices = await jupiterPrices(for: byMint.keys.filter { Self.knownMints[$0]?.stable != true })
        for (mint, quantity) in byMint.sorted(by: { $0.key < $1.key }) {
            let known = Self.knownMints[mint]
            let price: Decimal? = known?.stable == true ? 1 : prices[mint]
            holdings.append(CryptoHolding(
                symbol: known?.symbol ?? "\(mint.prefix(4))…\(mint.suffix(4))",
                name: known?.name ?? mint,
                quantity: quantity,
                priceUSD: price,
                // Wrapped SOL is SOL; matched by mint address, so this can't be spoofed.
                priceBySymbol: mint == "So11111111111111111111111111111111111111112"
            ))
        }
        return holdings
    }

    /// Prices in USD keyed by mint. Failures just leave tokens unpriced.
    func jupiterPrices(for mints: [String]) async -> [String: Decimal] {
        guard !mints.isEmpty else { return [:] }
        var prices: [String: Decimal] = [:]
        let host = jupiterAPIKey == nil ? "https://lite-api.jup.ag" : "https://api.jup.ag"
        for chunk in stride(from: 0, to: mints.count, by: 50).map({ Array(mints[$0..<min($0 + 50, mints.count)]) }) {
            var components = URLComponents(string: "\(host)/price/v3")!
            components.queryItems = [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))]
            var request = HTTPRequest(url: components.url!)
            if let jupiterAPIKey { request.headers["x-api-key"] = jupiterAPIKey }
            guard
                let response = try? await http.send(request),
                (200..<300).contains(response.status)
            else { continue }
            prices.merge(Self.parseJupiterPrices(response.body)) { $1 }
        }
        return prices
    }

    /// Accepts Jupiter's v3 shape `{mint: {usdPrice}}` and the older v2 shape `{data: {mint: {price}}}`.
    static func parseJupiterPrices(_ data: Data) -> [String: Decimal] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let entries = (object["data"] as? [String: Any]) ?? object
        var prices: [String: Decimal] = [:]
        for (mint, value) in entries {
            guard let fields = value as? [String: Any] else { continue }
            let raw = fields["usdPrice"] ?? fields["price"]
            if let number = raw as? NSNumber {
                prices[mint] = Decimal(exactly: number.doubleValue)
            } else if let string = raw as? String, let price = Decimal(apiString: string) {
                prices[mint] = price
            }
        }
        return prices
    }
}
