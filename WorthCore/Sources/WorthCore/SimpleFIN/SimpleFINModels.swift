import Foundation

/// Response of `GET <access url>/accounts`. See https://www.simplefin.org/protocol.html
/// Fields beyond the core spec (holdings, errlist) are decoded leniently because Bridge
/// adds them outside the published protocol.
public struct SimpleFINAccountSet: Decodable, Sendable {
    public var errors: [String]
    public var accounts: [SimpleFINAccount]

    private enum CodingKeys: String, CodingKey { case errors, errlist, accounts }

    private struct ErrorEntry: Decodable {
        var code: String?
        var msg: String?
    }

    public init(errors: [String] = [], accounts: [SimpleFINAccount]) {
        self.errors = errors
        self.accounts = accounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([SimpleFINAccount].self, forKey: .accounts) ?? []
        var messages = (try? c.decodeIfPresent([String].self, forKey: .errors)) ?? []
        if let list = try? c.decodeIfPresent([ErrorEntry].self, forKey: .errlist) {
            messages += list.compactMap { $0.msg ?? $0.code }
        }
        var seen = Set<String>()
        errors = messages.filter { seen.insert($0).inserted }
    }
}

public struct SimpleFINOrg: Decodable, Sendable {
    public var name: String?
    public var domain: String?
}

public struct SimpleFINAccount: Decodable, Sendable {
    public var id: String
    public var name: String
    public var currency: String
    public var balance: Decimal
    public var availableBalance: Decimal?
    public var balanceDate: Date
    public var org: SimpleFINOrg?
    public var transactions: [SimpleFINTransaction]
    public var holdings: [SimpleFINHolding]

    private enum CodingKeys: String, CodingKey {
        case id, name, currency, balance, org, transactions, holdings
        case availableBalance = "available-balance"
        case balanceDate = "balance-date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Account"
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        balance = try c.decode(FlexibleDecimal.self, forKey: .balance).value
        availableBalance = c.lenientDecimal(forKey: .availableBalance)
        let seconds = (try? c.decode(Double.self, forKey: .balanceDate)) ?? Date().timeIntervalSince1970
        balanceDate = Date(timeIntervalSince1970: seconds)
        org = try? c.decodeIfPresent(SimpleFINOrg.self, forKey: .org)
        transactions = (try? c.decodeIfPresent([SimpleFINTransaction].self, forKey: .transactions)) ?? []
        holdings = (try? c.decodeIfPresent([SimpleFINHolding].self, forKey: .holdings)) ?? []
    }

    public var institutionName: String {
        org?.name ?? org?.domain ?? "Bank"
    }
}

public struct SimpleFINTransaction: Decodable, Sendable {
    public var id: String
    /// Unix seconds; 0 while the transaction is pending.
    public var posted: Double
    public var amount: Decimal
    public var description: String
    public var payee: String?
    public var memo: String?
    public var transactedAt: Double?
    public var pending: Bool

    private enum CodingKeys: String, CodingKey {
        case id, posted, amount, description, payee, memo, pending
        case transactedAt = "transacted_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        posted = (try? c.decode(Double.self, forKey: .posted)) ?? 0
        amount = try c.decode(FlexibleDecimal.self, forKey: .amount).value
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        payee = try? c.decodeIfPresent(String.self, forKey: .payee)
        memo = try? c.decodeIfPresent(String.self, forKey: .memo)
        transactedAt = try? c.decodeIfPresent(Double.self, forKey: .transactedAt)
        pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? (posted == 0)
    }

    /// When the purchase happened: transacted_at if given, else the posting date.
    public func date(fallback: Date) -> Date {
        if let transactedAt, transactedAt > 0 { return Date(timeIntervalSince1970: transactedAt) }
        if posted > 0 { return Date(timeIntervalSince1970: posted) }
        return fallback
    }
}

public struct SimpleFINHolding: Decodable, Sendable {
    public var symbol: String?
    public var description: String?
    public var shares: Decimal?
    public var marketValue: Decimal?
    public var costBasis: Decimal?

    private enum CodingKeys: String, CodingKey {
        case symbol, description, shares
        case marketValue = "market_value"
        case costBasis = "cost_basis"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        shares = c.lenientDecimal(forKey: .shares)
        marketValue = c.lenientDecimal(forKey: .marketValue)
        costBasis = c.lenientDecimal(forKey: .costBasis)
    }
}
