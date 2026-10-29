import Foundation

public enum CryptoSecretKey {
    public static let ethplorerAPIKey = "ethplorer.apiKey"
    public static let jupiterAPIKey = "jupiter.apiKey"
}

/// Refreshes wallets from their sources and fills in USD prices.
public struct CryptoPortfolioService: Sendable {
    private let http: HTTPClient
    private let secrets: SecretStore
    private let prices: PriceService

    public init(http: HTTPClient, secrets: SecretStore, prices: PriceService) {
        self.http = http
        self.secrets = secrets
        self.prices = prices
    }

    /// Returns the wallet with fresh holdings, or with `lastError` set (keeping the old holdings).
    public func refresh(_ wallet: CryptoWallet, now: Date = Date()) async -> CryptoWallet {
        var updated = wallet
        do {
            var holdings = try await fetchHoldings(for: wallet)
            for index in holdings.indices where holdings[index].valueUSD == nil && holdings[index].priceBySymbol == true {
                holdings[index].priceUSD = await prices.usdPrice(for: holdings[index].symbol)
            }
            updated.holdings = holdings.sorted { ($0.valueUSD ?? 0) > ($1.valueUSD ?? 0) }
            updated.lastUpdated = now
            updated.lastError = nil
        } catch {
            updated.lastError = error.localizedDescription
        }
        return updated
    }

    public func price(of symbol: String) async -> Decimal? {
        await prices.usdPrice(for: symbol)
    }

    private func fetchHoldings(for wallet: CryptoWallet) async throws -> [CryptoHolding] {
        switch wallet.source {
        case .bitcoin:
            return try await BitcoinFetcher(http: http).holdings(address: wallet.address)
        case .ethereum:
            let key = secrets.secret(for: CryptoSecretKey.ethplorerAPIKey).flatMap { $0.isEmpty ? nil : $0 } ?? "freekey"
            return try await EthereumFetcher(http: http, apiKey: key).holdings(address: wallet.address)
        case .solana:
            let key = secrets.secret(for: CryptoSecretKey.jupiterAPIKey).flatMap { $0.isEmpty ? nil : $0 }
            return try await SolanaFetcher(http: http, jupiterAPIKey: key).holdings(address: wallet.address)
        case .hyperliquid:
            return try await HyperliquidFetcher(http: http).holdings(address: wallet.address)
        case .kraken:
            guard
                let json = secrets.secret(for: wallet.keychainKey),
                let credentials = try? JSONDecoder().decode(KrakenCredentials.self, from: Data(json.utf8))
            else {
                throw KrakenError.missingCredentials
            }
            return try await KrakenFetcher(http: http).holdings(credentials: credentials)
        }
    }
}
