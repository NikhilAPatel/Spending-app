import Foundation
import Testing
@testable import WorthCore

@Suite struct CryptoTests {
    func service(_ http: MockHTTP, secrets: InMemorySecretStore = InMemorySecretStore()) -> CryptoPortfolioService {
        CryptoPortfolioService(http: http, secrets: secrets, prices: PriceService(http: http))
    }

    @Test func bitcoinAddressIncludesMempool() async throws {
        let http = MockHTTP()
        http.on(url: "mempool.space/api/address/bc1qexample", body: Fixtures.mempoolAddress)
        http.on(url: "pair=XBTUSD", body: Fixtures.krakenBTCTicker)
        let wallet = await service(http).refresh(CryptoWallet(source: .bitcoin, label: "Cold", address: "bc1qexample"))
        #expect(wallet.lastError == nil)
        let btc = try #require(wallet.holdings.first)
        #expect(btc.quantity == dec("1.025"))
        #expect(btc.priceUSD == 100_000)
        #expect(wallet.totalUSD == 102_500)
    }

    @Test func bitcoinXpubUsesBlockchainInfo() async throws {
        let xpub = "xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz"
        let http = MockHTTP()
        http.on(url: "blockchain.info/balance", body: #"{"\#(xpub)":{"final_balance":250000000,"n_tx":12,"total_received":900000000}}"#)
        http.on(url: "pair=XBTUSD", body: Fixtures.krakenBTCTicker)
        let wallet = await service(http).refresh(CryptoWallet(source: .bitcoin, label: "Ledger", address: xpub))
        #expect(wallet.holdings.first?.quantity == dec("2.5"))
    }

    @Test func ethereumPricesTokensByContractNotSymbol() async throws {
        let http = MockHTTP()
        http.on(url: "api.ethplorer.io/getAddressInfo/0xd8da", body: Fixtures.ethplorer)
        let wallet = await service(http).refresh(CryptoWallet(source: .ethereum, label: "Main", address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"))
        #expect(wallet.lastError == nil)
        let eth = try #require(wallet.holdings.first { $0.symbol == "ETH" })
        #expect(eth.quantity == dec("1.5"))
        #expect(eth.valueUSD == dec("5250.75"))
        let usdc = wallet.holdings.filter { $0.symbol == "USDC" }
        #expect(usdc.count == 2)
        #expect(usdc.contains { $0.quantity == 2500 && $0.priceUSD == dec("0.9998") })
        // The fake "USDC" airdrop stays unpriced and doesn't inflate the total.
        #expect(usdc.contains { $0.name == "USDC Airdrop" && $0.priceUSD == nil })
        #expect(wallet.totalUSD == dec("5250.75") + dec("2499.5"))
        #expect(http.count(matching: "kraken") == 0)
    }

    @Test func ethereumErrorIsReported() async {
        let http = MockHTTP()
        http.on(url: "ethplorer", status: 400, body: #"{"error":{"code":104,"message":"Invalid address format"}}"#)
        let wallet = await service(http).refresh(CryptoWallet(source: .ethereum, label: "Bad", address: "0x0000000000000000000000000000000000000000"))
        #expect(wallet.lastError?.contains("Invalid address format") == true)
    }

    @Test func solanaNativeAndTokens() async throws {
        let http = MockHTTP()
        http.on(url: "api.mainnet-beta.solana.com", bodyContains: "getBalance", body: Fixtures.solanaBalance)
        http.on(url: "api.mainnet-beta.solana.com", bodyContains: SolanaFetcher.tokenProgram, body: Fixtures.solanaTokens)
        http.on(url: "api.mainnet-beta.solana.com", bodyContains: SolanaFetcher.token2022Program, body: Fixtures.solanaNoTokens)
        http.on(url: "lite-api.jup.ag/price/v3", body: Fixtures.jupiterV3)
        http.on(url: "pair=SOLUSD", body: Fixtures.krakenSOLTicker)
        let wallet = await service(http).refresh(CryptoWallet(source: .solana, label: "Phantom", address: "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"))
        #expect(wallet.lastError == nil)
        let bySymbol = Dictionary(uniqueKeysWithValues: wallet.holdings.map { ($0.symbol, $0) })
        #expect(bySymbol["SOL"]?.quantity == dec("2.5"))
        #expect(bySymbol["SOL"]?.valueUSD == 450)
        #expect(bySymbol["USDC"]?.valueUSD == 125)
        #expect(bySymbol["JUP"]?.valueUSD == 520)
        #expect(wallet.holdings.count == 3)
        // Stablecoins aren't sent to Jupiter.
        let jupiter = try #require(http.requests.first { $0.url.absoluteString.contains("jup.ag") })
        #expect(!jupiter.url.absoluteString.contains("EPjFWdd5"))
    }

    @Test func jupiterParsesV3AndV2() {
        #expect(SolanaFetcher.parseJupiterPrices(Data(Fixtures.jupiterV3.utf8)) == ["JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": dec("0.52")])
        let v2 = #"{"data":{"MintA":{"id":"MintA","type":"derivedPrice","price":"1.25"}},"timeTaken":0.003}"#
        #expect(SolanaFetcher.parseJupiterPrices(Data(v2.utf8)) == ["MintA": dec("1.25")])
    }

    @Test func hyperliquidPerpsSpotStakingVaults() async throws {
        let http = MockHTTP()
        let info = "api.hyperliquid.xyz/info"
        http.on(url: info, bodyContains: #""type":"clearinghouseState""#, body: Fixtures.hlClearinghouse)
        http.on(url: info, bodyContains: #""type":"spotClearinghouseState""#, body: Fixtures.hlSpotState)
        http.on(url: info, bodyContains: #""type":"spotMeta""#, body: Fixtures.hlSpotMeta)
        http.on(url: info, bodyContains: #""type":"allMids""#, body: Fixtures.hlAllMids)
        http.on(url: info, bodyContains: #""type":"delegatorSummary""#, body: Fixtures.hlDelegator)
        http.on(url: info, bodyContains: #""type":"userVaultEquities""#, body: Fixtures.hlVaults)
        let wallet = await service(http).refresh(CryptoWallet(source: .hyperliquid, label: "HL", address: "0xABCDEFabcdef0123456789abcdef0123456789ab"))
        #expect(wallet.lastError == nil)
        let total = dec("13109.482328") + dec("14.625485") + 4000 + 2000 + dec("742.5")
        #expect(wallet.totalUSD == total)
        #expect(wallet.holdings.contains { $0.symbol == "HYPE" && $0.name == "Staked" && $0.priceUSD == 40 })
        #expect(!wallet.holdings.contains { $0.symbol == "PURR" })
        // Addresses are sent lowercased.
        #expect(http.requests.contains { String(decoding: $0.body ?? Data(), as: UTF8.self).contains("0xabcdefabcdef") })
    }

    @Test func hyperliquidToleratesMissingStaking() async throws {
        let http = MockHTTP()
        let info = "api.hyperliquid.xyz/info"
        http.on(url: info, bodyContains: #""type":"clearinghouseState""#, body: Fixtures.hlClearinghouse)
        http.on(url: info, bodyContains: #""type":"spotClearinghouseState""#, body: Fixtures.hlSpotState)
        http.on(url: info, bodyContains: #""type":"spotMeta""#, body: Fixtures.hlSpotMeta)
        http.on(url: info, bodyContains: #""type":"allMids""#, body: Fixtures.hlAllMids)
        let wallet = await service(http).refresh(CryptoWallet(source: .hyperliquid, label: "HL", address: "0xabcdefabcdef0123456789abcdef0123456789ab"))
        #expect(wallet.lastError == nil)
        #expect(!wallet.holdings.contains { $0.name == "Staked" })
    }

    @Test func krakenAssetCodesNormalize() {
        #expect(KrakenFetcher.normalize("XXBT") == "BTC")
        #expect(KrakenFetcher.normalize("XETH") == "ETH")
        #expect(KrakenFetcher.normalize("ETH2.S") == "ETH")
        #expect(KrakenFetcher.normalize("SOL.F") == "SOL")
        #expect(KrakenFetcher.normalize("ZUSD") == "USD")
        #expect(KrakenFetcher.normalize("USD.HOLD") == "USD")
        #expect(KrakenFetcher.normalize("HYPE") == "HYPE")
        let holdings = KrakenFetcher.holdings(from: ["XXBT": "0.5000000000", "ZUSD": "120.50", "DOT.S": "0", "ETH2.S": "2"])
        #expect(holdings.map(\.symbol) == ["BTC", "ETH", "USD"])
        #expect(holdings.first { $0.symbol == "ETH" }?.name == "ETH2.S")
    }

    @Test func krakenMissingKeyIsAnError() async {
        let wallet = await service(MockHTTP()).refresh(CryptoWallet(source: .kraken, label: "Kraken", address: ""))
        #expect(wallet.lastError == KrakenError.missingCredentials.errorDescription)
    }

    #if canImport(CryptoKit)
    /// Example from Kraken's REST authentication docs.
    @Test func krakenSignatureMatchesDocs() throws {
        let signature = try KrakenFetcher.signature(
            path: "/0/private/AddOrder",
            nonce: "1616492376594",
            postData: "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25",
            privateKey: "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg=="
        )
        #expect(signature == "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ==")
    }
    #endif

    @Test func priceServiceFallsBackToUSDTAndCaches() async {
        let http = MockHTTP()
        http.on(url: "pair=FOOUSDT", body: #"{"error":[],"result":{"FOOUSDT":{"c":["2.50","1"]}}}"#)
        http.on(url: "pair=FOOUSD", body: Fixtures.krakenUnknownPair)
        http.on(url: "pair=NOPE", body: Fixtures.krakenUnknownPair)
        let prices = PriceService(http: http)
        #expect(await prices.usdPrice(for: "foo") == dec("2.50"))
        #expect(await prices.usdPrice(for: "FOO") == dec("2.50"))
        #expect(await prices.usdPrice(for: "USDC") == 1)
        #expect(await prices.usdPrice(for: "NOPE") == nil)
        #expect(await prices.usdPrice(for: "NOPE") == nil)
        #expect(http.count(matching: "pair=FOO") == 2)
        #expect(http.count(matching: "pair=NOPE") == 2)
    }

    @Test func addressValidation() {
        #expect(CryptoSource.bitcoin.validate(address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq") == nil)
        #expect(CryptoSource.bitcoin.validate(address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == nil)
        #expect(CryptoSource.bitcoin.validate(address: "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs") != nil)
        #expect(CryptoSource.ethereum.validate(address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045") == nil)
        #expect(CryptoSource.ethereum.validate(address: "0x123") != nil)
        #expect(CryptoSource.solana.validate(address: "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU") == nil)
        #expect(CryptoSource.solana.validate(address: "0OIl-not-base58") != nil)
        #expect(CryptoSource.hyperliquid.validate(address: " 0xd8da6bf26964af9d7eed9e03e53415d37aa96045 ") == nil)
    }
}
