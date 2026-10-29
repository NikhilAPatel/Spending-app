import Foundation
import Testing
@testable import WorthCore

/// A clock tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current = current.addingTimeInterval(hours * 3600) } }
}

@MainActor
@Suite struct AppModelTests {
    let http = MockHTTP()
    let secrets = InMemorySecretStore()
    let store = InMemoryDataStore()
    let clock = TestClock(date("2025-10-28"))

    func makeModel() -> AppModel {
        let clock = clock
        return AppModel(store: store, secrets: secrets, http: http, now: { clock.now })
    }

    func stubSimpleFIN() {
        http.on(url: "/claim/", body: Fixtures.accessURL)
        http.on(url: "/simplefin/accounts", body: Fixtures.simpleFINAccounts())
    }

    var setupToken: String {
        Data("https://beta-bridge.simplefin.org/simplefin/claim/DEMO".utf8).base64EncodedString()
    }

    @Test func connectingPullsAccountsAndRecordsNetWorth() async throws {
        stubSimpleFIN()
        let model = makeModel()
        try await model.connectSimpleFIN(setupToken: setupToken)

        #expect(secrets.secret(for: SecretKey.simpleFINAccessURL) == Fixtures.accessURL)
        #expect(model.data.accounts.count == 3)
        #expect(model.netWorth.total == dec("5200.50") - dec("2310.44") + dec("15000.25"))
        #expect(model.data.snapshots.count == 1)
        #expect(model.data.simpleFINMessages == ["Wells Fargo needs you to reauthenticate"])

        // The Amex payment pairs with the WF debit; payroll is income; the rest is spending.
        let october = model.summary(for: MonthKey(year: 2025, month: 10))
        #expect(october.income == 4250)
        #expect(october.spending == dec("62.10") + dec("48.20") + 15)

        // Everything persisted.
        let saved = try #require(try store.load())
        #expect(saved.accounts.count == 3)
        #expect(saved.simpleFINConnected)
    }

    @Test func failedFirstSyncStillKeepsTheConnection() async throws {
        http.on(url: "/claim/", body: Fixtures.accessURL)
        http.on(url: "/simplefin/accounts", status: 500, body: "oops")
        let model = makeModel()
        // The token is spent once claimed, so this must not throw and send the user back to re-enter it.
        try await model.connectSimpleFIN(setupToken: setupToken)
        #expect(model.data.simpleFINConnected)
        #expect(secrets.secret(for: SecretKey.simpleFINAccessURL) == Fixtures.accessURL)
        #expect(model.refreshMessages.first?.contains("first sync failed") == true)
        #expect(model.data.lastSimpleFINSync == nil)
    }

    @Test func pullToRefreshRespectsSimpleFINRateLimit() async throws {
        stubSimpleFIN()
        let model = makeModel()
        try await model.connectSimpleFIN(setupToken: setupToken)
        #expect(http.count(matching: "/accounts") == 1)

        clock.advance(hours: 0.5)
        await model.refresh()
        #expect(http.count(matching: "/accounts") == 1)
        #expect(model.nextManualBankRefresh != nil)

        clock.advance(hours: 1)
        await model.refresh()
        #expect(http.count(matching: "/accounts") == 2)
        // Follow-up syncs ask for 10 days before the previous sync, not the full 90.
        let last = try #require(http.requests.last { $0.url.absoluteString.contains("/accounts") })
        let start = try #require(URLComponents(url: last.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "start-date" }?.value.flatMap(Double.init))
        #expect(abs(start - date("2025-10-18").timeIntervalSince1970) < 1)

        // Automatic refresh (app open) waits 6 hours for banks.
        clock.advance(hours: 2)
        await model.refreshIfStale()
        #expect(http.count(matching: "/accounts") == 2)
    }

    @Test func walletsValidateBeforeSaving() async throws {
        let model = makeModel()
        await #expect(throws: ValidationError.self) {
            try await model.addWallet(source: .ethereum, label: "", address: "0x123")
        }
        http.on(url: "mempool.space", status: 400, body: "Invalid Bitcoin address")
        await #expect(throws: ValidationError.self) {
            try await model.addWallet(source: .bitcoin, label: "", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        }
        #expect(model.data.wallets.isEmpty)
    }

    @Test func addingWalletAndManualAssetsUpdatesNetWorth() async throws {
        http.on(url: "mempool.space/api/address/", body: Fixtures.mempoolAddress)
        http.on(url: "pair=XBTUSD", body: Fixtures.krakenBTCTicker)
        http.on(url: "pair=SOLUSD", body: Fixtures.krakenSOLTicker)
        let model = makeModel()
        try await model.addWallet(source: .bitcoin, label: "", address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        #expect(model.data.wallets.first?.label == "Bitcoin")

        await model.saveManualAsset(ManualAsset(name: "Series A", kind: .privateCompany, value: 50_000))
        await model.saveManualAsset(ManualAsset(name: "Staked SOL", kind: .cryptoHolding, value: 0, symbol: "sol", quantity: 10))
        #expect(model.data.manualAssets.first { $0.name == "Staked SOL" }?.value == 1800)
        let expectedTotal: Decimal = 102_500 + 50_000 + 1800
        #expect(model.netWorth.total == expectedTotal)
        #expect(model.netWorth.total(for: .crypto) == 104_300)

        let walletID = try #require(model.data.wallets.first?.id)
        model.removeWallet(id: walletID)
        #expect(model.netWorth.total(for: .crypto) == 1800)
        #expect(model.data.snapshots.last?.total == 51_800)
    }

    @Test func krakenCredentialsLiveInSecretStore() async throws {
        http.on(url: "/0/private/Balance", body: #"{"error":[],"result":{"XXBT":"0.1","ZUSD":"500.00"}}"#)
        http.on(url: "pair=XBTUSD", body: Fixtures.krakenBTCTicker)
        let model = makeModel()
        #if canImport(CryptoKit)
        try await model.addKrakenAccount(label: "", apiKey: "key", privateKey: Data("secret".utf8).base64EncodedString())
        let wallet = try #require(model.data.wallets.first)
        #expect(wallet.totalUSD == 10_500)
        #expect(secrets.secret(for: wallet.keychainKey) != nil)
        model.removeWallet(id: wallet.id)
        #expect(secrets.secret(for: wallet.keychainKey) == nil)
        #else
        // Without CryptoKit the request can't be signed; the key must not be left behind.
        await #expect(throws: ValidationError.self) {
            try await model.addKrakenAccount(label: "", apiKey: "key", privateKey: Data("secret".utf8).base64EncodedString())
        }
        #expect(model.data.wallets.isEmpty)
        #endif
        await #expect(throws: KrakenError.invalidPrivateKey) {
            try await model.addKrakenAccount(label: "", apiKey: "key", privateKey: "not base64!!")
        }
    }

    @Test func recategorizingWithRuleAppliesToAllMatches() async throws {
        stubSimpleFIN()
        let model = makeModel()
        try await model.connectSimpleFIN(setupToken: setupToken)
        let coffee = try #require(model.data.transactions.first { $0.description.contains("BLUE BOTTLE") })

        model.setCategory("Business", for: coffee)
        #expect(model.categorized.first { $0.id == coffee.id }?.source == .override)

        model.setCategory("Business", for: coffee, rulePattern: AppModel.suggestedPattern(for: coffee))
        let result = try #require(model.categorized.first { $0.id == coffee.id })
        #expect(result.category == "Business")
        #expect(result.source == .userRule)
        #expect(model.data.overrides.isEmpty)
        #expect(model.data.rules.map(\.pattern) == ["BLUE BOTTLE COFFEE"])

        model.addCustomCategory(name: "Kids", kind: .expense)
        model.addCustomCategory(name: "kids", kind: .expense)
        #expect(model.data.customCategories.count == 1)
    }

    @Test func excludingAccountsChangesReports() async throws {
        stubSimpleFIN()
        let model = makeModel()
        try await model.connectSimpleFIN(setupToken: setupToken)
        var amex = try #require(model.account(id: "ACT-amex"))
        amex.includeInSpending = false
        amex.includeInNetWorth = false
        model.updateAccount(amex)
        // Only WF checking counts now; its Amex payment is still recognized as a transfer.
        #expect(model.summary(for: MonthKey(year: 2025, month: 10)).spending == dec("62.10"))
        #expect(model.netWorth.total == dec("5200.50") + dec("15000.25"))
    }

    @Test func eraseRemovesDataAndSecrets() async throws {
        stubSimpleFIN()
        let model = makeModel()
        try await model.connectSimpleFIN(setupToken: setupToken)
        model.eraseAllData()
        #expect(model.data.accounts.isEmpty)
        #expect(secrets.secret(for: SecretKey.simpleFINAccessURL) == nil)
        #expect(try store.load() == nil)
    }

    @Test func savedDataSurvivesRelaunch() async throws {
        stubSimpleFIN()
        try await makeModel().connectSimpleFIN(setupToken: setupToken)
        let relaunched = makeModel()
        #expect(relaunched.data.accounts.count == 3)
        #expect(relaunched.categorized.count == 6)
    }

    @Test func fileStoreRoundTripsAndToleratesMissingFields() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileStore = FileDataStore(url: dir.appendingPathComponent("worth.json"))
        #expect(try fileStore.load() == nil)

        var data = AppData()
        data.manualAssets = [ManualAsset(name: "Art", kind: .art, value: dec("1234.56"))]
        data.rules = [CategoryRule(pattern: "X", category: "Y")]
        try fileStore.save(data)
        let loaded = try #require(try fileStore.load())
        #expect(loaded.manualAssets.first?.value == dec("1234.56"))
        #expect(loaded.rules.first?.category == "Y")

        try Data(#"{"rules": []}"#.utf8).write(to: fileStore.url)
        let partial = try #require(try fileStore.load())
        #expect(partial.requireFaceID)
        #expect(partial.accounts.isEmpty)
    }
}
