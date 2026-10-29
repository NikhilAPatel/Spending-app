import Charts
import SwiftUI
import WorthCore

struct NetWorthView: View {
    @Environment(AppModel.self) private var model
    @State private var range: ChartRange = .threeMonths

    var body: some View {
        let breakdown = model.netWorth
        NavigationStack {
            List {
                if model.hasAnyData {
                    Section {
                        NetWorthHeader(breakdown: breakdown, snapshots: model.data.snapshots, range: $range)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nothing connected yet", systemImage: "building.columns")
                    } description: {
                        Text("Go to the Accounts tab to connect your banks through SimpleFIN, add crypto wallets, or enter assets like private deals and art.")
                    }
                    .listRowBackground(Color.clear)
                }

                RefreshStatusSection()

                ForEach(breakdown.groups) { group in
                    Section {
                        ForEach(breakdown.lines(in: group)) { line in
                            NavigationLink(value: line.source) {
                                NetWorthLineRow(line: line)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.displayName)
                            Spacer()
                            Text(Format.currency(breakdown.total(for: group)))
                        }
                    }
                }
            }
            .navigationTitle("Net Worth")
            .refreshable { await model.refresh() }
            .navigationDestination(for: NetWorthLine.Source.self) { source in
                switch source {
                case let .bank(id): BankAccountDetailView(accountID: id)
                case let .wallet(id): WalletDetailView(walletID: id)
                case let .manual(id): ManualAssetEditor(assetID: id)
                }
            }
        }
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var periodLabel: String {
        switch self {
        case .month: "past month"
        case .threeMonths: "past 3 months"
        case .year: "past year"
        case .all: "all time"
        }
    }

    func filter(_ snapshots: [NetWorthSnapshot], now: Date = Date()) -> [NetWorthSnapshot] {
        let days: Double? = switch self {
        case .month: 31
        case .threeMonths: 92
        case .year: 366
        case .all: nil
        }
        guard let days else { return snapshots }
        let cutoff = now.addingTimeInterval(-days * 86_400)
        return snapshots.filter { $0.date >= cutoff }
    }
}

struct NetWorthHeader: View {
    let breakdown: NetWorthBreakdown
    let snapshots: [NetWorthSnapshot]
    @Binding var range: ChartRange
    @State private var selectedDate: Date?

    var body: some View {
        let points = range.filter(snapshots)
        let selected = selectedDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let value = selected?.total ?? breakdown.total
        let change = points.first.map { value - $0.total }

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Net worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Format.currency(value))
                    .font(.system(size: 44, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if let change, points.count >= 2 {
                    DeltaLabel(change: change, period: range.periodLabel)
                }
            }

            if points.count >= 2 {
                NetWorthChart(points: points, selected: selected, selectedDate: $selectedDate)
                    .frame(height: 180)
            } else {
                Text("The chart fills in as Worth records your net worth each day you open it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                LabeledValue(title: "Assets", value: breakdown.assets)
                Spacer()
                LabeledValue(title: "Debts", value: breakdown.liabilities)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct LabeledValue: View {
    let title: String
    let value: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.currency(value)).font(.subheadline.weight(.medium))
        }
    }
}

/// One series, so no legend: the header names it. Drag to read past values.
struct NetWorthChart: View {
    let points: [NetWorthSnapshot]
    let selected: NetWorthSnapshot?
    @Binding var selectedDate: Date?

    var body: some View {
        let values = points.map { $0.total.doubleValue }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.1, abs(high) * 0.01, 1)
        let floor = low - padding
        let ceiling = high + padding
        let ringColor = Color(.secondarySystemGroupedBackground)

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", floor),
                    yEnd: .value("Net worth", point.total.doubleValue)
                )
                .foregroundStyle(Color.chartAccent.opacity(0.1))
                .interpolationMethod(.monotone)

                LineMark(x: .value("Date", point.date), y: .value("Net worth", point.total.doubleValue))
                    .foregroundStyle(Color.chartAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }

            if let point = selected ?? points.last {
                if selected != nil {
                    RuleMark(x: .value("Date", point.date))
                        .foregroundStyle(Color.chartMuted)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                PointMark(x: .value("Date", point.date), y: .value("Net worth", point.total.doubleValue))
                    .symbol {
                        Circle()
                            .fill(Color.chartAccent)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(ringColor, lineWidth: 2))
                    }
            }
        }
        .chartYScale(domain: floor...ceiling)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Format.compactCurrency(amount))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .accessibilityLabel("Net worth over time")
    }
}

struct NetWorthLineRow: View {
    let line: NetWorthLine

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                Text(line.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.currency(line.value))
                    .monospacedDigit()
                if let asOf = line.asOf, Date().timeIntervalSince(asOf) > 3 * 86_400 {
                    Text("as of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
