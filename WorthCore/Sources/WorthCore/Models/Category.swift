import Foundation

public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    /// Counts toward spending. Refunds in these categories reduce spending.
    case expense
    case income
    /// Moving your own money around (card payments, transfers, brokerage deposits). Ignored in reports.
    case transfer
}

public struct SpendingCategory: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var kind: CategoryKind
    public var symbolName: String

    public var id: String { name }

    public init(name: String, kind: CategoryKind, symbolName: String = "tag") {
        self.name = name
        self.kind = kind
        self.symbolName = symbolName
    }
}

extension SpendingCategory {
    public static let uncategorized = "Uncategorized"
    public static let otherIncome = "Other Income"
    public static let transfer = "Transfer"
    public static let cardPayment = "Credit Card Payment"

    public static let builtIn: [SpendingCategory] = [
        .init(name: "Groceries", kind: .expense, symbolName: "cart"),
        .init(name: "Dining", kind: .expense, symbolName: "fork.knife"),
        .init(name: "Shopping", kind: .expense, symbolName: "bag"),
        .init(name: "Transportation", kind: .expense, symbolName: "car"),
        .init(name: "Travel", kind: .expense, symbolName: "airplane"),
        .init(name: "Housing", kind: .expense, symbolName: "house"),
        .init(name: "Utilities", kind: .expense, symbolName: "bolt"),
        .init(name: "Subscriptions", kind: .expense, symbolName: "repeat"),
        .init(name: "Entertainment", kind: .expense, symbolName: "ticket"),
        .init(name: "Health & Fitness", kind: .expense, symbolName: "heart"),
        .init(name: "Personal Care", kind: .expense, symbolName: "scissors"),
        .init(name: "Education", kind: .expense, symbolName: "book"),
        .init(name: "Gifts & Donations", kind: .expense, symbolName: "gift"),
        .init(name: "Insurance", kind: .expense, symbolName: "shield"),
        .init(name: "Taxes", kind: .expense, symbolName: "building.columns"),
        .init(name: "Fees & Interest", kind: .expense, symbolName: "exclamationmark.triangle"),
        .init(name: "Pets", kind: .expense, symbolName: "pawprint"),
        .init(name: "Venmo & Zelle", kind: .expense, symbolName: "arrow.left.arrow.right"),
        .init(name: "Cash & ATM", kind: .expense, symbolName: "banknote"),
        .init(name: "Business", kind: .expense, symbolName: "briefcase"),
        .init(name: "Other", kind: .expense, symbolName: "square.grid.2x2"),
        .init(name: uncategorized, kind: .expense, symbolName: "questionmark.circle"),
        .init(name: "Paycheck", kind: .income, symbolName: "dollarsign.circle"),
        .init(name: "Interest & Dividends", kind: .income, symbolName: "percent"),
        .init(name: "Deal Income", kind: .income, symbolName: "building.2"),
        .init(name: otherIncome, kind: .income, symbolName: "plus.circle"),
        .init(name: cardPayment, kind: .transfer, symbolName: "creditcard"),
        .init(name: transfer, kind: .transfer, symbolName: "arrow.left.arrow.right.circle"),
        .init(name: "Investment Transfer", kind: .transfer, symbolName: "chart.line.uptrend.xyaxis"),
    ]
}

/// Built-in categories plus any the user created.
public struct CategoryCatalog: Sendable {
    public let all: [SpendingCategory]
    private let byName: [String: SpendingCategory]

    public init(custom: [SpendingCategory] = []) {
        var seen = Set<String>()
        var list: [SpendingCategory] = []
        for category in SpendingCategory.builtIn + custom where seen.insert(category.name.lowercased()).inserted {
            list.append(category)
        }
        all = list
        byName = Dictionary(list.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func category(named name: String) -> SpendingCategory {
        byName[name.lowercased()] ?? SpendingCategory(name: name, kind: .expense)
    }

    public func kind(of name: String) -> CategoryKind { category(named: name).kind }
}
