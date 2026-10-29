import Foundation

/// Bitcoin balance for a single address (mempool.space) or an xpub (blockchain.info).
struct BitcoinFetcher: Sendable {
    let http: HTTPClient

    private struct AddressStats: Decodable {
        struct Stats: Decodable {
            let funded_txo_sum: Int64
            let spent_txo_sum: Int64
        }
        let chain_stats: Stats
        let mempool_stats: Stats?
    }

    private struct BalanceEntry: Decodable {
        let final_balance: Int64
    }

    func holdings(address: String) async throws -> [CryptoHolding] {
        let satoshis: Int64
        if address.hasPrefix("xpub") {
            var components = URLComponents(string: "https://blockchain.info/balance")!
            components.queryItems = [URLQueryItem(name: "active", value: address)]
            let result = try await http.json([String: BalanceEntry].self, HTTPRequest(url: components.url!))
            satoshis = result[address]?.final_balance ?? result.values.reduce(0) { $0 + $1.final_balance }
        } else {
            let url = URL(string: "https://mempool.space/api/address/")!.appendingPathComponent(address)
            let stats = try await http.json(AddressStats.self, HTTPRequest(url: url))
            let confirmed = stats.chain_stats.funded_txo_sum - stats.chain_stats.spent_txo_sum
            let unconfirmed = (stats.mempool_stats?.funded_txo_sum ?? 0) - (stats.mempool_stats?.spent_txo_sum ?? 0)
            satoshis = confirmed + unconfirmed
        }
        return [CryptoHolding(symbol: "BTC", name: "Bitcoin", quantity: Decimal(satoshis).shifted(byDecimalPlaces: 8), priceBySymbol: true)]
    }
}
