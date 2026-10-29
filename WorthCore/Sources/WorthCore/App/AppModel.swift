import Foundation
import Observation

/// All app state and actions. Views read from it and call its methods; it owns persistence,
/// secrets and network refreshes.
@MainActor
@Observable
public final class AppModel {
    /// SimpleFIN Bridge updates from banks about once a day and asks apps to stay under 24
    /// requests a day, so bank data is pulled at most hourly (pull-to-refresh) or every 6 hours
    /// (automatic, on app open).
    public static let manualBankInterval: TimeInterval = 60 * 60
    public static let automaticBankInterval: TimeInterval = 6 * 60 * 60
    public static let automaticCryptoInterval: TimeInterval = 15 * 60
    /// How far before the last sync to re-request, so late-posting and edited transactions are caught.
    public static let bankOverlap: TimeInterval = 10 * 86_400

    public private(set) var data: AppData
    public private(set) var categorized: [CategorizedTransaction] = []
    public private(set) var catalog = CategoryCatalog()
    public private(set) var isRefreshing = false
    /// Problems from the last refresh, shown as a banner.
    public private(set) var refreshMessages: [String] = []
    public private(set) var saveError: String?

    @ObservationIgnored private let store: DataStore
    @ObservationIgnored public let secrets: SecretStore
    @ObservationIgnored private let http: HTTPClient
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        store: DataStore,
        secrets: SecretStore,
        http: HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.secrets = secrets
        self.http = http
        self.now = now
        do {
            data = try store.load() ?? AppData()
        } catch {
            data = AppData()
            saveError = "Couldn't read saved data: \(error.localizedDescription)"
        }
        recategorize()
    }

    // MARK: - Derived data

    public var netWorth: NetWorthBreakdown {
        NetWorthCalculator.breakdown(accounts: data.accounts, wallets: data.wallets, manualAssets: data.manualAssets)
    }

    public var spendingAccountIDs: Set<String> {
        Set(data.accounts.filter(\.includeInSpending).map(\.id))
    }

    public func summary(for month: MonthKey) -> MonthlySummary {
        SpendingReport.summary(for: month, transactions: categorized, accountIDs: spendingAccountIDs, catalog: catalog)
    }

    public func trend(endingAt month: MonthKey, count: Int = 6) -> [MonthlySummary] {
        SpendingReport.trend(endingAt: month, count: count, transactions: categorized, accountIDs: spendingAccountIDs, catalog: catalog)
    }

    public var currentMonth: MonthKey { MonthKey(now()) }

    public func account(id: String) -> BankAccount? {
        data.accounts.first { $0.id == id }
    }

    public var hasAnyData: Bool {
        !data.accounts.isEmpty || !data.wallets.isEmpty || !data.manualAssets.isEmpty
    }

    /// When pull-to-refresh will next fetch from the banks, if that's in the future.
    public var nextManualBankRefresh: Date? {
        guard let last = data.lastSimpleFINSync else { return nil }
        let next = last.addingTimeInterval(Self.manualBankInterval)
        return next > now() ? next : nil
    }

    // MARK: - Refresh

    /// Call when the app comes to the foreground.
    public func refreshIfStale() async {
        if let last = data.lastRefresh, now().timeIntervalSince(last) < Self.automaticCryptoInterval { return }
        await refresh(userInitiated: false)
    }

    public func refresh(userInitiated: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var messages: [String] = []

        let bankInterval = userInitiated ? Self.manualBankInterval : Self.automaticBankInterval
        if data.simpleFINConnected, data.lastSimpleFINSync.map({ now().timeIntervalSince($0) >= bankInterval }) ?? true {
            do {
                try await syncBanks()
            } catch {
                messages.append(error.localizedDescription)
            }
        }

        await refreshWallets()
        await priceManualCrypto()
        messages += data.wallets.compactMap { wallet in wallet.lastError.map { "\(wallet.label): \($0)" } }
        messages += data.simpleFINMessages

        recordSnapshot()
        data.lastRefresh = now()
        refreshMessages = messages
        persist()
    }

    private func syncBanks() async throws {
        guard let accessURL = secrets.secret(for: SecretKey.simpleFINAccessURL) else {
            data.simpleFINConnected = false
            throw SimpleFINError.invalidAccessURL
        }
        let current = now()
        let earliest = current.addingTimeInterval(-Double(SimpleFINClient.maxHistoryDays) * 86_400)
        let start = max(data.lastSimpleFINSync.map { $0.addingTimeInterval(-Self.bankOverlap) } ?? earliest, earliest)

        let response = try await SimpleFINClient(http: http).fetchAccounts(accessURL: accessURL, startDate: start, now: current)
        let merged = SimpleFINSync.merge(accounts: data.accounts, transactions: data.transactions, with: response, windowStart: start, now: current)
        data.accounts = merged.accounts
        data.transactions = merged.transactions
        data.simpleFINMessages = response.errors
        data.lastSimpleFINSync = current
        recategorize()
    }

    private func refreshWallets() async {
        guard !data.wallets.isEmpty else { return }
        let service = CryptoPortfolioService(http: http, secrets: secrets, prices: PriceService(http: http))
        let wallets = data.wallets
        let timestamp = now()
        let refreshed = await withTaskGroup(of: CryptoWallet.self, returning: [UUID: CryptoWallet].self) { group in
            for wallet in wallets {
                group.addTask { await service.refresh(wallet, now: timestamp) }
            }
            var results: [UUID: CryptoWallet] = [:]
            for await wallet in group { results[wallet.id] = wallet }
            return results
        }
        // Wallets removed while the refresh was running stay removed.
        for index in data.wallets.indices {
            if let updated = refreshed[data.wallets[index].id] {
                data.wallets[index].holdings = updated.holdings
                data.wallets[index].lastUpdated = updated.lastUpdated
                data.wallets[index].lastError = updated.lastError
            }
        }
    }

    private func priceManualCrypto() async {
        let holdings = data.manualAssets.filter { $0.kind == .cryptoHolding && $0.symbol != nil && $0.quantity != nil }
        guard !holdings.isEmpty else { return }
        let prices = PriceService(http: http)
        for asset in holdings {
            guard let symbol = asset.symbol, let quantity = asset.quantity, let price = await prices.usdPrice(for: symbol) else { continue }
            if let index = data.manualAssets.firstIndex(where: { $0.id == asset.id }) {
                data.manualAssets[index].setValue((quantity * price).rounded(2), on: now())
            }
        }
    }

    private func recordSnapshot() {
        guard hasAnyData else { return }
        data.snapshots = NetWorthCalculator.recording(netWorth, at: now(), into: data.snapshots)
    }

    // MARK: - SimpleFIN

    /// Claims a setup token from SimpleFIN Bridge and pulls the first 90 days of data.
    public func connectSimpleFIN(setupToken: String) async throws {
        let accessURL = try await SimpleFINClient(http: http).claim(setupToken: setupToken)
        try secrets.setSecret(accessURL, for: SecretKey.simpleFINAccessURL)
        data.simpleFINConnected = true
        data.lastSimpleFINSync = nil
        persist()
        try await syncBanks()
        recordSnapshot()
        persist()
    }

    /// Forgets the SimpleFIN credentials. Accounts and history stay until removed.
    public func disconnectSimpleFIN() {
        try? secrets.setSecret(nil, for: SecretKey.simpleFINAccessURL)
        data.simpleFINConnected = false
        data.simpleFINMessages = []
        persist()
    }

    // MARK: - Accounts

    public func updateAccount(_ account: BankAccount) {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        data.accounts[index] = account
        recategorize()
        recordSnapshot()
        persist()
    }

    /// Deletes an account and its transactions (e.g. a closed card). It comes back on the
    /// next sync if it's still linked in SimpleFIN Bridge.
    public func removeAccount(id: String) {
        data.accounts.removeAll { $0.id == id }
        data.transactions.removeAll { $0.accountId == id }
        recategorize()
        recordSnapshot()
        persist()
    }

    // MARK: - Crypto

    public func addWallet(source: CryptoSource, label: String, address: String) async throws {
        if let problem = source.validate(address: address) {
            throw ValidationError(problem)
        }
        let wallet = CryptoWallet(source: source, label: label.isEmpty ? source.displayName : label, address: address)
        try await add(wallet)
    }

    public func addKrakenAccount(label: String, apiKey: String, privateKey: String) async throws {
        let credentials = KrakenCredentials(apiKey: apiKey, privateKey: privateKey)
        guard !credentials.apiKey.isEmpty, !credentials.privateKey.isEmpty else {
            throw ValidationError("Enter both the API key and the private key.")
        }
        guard Data(base64Encoded: credentials.privateKey) != nil else { throw KrakenError.invalidPrivateKey }
        let wallet = CryptoWallet(source: .kraken, label: label.isEmpty ? "Kraken" : label, address: "")
        let json = String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
        try secrets.setSecret(json, for: wallet.keychainKey)
        do {
            try await add(wallet)
        } catch {
            try? secrets.setSecret(nil, for: wallet.keychainKey)
            throw error
        }
    }

    /// Fetches the wallet once before saving it so bad addresses or keys fail right away.
    private func add(_ wallet: CryptoWallet) async throws {
        let service = CryptoPortfolioService(http: http, secrets: secrets, prices: PriceService(http: http))
        let refreshed = await service.refresh(wallet, now: now())
        if let error = refreshed.lastError {
            throw ValidationError(error)
        }
        data.wallets.append(refreshed)
        recordSnapshot()
        persist()
    }

    public func renameWallet(id: UUID, to label: String) {
        guard let index = data.wallets.firstIndex(where: { $0.id == id }), !label.isEmpty else { return }
        data.wallets[index].label = label
        persist()
    }

    public func removeWallet(id: UUID) {
        guard let wallet = data.wallets.first(where: { $0.id == id }) else { return }
        if wallet.source == .kraken {
            try? secrets.setSecret(nil, for: wallet.keychainKey)
        }
        data.wallets.removeAll { $0.id == id }
        recordSnapshot()
        persist()
    }

    // MARK: - Manual assets

    /// Inserts or updates. For coin holdings the value is priced right away.
    public func saveManualAsset(_ asset: ManualAsset) async {
        var asset = asset
        if asset.kind == .cryptoHolding, let symbol = asset.symbol, let quantity = asset.quantity,
           let price = await PriceService(http: http).usdPrice(for: symbol) {
            asset.setValue((quantity * price).rounded(2), on: now())
        }
        if let index = data.manualAssets.firstIndex(where: { $0.id == asset.id }) {
            data.manualAssets[index] = asset
        } else {
            data.manualAssets.append(asset)
        }
        recordSnapshot()
        persist()
    }

    public func deleteManualAsset(id: UUID) {
        data.manualAssets.removeAll { $0.id == id }
        recordSnapshot()
        persist()
    }

    // MARK: - Categories

    /// Sets the category for one transaction, or for every transaction matching `rulePattern`.
    public func setCategory(_ category: String, for transaction: Transaction, rulePattern: String? = nil) {
        if let pattern = rulePattern?.trimmingCharacters(in: .whitespaces), !pattern.isEmpty {
            data.rules.removeAll { Categorizer.normalize($0.pattern) == Categorizer.normalize(pattern) }
            data.rules.append(CategoryRule(pattern: pattern, category: category))
            // The rule now decides; drop one-off overrides it would otherwise be hidden by.
            let matcher = Categorizer(userRules: [CategoryRule(pattern: pattern, category: category)])
            for tx in data.transactions where matcher.match(tx.description + " " + (tx.payee ?? ""))?.isUserRule == true {
                data.overrides[tx.id] = nil
            }
        } else {
            data.overrides[transaction.id] = category
        }
        recategorize()
        persist()
    }

    public func clearOverride(for transaction: Transaction) {
        data.overrides[transaction.id] = nil
        recategorize()
        persist()
    }

    public func deleteRule(id: UUID) {
        data.rules.removeAll { $0.id == id }
        recategorize()
        persist()
    }

    public func addCustomCategory(name: String, kind: CategoryKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !catalog.all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        data.customCategories.append(SpendingCategory(name: trimmed, kind: kind))
        recategorize()
        persist()
    }

    /// A merchant pattern for "always categorize like this", with bank boilerplate removed:
    /// "PURCHASE AUTHORIZED ON 10/12 BLUE BOTTLE COFFEE SAN FRANCISCO CA S3842 CARD 1234" -> "BLUE BOTTLE COFFEE".
    nonisolated public static func suggestedPattern(for transaction: Transaction) -> String {
        let noise: Set<String> = [
            "PURCHASE", "AUTHORIZED", "ON", "POS", "DEBIT", "CARD", "CHECKCARD", "RECURRING", "PAYMENT",
            "SQ", "TST", "APLPAY", "ACH", "WEB", "PPD", "CCD", "ID", "INC", "LLC", "CO", "THE", "WWW", "COM",
            "VISA", "DDA", "PREAUTHORIZED", "ONLINE", "PMT", "BILL", "PAY", "DBT", "CRD", "SP", "PP",
        ]
        let words = Categorizer.normalize(transaction.payee?.isEmpty == false ? transaction.payee! : transaction.description)
            .split(separator: " ")
            .map(String.init)
            .filter { word in !noise.contains(word) && !word.contains(where: \.isNumber) }
        return words.prefix(3).joined(separator: " ")
    }

    // MARK: - Settings

    public func setRequireFaceID(_ enabled: Bool) {
        data.requireFaceID = enabled
        persist()
    }

    public func setOptionalAPIKey(_ value: String, for key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try? secrets.setSecret(trimmed.isEmpty ? nil : trimmed, for: key)
    }

    /// Deletes everything: saved data and every stored credential.
    public func eraseAllData() {
        try? secrets.setSecret(nil, for: SecretKey.simpleFINAccessURL)
        try? secrets.setSecret(nil, for: CryptoSecretKey.ethplorerAPIKey)
        try? secrets.setSecret(nil, for: CryptoSecretKey.jupiterAPIKey)
        for wallet in data.wallets where wallet.source == .kraken {
            try? secrets.setSecret(nil, for: wallet.keychainKey)
        }
        try? store.erase()
        data = AppData()
        refreshMessages = []
        recategorize()
    }

    // MARK: - Internals

    private func recategorize() {
        catalog = CategoryCatalog(custom: data.customCategories)
        let categorizer = Categorizer(userRules: data.rules, overrides: data.overrides, catalog: catalog)
        categorized = categorizer.categorize(data.transactions, accounts: data.accounts)
    }

    private func persist() {
        do {
            try store.save(data)
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

public struct ValidationError: Error, LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
