import Foundation

public struct CategorizedTransaction: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        /// The user picked a category for this one transaction.
        case override
        /// One of the user's "always categorize X as Y" rules.
        case userRule
        case builtInRule
        /// Paired with the opposite amount in another of the user's accounts.
        case matchedTransfer
        /// Nothing matched.
        case fallback
    }

    public var transaction: Transaction
    public var category: String
    public var kind: CategoryKind
    public var source: Source

    public var id: String { transaction.id }

    /// Positive for a purchase, negative for a refund; zero for income and transfers.
    public var spendingAmount: Decimal { kind == .expense ? -transaction.amount : 0 }

    /// Positive for money received; zero for spending and transfers.
    public var incomeAmount: Decimal { kind == .income ? transaction.amount : 0 }
}

public struct Categorizer: Sendable {
    struct CompiledRule: Sendable {
        let needle: String
        let category: String
        let isUserRule: Bool
    }

    private let rules: [CompiledRule]
    private let overrides: [String: String]
    private let catalog: CategoryCatalog

    /// Days apart the two sides of a transfer or card payment may post.
    static let transferWindow: TimeInterval = 5 * 86_400

    public init(userRules: [CategoryRule] = [], overrides: [String: String] = [:], catalog: CategoryCatalog = CategoryCatalog()) {
        self.overrides = overrides
        self.catalog = catalog

        func compile(_ pattern: String, _ category: String, user: Bool) -> CompiledRule? {
            let wholeWord = pattern.hasSuffix(" ")
            let normalized = Self.normalize(pattern)
            guard !normalized.isEmpty else { return nil }
            return CompiledRule(needle: " \(normalized)\(wholeWord ? " " : "")", category: category, isUserRule: user)
        }

        let user = userRules.compactMap { compile($0.pattern, $0.category, user: true) }
        var seen = Set<String>()
        let builtIn = BuiltInRules.all
            .compactMap { compile($0.pattern, $0.category, user: false) }
            .filter { seen.insert($0.needle).inserted }
        // User rules first, then the most specific (longest) pattern wins.
        rules = user.sorted { $0.needle.count > $1.needle.count } + builtIn.sorted { $0.needle.count > $1.needle.count }
    }

    /// Uppercases and replaces punctuation with spaces: "SQ *Blue Bottle #12" -> "SQ BLUE BOTTLE 12".
    public static func normalize(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var lastWasSpace = true
        for scalar in text.uppercased().unicodeScalars {
            let isAlnum = (scalar >= "A" && scalar <= "Z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                output.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                output.append(" ")
                lastWasSpace = true
            }
        }
        if output.hasSuffix(" ") { output.removeLast() }
        return output
    }

    /// The first rule matching a description, if any.
    public func match(_ text: String) -> (category: String, isUserRule: Bool)? {
        let haystack = " \(Self.normalize(text)) "
        guard let rule = rules.first(where: { haystack.contains($0.needle) }) else { return nil }
        return (rule.category, rule.isUserRule)
    }

    public func categorize(_ transactions: [Transaction], accounts: [BankAccount]) -> [CategorizedTransaction] {
        let accountsByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var results = transactions.map { transaction -> CategorizedTransaction in
            if let category = overrides[transaction.id] {
                return CategorizedTransaction(transaction: transaction, category: category, kind: catalog.kind(of: category), source: .override)
            }
            let text = [transaction.description, transaction.payee ?? ""].joined(separator: " ")
            if let match = match(text) {
                return CategorizedTransaction(
                    transaction: transaction,
                    category: match.category,
                    kind: catalog.kind(of: match.category),
                    source: match.isUserRule ? .userRule : .builtInRule
                )
            }
            let category = fallbackCategory(for: transaction, account: accountsByID[transaction.accountId])
            return CategorizedTransaction(transaction: transaction, category: category, kind: catalog.kind(of: category), source: .fallback)
        }

        matchTransfers(&results, accounts: accountsByID)
        return results
    }

    private func fallbackCategory(for transaction: Transaction, account: BankAccount?) -> String {
        if transaction.amount > 0 && account?.kind == .cash {
            return SpendingCategory.otherIncome
        }
        return SpendingCategory.uncategorized
    }

    /// Pairs unexplained money leaving one account with the same amount arriving in another
    /// within a few days, e.g. "-$1,204.18 WF checking" and "+$1,204.18 Amex". Those are card
    /// payments or transfers, not spending and income.
    /// One side may already be labeled by a rule (the card's "PAYMENT RECEIVED") while the other
    /// isn't ("ACH DEBIT AMERICAN EXPRESS"); only the unlabeled side is changed.
    private func matchTransfers(_ results: inout [CategorizedTransaction], accounts: [String: BankAccount]) {
        let candidates = results.indices.filter { index in
            let result = results[index]
            guard result.transaction.amount != 0 else { return false }
            return result.source == .fallback || (result.source == .builtInRule && result.kind == .transfer)
        }
        var inflowsByAmount: [Decimal: [Int]] = [:]
        for index in candidates where results[index].transaction.amount > 0 {
            inflowsByAmount[results[index].transaction.amount, default: []].append(index)
        }

        var used = Set<Int>()
        let outflows = candidates
            .filter { results[$0].transaction.amount < 0 }
            .sorted { results[$0].transaction.date < results[$1].transaction.date }

        for out in outflows {
            let outTx = results[out].transaction
            let outIsFallback = results[out].source == .fallback
            let options = (inflowsByAmount[-outTx.amount] ?? []).filter { index in
                let inTx = results[index].transaction
                return !used.contains(index)
                    && (outIsFallback || results[index].source == .fallback)
                    && inTx.accountId != outTx.accountId
                    && abs(inTx.date.timeIntervalSince(outTx.date)) <= Self.transferWindow
            }
            guard let match = options.min(by: {
                abs(results[$0].transaction.date.timeIntervalSince(outTx.date)) < abs(results[$1].transaction.date.timeIntervalSince(outTx.date))
            }) else { continue }

            let category: String
            if let labeled = [out, match].first(where: { results[$0].source != .fallback }) {
                category = results[labeled].category
            } else {
                let kinds = [accounts[outTx.accountId]?.kind, accounts[results[match].transaction.accountId]?.kind]
                if kinds.contains(.creditCard) || kinds.contains(.loan) {
                    category = SpendingCategory.cardPayment
                } else if kinds.contains(.investment) {
                    category = "Investment Transfer"
                } else {
                    category = SpendingCategory.transfer
                }
            }
            for index in [out, match] where results[index].source == .fallback {
                results[index].category = category
                results[index].kind = .transfer
                results[index].source = .matchedTransfer
            }
            used.insert(match)
        }
    }
}
