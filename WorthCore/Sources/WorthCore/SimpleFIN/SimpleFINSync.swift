import Foundation

/// Folds a SimpleFIN response into the stored accounts and transactions.
public enum SimpleFINSync {
    public struct Result: Sendable {
        public var accounts: [BankAccount]
        public var transactions: [Transaction]
    }

    /// - Parameter windowStart: the `start-date` that was requested. Stored transactions for a
    ///   returned account on or after it are replaced, so edits and deletions at the bank show up
    ///   and pending charges don't linger once they post (often under a new id).
    public static func merge(
        accounts existingAccounts: [BankAccount],
        transactions existingTransactions: [Transaction],
        with response: SimpleFINAccountSet,
        windowStart: Date?,
        now: Date = Date()
    ) -> Result {
        var accounts = existingAccounts
        var transactions = existingTransactions

        for remote in response.accounts {
            let holdings = remote.holdings.compactMap { holding -> Holding? in
                guard let symbol = holding.symbol ?? holding.description else { return nil }
                return Holding(symbol: symbol, description: holding.description, shares: holding.shares, marketValue: holding.marketValue, costBasis: holding.costBasis)
            }

            if let index = accounts.firstIndex(where: { $0.id == remote.id }) {
                accounts[index].name = remote.name
                accounts[index].institution = remote.institutionName
                accounts[index].currency = remote.currency
                accounts[index].balance = remote.balance
                accounts[index].availableBalance = remote.availableBalance
                accounts[index].balanceDate = remote.balanceDate
                accounts[index].holdings = holdings
            } else {
                let kind = AccountKind.guess(name: remote.name, institution: remote.institutionName, balance: remote.balance, hasHoldings: !holdings.isEmpty)
                accounts.append(BankAccount(
                    id: remote.id,
                    name: remote.name,
                    institution: remote.institutionName,
                    currency: remote.currency,
                    balance: remote.balance,
                    availableBalance: remote.availableBalance,
                    balanceDate: remote.balanceDate,
                    holdings: holdings,
                    kind: kind
                ))
            }

            let fresh = remote.transactions.map { tx in
                Transaction(
                    id: "\(remote.id)|\(tx.id)",
                    accountId: remote.id,
                    date: tx.date(fallback: now),
                    amount: tx.amount,
                    description: tx.description,
                    payee: tx.payee,
                    memo: tx.memo,
                    isPending: tx.pending
                )
            }
            // When a bank connection is failing, SimpleFIN may return the account with no
            // transactions plus an error. Don't let that wipe the history we already have.
            if fresh.isEmpty && !response.errors.isEmpty { continue }

            let freshIDs = Set(fresh.map(\.id))
            let start = windowStart ?? fresh.map(\.date).min() ?? now
            transactions.removeAll { old in
                old.accountId == remote.id && (old.isPending || old.date >= start || freshIDs.contains(old.id))
            }
            transactions.append(contentsOf: fresh)
        }

        transactions.sort { $0.date > $1.date }
        return Result(accounts: accounts, transactions: transactions)
    }
}
