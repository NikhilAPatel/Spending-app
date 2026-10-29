import Foundation

public struct NetWorthLine: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case bank(String)
        case wallet(UUID)
        case manual(UUID)
    }

    public var source: Source
    public var name: String
    public var detail: String
    public var group: AssetGroup
    public var value: Decimal
    public var asOf: Date?

    public var id: Source { source }
}

public struct NetWorthBreakdown: Sendable {
    public var lines: [NetWorthLine]

    public var total: Decimal { lines.reduce(0) { $0 + $1.value } }
    public var assets: Decimal { lines.filter { $0.value > 0 }.reduce(0) { $0 + $1.value } }
    public var liabilities: Decimal { lines.filter { $0.value < 0 }.reduce(0) { $0 - $1.value } }

    public func total(for group: AssetGroup) -> Decimal {
        lines.filter { $0.group == group }.reduce(0) { $0 + $1.value }
    }

    public func lines(in group: AssetGroup) -> [NetWorthLine] {
        lines.filter { $0.group == group }.sorted { abs($0.value) > abs($1.value) }
    }

    /// Groups that have at least one line, in display order.
    public var groups: [AssetGroup] {
        AssetGroup.allCases.filter { group in lines.contains { $0.group == group } }
    }
}

public enum NetWorthCalculator {
    public static func breakdown(accounts: [BankAccount], wallets: [CryptoWallet], manualAssets: [ManualAsset]) -> NetWorthBreakdown {
        var lines: [NetWorthLine] = []

        for account in accounts where account.includeInNetWorth {
            let value = account.netWorthValue
            let group: AssetGroup = switch account.kind {
            case .cash: .cash
            case .investment: .investments
            case .creditCard, .loan: .debt
            case .other: value < 0 ? .debt : .otherAssets
            }
            lines.append(NetWorthLine(source: .bank(account.id), name: account.displayName, detail: account.institution, group: group, value: value, asOf: account.balanceDate))
        }

        for wallet in wallets {
            lines.append(NetWorthLine(source: .wallet(wallet.id), name: wallet.label, detail: wallet.source.displayName, group: .crypto, value: wallet.totalUSD, asOf: wallet.lastUpdated))
        }

        for asset in manualAssets {
            let group: AssetGroup = switch asset.kind {
            case .privateCompany, .stockPlan: .investments
            case .art, .realEstate, .vehicle, .otherAsset: .otherAssets
            case .cash: .cash
            case .cryptoHolding: .crypto
            case .loan, .otherDebt: .debt
            }
            lines.append(NetWorthLine(source: .manual(asset.id), name: asset.name, detail: asset.kind.displayName, group: group, value: asset.netWorthValue, asOf: asset.updatedAt))
        }

        return NetWorthBreakdown(lines: lines)
    }

    /// Replaces today's snapshot (if any) so the chart gets one point per day.
    public static func recording(_ breakdown: NetWorthBreakdown, at date: Date, into snapshots: [NetWorthSnapshot], calendar: Calendar = .current) -> [NetWorthSnapshot] {
        let day = calendar.startOfDay(for: date)
        var byGroup: [String: Decimal] = [:]
        for group in AssetGroup.allCases {
            byGroup[group.rawValue] = breakdown.total(for: group)
        }
        var result = snapshots.filter { !calendar.isDate($0.date, inSameDayAs: day) }
        result.append(NetWorthSnapshot(date: day, total: breakdown.total, byGroup: byGroup))
        result.sort { $0.date < $1.date }
        return result
    }
}
