import Foundation
import Testing
@testable import WorthCore

/// Hits the real public services with well-known public addresses, to check that the
/// response shapes the fixtures assume still match reality. Skipped unless enabled:
///
///     WORTH_LIVE_TESTS=1 swift test --filter LiveAPITests
///
/// No credentials are used. SimpleFIN and Kraken balances need the user's own keys and
/// are verified in the app instead.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WORTH_LIVE_TESTS"] == "1"), .serialized)
struct LiveAPITests {
    let http = URLSessionHTTPClient()

    func refresh(_ source: CryptoSource, _ address: String) async -> CryptoWallet {
        let service = CryptoPortfolioService(http: http, secrets: InMemorySecretStore(), prices: PriceService(http: http))
        let wallet = await service.refresh(CryptoWallet(source: source, label: source.displayName, address: address))
        print("[\(source.displayName)] error=\(wallet.lastError ?? "none") total=\(wallet.totalUSD)")
        for holding in wallet.holdings.prefix(10) {
            print("   \(holding.symbol) \(holding.name ?? "") qty=\(holding.quantity) price=\(holding.priceUSD.map { "\($0)" } ?? "nil") value=\(holding.valueUSD.map { "\($0)" } ?? "nil")")
        }
        return wallet
    }

    @Test func krakenPublicPrices() async {
        let prices = PriceService(http: http)
        for symbol in ["BTC", "ETH", "SOL", "HYPE", "DOGE", "EUR"] {
            let price = await prices.usdPrice(for: symbol)
            print("[Kraken] \(symbol) = \(price.map { "\($0)" } ?? "nil")")
            if ["BTC", "ETH", "SOL"].contains(symbol) {
                #expect((price ?? 0) > 0, "\(symbol) should have a Kraken USD price")
            }
        }
    }

    /// The genesis block address has held 50+ BTC since 2009.
    @Test func bitcoinAddress() async {
        let wallet = await refresh(.bitcoin, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")
        #expect(wallet.lastError == nil)
        #expect((wallet.holdings.first?.quantity ?? 0) > 50)
        #expect(wallet.totalUSD > 0)
    }

    /// vitalik.eth: holds ETH and many tokens, including unpriced spam.
    @Test func ethereumAddress() async {
        let wallet = await refresh(.ethereum, "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        #expect(wallet.lastError == nil)
        #expect(wallet.holdings.contains { $0.symbol == "ETH" && $0.priceUSD != nil })
    }

    /// Any valid address works; this checks the RPC and Jupiter response shapes.
    @Test func solanaAddress() async {
        let wallet = await refresh(.solana, "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
        #expect(wallet.lastError == nil)
        let jupiter = await SolanaFetcher(http: http).jupiterPrices(for: ["JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"])
        print("[Jupiter] JUP = \(jupiter.values.first.map { "\($0)" } ?? "nil (endpoint moved or needs a key?)")")
        #expect(!jupiter.isEmpty, "Jupiter price API returned nothing; check host/version in SolanaFetcher")
    }

    /// Hyperliquid's HLP vault: has perps equity and is publicly queryable.
    @Test func hyperliquidAddress() async {
        let wallet = await refresh(.hyperliquid, "0xdfc24b077bc1425ad1dea75bcb6f8158e10df303")
        #expect(wallet.lastError == nil)
        #expect(wallet.totalUSD > 0)
    }
}
