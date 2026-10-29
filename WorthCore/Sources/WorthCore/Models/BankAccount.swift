import Foundation

public enum AccountKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cash
    case creditCard
    case investment
    case loan
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash: "Checking & Savings"
        case .creditCard: "Credit Card"
        case .investment: "Investment"
        case .loan: "Loan"
        case .other: "Other"
        }
    }

    public var isLiability: Bool { self == .creditCard || self == .loan }
}

/// An account synced from SimpleFIN, plus the user's settings for it.
public struct BankAccount: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var institution: String
    public var currency: String
    public var balance: Decimal
    public var availableBalance: Decimal?
    public var balanceDate: Date
    public var holdings: [Holding]

    public var kind: AccountKind
    public var includeInNetWorth: Bool
    public var includeInSpending: Bool
    public var nickname: String?

    public init(
        id: String,
        name: String,
        institution: String,
        currency: String = "USD",
        balance: Decimal,
        availableBalance: Decimal? = nil,
        balanceDate: Date,
        holdings: [Holding] = [],
        kind: AccountKind,
        includeInNetWorth: Bool = true,
        includeInSpending: Bool? = nil,
        nickname: String? = nil
    ) {
        self.id = id
        self.name = name
        self.institution = institution
        self.currency = currency
        self.balance = balance
        self.availableBalance = availableBalance
        self.balanceDate = balanceDate
        self.holdings = holdings
        self.kind = kind
        self.includeInNetWorth = includeInNetWorth
        self.includeInSpending = includeInSpending ?? (kind == .cash || kind == .creditCard)
        self.nickname = nickname
    }

    public var displayName: String { nickname?.isEmpty == false ? nickname! : name }

    /// What this account adds to net worth. Banks disagree on whether a card balance
    /// is positive or negative, so debts always count as -|balance|.
    public var netWorthValue: Decimal {
        kind.isLiability ? -abs(balance) : balance
    }
}

public struct Holding: Codable, Hashable, Sendable {
    public var symbol: String
    public var description: String?
    public var shares: Decimal?
    public var marketValue: Decimal?
    public var costBasis: Decimal?

    public init(symbol: String, description: String? = nil, shares: Decimal? = nil, marketValue: Decimal? = nil, costBasis: Decimal? = nil) {
        self.symbol = symbol
        self.description = description
        self.shares = shares
        self.marketValue = marketValue
        self.costBasis = costBasis
    }
}

public struct BankTransaction: Codable, Identifiable, Hashable, Sendable {
    /// Unique across accounts: "<accountId>|<SimpleFIN transaction id>".
    public var id: String
    public var accountId: String
    public var date: Date
    /// Negative = money leaving the account (a purchase on a card or a debit from checking).
    public var amount: Decimal
    public var description: String
    public var payee: String?
    public var memo: String?
    public var isPending: Bool

    public init(id: String, accountId: String, date: Date, amount: Decimal, description: String, payee: String? = nil, memo: String? = nil, isPending: Bool = false) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.description = description
        self.payee = payee
        self.memo = memo
        self.isPending = isPending
    }

    public var displayName: String {
        if let payee, !payee.isEmpty { return payee }
        return description
    }
}

extension AccountKind {
    /// Best guess from the account and institution names; the user can change it in the app.
    public static func guess(name: String, institution: String, balance: Decimal, hasHoldings: Bool) -> AccountKind {
        let text = " \(name) \(institution) ".uppercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        if has(["MORTGAGE", " LOAN", "HELOC", "LINE OF CREDIT", "STUDENT"]) { return .loan }
        if has(["CHECKING", "SAVINGS", "MONEY MARKET", "SPENDING", "CASH MANAGEMENT"]) { return .cash }
        if hasHoldings || has([
            "BROKERAGE", "INVEST", " IRA", "ROTH", "401", "403(B)", "403B", "TRADING", "INDIVIDUAL",
            "JOINT", "STOCK PLAN", "ROBINHOOD", "MORGAN STANLEY", "E*TRADE", "ETRADE", "FIDELITY",
            "SCHWAB", "VANGUARD", "WEALTHFRONT", "BETTERMENT", "SHAREWORKS",
        ]) { return .investment }
        if has([
            "CREDIT CARD", " CARD", "VISA", "MASTERCARD", "AMERICAN EXPRESS", "AMEX", "PLATINUM", "GOLD",
            "SAPPHIRE", "FREEDOM", "ACTIVE CASH", "AUTOGRAPH", "REFLECT", "BLUE CASH", "SKYMILES",
            "BONVOY", "HILTON HONORS", "APPLE CARD", "VENTURE", "QUICKSILVER", "DOUBLE CASH",
        ]) { return .creditCard }
        return balance < 0 ? .creditCard : .cash
    }
}
