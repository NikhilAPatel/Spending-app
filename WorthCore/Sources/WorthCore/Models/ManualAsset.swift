import Foundation

public enum ManualAssetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case privateCompany
    case stockPlan
    case art
    case realEstate
    case vehicle
    case cash
    case cryptoHolding
    case otherAsset
    case loan
    case otherDebt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .privateCompany: "Private Company / Deal"
        case .stockPlan: "Stock Plan (RSUs, options)"
        case .art: "Art & Collectibles"
        case .realEstate: "Real Estate"
        case .vehicle: "Vehicle"
        case .cash: "Cash"
        case .cryptoHolding: "Crypto (coin + amount)"
        case .otherAsset: "Other Asset"
        case .loan: "Loan"
        case .otherDebt: "Other Debt"
        }
    }

    public var symbolName: String {
        switch self {
        case .privateCompany: "building.2"
        case .stockPlan: "chart.line.uptrend.xyaxis"
        case .art: "paintpalette"
        case .realEstate: "house"
        case .vehicle: "car"
        case .cash: "banknote"
        case .cryptoHolding: "bitcoinsign.circle"
        case .otherAsset: "shippingbox"
        case .loan, .otherDebt: "creditcard"
        }
    }

    public var isLiability: Bool { self == .loan || self == .otherDebt }
}

public struct ValuePoint: Codable, Hashable, Sendable {
    public var date: Date
    public var value: Decimal

    public init(date: Date, value: Decimal) {
        self.date = date
        self.value = value
    }
}

/// Anything SimpleFIN and the wallet integrations can't see: private deals, art, a house, a stock plan.
public struct ManualAsset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ManualAssetKind
    /// Dollar value, always entered as a positive number (debts are subtracted automatically).
    public var value: Decimal
    public var updatedAt: Date
    public var notes: String
    public var history: [ValuePoint]

    /// For `.cryptoHolding`: the coin symbol and amount, priced on every refresh.
    public var symbol: String?
    public var quantity: Decimal?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ManualAssetKind,
        value: Decimal,
        updatedAt: Date = Date(),
        notes: String = "",
        symbol: String? = nil,
        quantity: Decimal? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = abs(value)
        self.updatedAt = updatedAt
        self.notes = notes
        self.history = [ValuePoint(date: updatedAt, value: abs(value))]
        self.symbol = symbol?.uppercased()
        self.quantity = quantity
    }

    public var netWorthValue: Decimal { kind.isLiability ? -abs(value) : abs(value) }

    /// Records a new valuation, keeping one history point per day.
    public mutating func setValue(_ newValue: Decimal, on date: Date = Date(), calendar: Calendar = .current) {
        value = abs(newValue)
        updatedAt = date
        history.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        history.append(ValuePoint(date: date, value: abs(newValue)))
        history.sort { $0.date < $1.date }
    }
}
