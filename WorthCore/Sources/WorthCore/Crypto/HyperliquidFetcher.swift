import Foundation

/// Read-only Hyperliquid balances from the public info endpoint (no key needed):
/// perps account value, spot tokens, staked HYPE and vault deposits.
struct HyperliquidFetcher: Sendable {
    let http: HTTPClient
    var infoURL = URL(string: "https://api.hyperliquid.xyz/info")!

    private struct ClearinghouseState: Decodable {
        struct MarginSummary: Decodable { let accountValue: String }
        let marginSummary: MarginSummary
    }

    private struct SpotState: Decodable {
        struct Balance: Decodable {
            let coin: String
            let token: Int
            let total: String
        }
        let balances: [Balance]
    }

    private struct SpotMeta: Decodable {
        struct Token: Decodable {
            let name: String
            let index: Int
            let fullName: String?
        }
        struct Pair: Decodable {
            let name: String
            let tokens: [Int]
        }
        let tokens: [Token]
        let universe: [Pair]
    }

    private struct DelegatorSummary: Decodable {
        let delegated: String
        let undelegated: String
        let totalPendingWithdrawal: String
    }

    private struct VaultEquity: Decodable {
        let vaultAddress: String
        let equity: String
    }

    private func info<T: Decodable>(_ body: [String: Any], as type: T.Type) async throws -> T {
        try await http.json(T.self, try .postJSON(infoURL, body))
    }

    func holdings(address rawAddress: String) async throws -> [CryptoHolding] {
        let address = rawAddress.lowercased()
        async let perpsTask = info(["type": "clearinghouseState", "user": address], as: ClearinghouseState.self)
        async let spotTask = info(["type": "spotClearinghouseState", "user": address], as: SpotState.self)
        async let metaTask = info(["type": "spotMeta"], as: SpotMeta.self)
        async let midsTask = info(["type": "allMids"], as: [String: String].self)
        // Staking and vaults are optional extras; don't fail the wallet if they error.
        async let stakingTask = try? info(["type": "delegatorSummary", "user": address], as: DelegatorSummary.self)
        async let vaultsTask = try? info(["type": "userVaultEquities", "user": address], as: [VaultEquity].self)

        let (perps, spot, meta, mids) = try await (perpsTask, spotTask, metaTask, midsTask)
        let staking = await stakingTask
        let vaults = await vaultsTask

        let prices = Self.spotPrices(meta: meta, mids: mids)
        var holdings: [CryptoHolding] = []

        if let value = Decimal(apiString: perps.marginSummary.accountValue), value != 0 {
            holdings.append(CryptoHolding(symbol: "USDC", name: "Perps account value", quantity: value, fixedValueUSD: value))
        }

        for balance in spot.balances {
            guard let quantity = Decimal(apiString: balance.total), quantity > 0 else { continue }
            let price: Decimal? = balance.coin == "USDC" ? 1 : (prices[balance.token] ?? mids[balance.coin].flatMap(Decimal.init(apiString:)))
            holdings.append(CryptoHolding(symbol: balance.coin, name: "Spot", quantity: quantity, priceUSD: price))
        }

        if let staking {
            let staked = [staking.delegated, staking.undelegated, staking.totalPendingWithdrawal]
                .compactMap(Decimal.init(apiString:))
                .reduce(0, +)
            if staked > 0 {
                let hypeIndex = meta.tokens.first { $0.name == "HYPE" }?.index
                let price = hypeIndex.flatMap { prices[$0] } ?? mids["HYPE"].flatMap(Decimal.init(apiString:))
                holdings.append(CryptoHolding(symbol: "HYPE", name: "Staked", quantity: staked, priceUSD: price))
            }
        }

        let vaultTotal = (vaults ?? []).compactMap { Decimal(apiString: $0.equity) }.reduce(0, +)
        if vaultTotal > 0 {
            holdings.append(CryptoHolding(symbol: "USDC", name: "Vault deposits", quantity: vaultTotal, fixedValueUSD: vaultTotal))
        }
        return holdings
    }

    /// Spot token index -> USD price, using each token's /USDC market (token index 0 is USDC).
    private static func spotPrices(meta: SpotMeta, mids: [String: String]) -> [Int: Decimal] {
        var prices: [Int: Decimal] = [:]
        for pair in meta.universe where pair.tokens.count == 2 && pair.tokens[1] == 0 {
            if let mid = mids[pair.name].flatMap(Decimal.init(apiString:)) {
                prices[pair.tokens[0]] = mid
            }
        }
        return prices
    }
}
