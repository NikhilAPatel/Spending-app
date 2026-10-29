import Foundation

public struct MonthKey: Hashable, Comparable, Sendable, Identifiable {
    public var year: Int
    public var month: Int

    public var id: String { "\(year)-\(month)" }

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1)
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public func start(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    public func adding(months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        return MonthKey(year: index / 12, month: index % 12 + 1)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        MonthKey(date, calendar: calendar) == self
    }
}

public struct CategoryTotal: Identifiable, Hashable, Sendable {
    public var category: SpendingCategory
    public var amount: Decimal
    public var count: Int

    public var id: String { category.name }
}

public struct MonthlySummary: Identifiable, Sendable {
    public var month: MonthKey
    /// Purchases minus refunds, as a positive number.
    public var spending: Decimal
    public var income: Decimal
    /// Expense categories with a net positive total, largest first.
    public var categories: [CategoryTotal]
    public var incomeCategories: [CategoryTotal]
    public var transactions: [CategorizedTransaction]

    public var id: MonthKey { month }
    public var net: Decimal { income - spending }
}

public enum SpendingReport {
    /// - Parameter accountIDs: accounts whose transactions count (the user's "include in spending" set).
    public static func summary(
        for month: MonthKey,
        transactions: [CategorizedTransaction],
        accountIDs: Set<String>,
        catalog: CategoryCatalog,
        calendar: Calendar = .current
    ) -> MonthlySummary {
        let inMonth = transactions.filter {
            accountIDs.contains($0.transaction.accountId) && month.contains($0.transaction.date, calendar: calendar)
        }

        var expense: [String: (Decimal, Int)] = [:]
        var income: [String: (Decimal, Int)] = [:]
        for item in inMonth {
            switch item.kind {
            case .expense:
                let current = expense[item.category] ?? (0, 0)
                expense[item.category] = (current.0 + item.spendingAmount, current.1 + 1)
            case .income:
                let current = income[item.category] ?? (0, 0)
                income[item.category] = (current.0 + item.incomeAmount, current.1 + 1)
            case .transfer:
                continue
            }
        }

        func totals(_ map: [String: (Decimal, Int)]) -> [CategoryTotal] {
            map.map { CategoryTotal(category: catalog.category(named: $0.key), amount: $0.value.0, count: $0.value.1) }
                .filter { $0.amount > 0 }
                .sorted { $0.amount > $1.amount }
        }

        let expenseTotals = totals(expense)
        let incomeTotals = totals(income)
        return MonthlySummary(
            month: month,
            spending: expense.values.reduce(0) { $0 + $1.0 },
            income: income.values.reduce(0) { $0 + $1.0 },
            categories: expenseTotals,
            incomeCategories: incomeTotals,
            transactions: inMonth.sorted { $0.transaction.date > $1.transaction.date }
        )
    }

    /// Summaries for the `count` months ending with `last`, oldest first.
    public static func trend(
        endingAt last: MonthKey,
        count: Int,
        transactions: [CategorizedTransaction],
        accountIDs: Set<String>,
        catalog: CategoryCatalog,
        calendar: Calendar = .current
    ) -> [MonthlySummary] {
        (0..<count).reversed().map { offset in
            summary(for: last.adding(months: -offset), transactions: transactions, accountIDs: accountIDs, catalog: catalog, calendar: calendar)
        }
    }
}
