import Foundation

public enum AssetGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case cash
    case investments
    case crypto
    case otherAssets
    case debt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash: "Cash"
        case .investments: "Investments"
        case .crypto: "Crypto"
        case .otherAssets: "Other Assets"
        case .debt: "Debt"
        }
    }
}

public struct NetWorthSnapshot: Codable, Hashable, Sendable, Identifiable {
    /// Start of the day this snapshot represents; one snapshot per day.
    public var date: Date
    public var total: Decimal
    public var byGroup: [String: Decimal]

    public var id: Date { date }

    public init(date: Date, total: Decimal, byGroup: [String: Decimal]) {
        self.date = date
        self.total = total
        self.byGroup = byGroup
    }
}

public struct CategoryRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Matched case-insensitively against the transaction description and payee.
    public var pattern: String
    public var category: String

    public init(id: UUID = UUID(), pattern: String, category: String) {
        self.id = id
        self.pattern = pattern
        self.category = category
    }
}

/// Everything the app persists, except secrets (those live in the keychain).
public struct AppData: Codable, Sendable {
    public var accounts: [BankAccount] = []
    public var transactions: [BankTransaction] = []
    public var wallets: [CryptoWallet] = []
    public var manualAssets: [ManualAsset] = []
    public var rules: [CategoryRule] = []
    /// BankTransaction id -> category name, set when the user recategorizes one transaction.
    public var overrides: [String: String] = [:]
    public var customCategories: [SpendingCategory] = []
    public var snapshots: [NetWorthSnapshot] = []

    public var simpleFINConnected = false
    public var lastSimpleFINSync: Date?
    public var simpleFINMessages: [String] = []
    public var lastRefresh: Date?
    public var requireFaceID = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case accounts, transactions, wallets, manualAssets, rules, overrides, customCategories, snapshots
        case simpleFINConnected, lastSimpleFINSync, simpleFINMessages, lastRefresh, requireFaceID
    }

    // Every field is optional on decode so older saved files keep loading as fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([BankAccount].self, forKey: .accounts) ?? []
        transactions = try c.decodeIfPresent([BankTransaction].self, forKey: .transactions) ?? []
        wallets = try c.decodeIfPresent([CryptoWallet].self, forKey: .wallets) ?? []
        manualAssets = try c.decodeIfPresent([ManualAsset].self, forKey: .manualAssets) ?? []
        rules = try c.decodeIfPresent([CategoryRule].self, forKey: .rules) ?? []
        overrides = try c.decodeIfPresent([String: String].self, forKey: .overrides) ?? [:]
        customCategories = try c.decodeIfPresent([SpendingCategory].self, forKey: .customCategories) ?? []
        snapshots = try c.decodeIfPresent([NetWorthSnapshot].self, forKey: .snapshots) ?? []
        simpleFINConnected = try c.decodeIfPresent(Bool.self, forKey: .simpleFINConnected) ?? false
        lastSimpleFINSync = try c.decodeIfPresent(Date.self, forKey: .lastSimpleFINSync)
        simpleFINMessages = try c.decodeIfPresent([String].self, forKey: .simpleFINMessages) ?? []
        lastRefresh = try c.decodeIfPresent(Date.self, forKey: .lastRefresh)
        requireFaceID = try c.decodeIfPresent(Bool.self, forKey: .requireFaceID) ?? true
    }
}
