import Charts
import SwiftUI
import WorthCore

struct SpendingView: View {
    @Environment(AppModel.self) private var model
    @State private var month: MonthKey?

    var body: some View {
        let current = model.currentMonth
        let selected = month ?? current
        let summary = model.summary(for: selected)
        let trend = model.trend(endingAt: current, count: 6)

        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: selected, canGoForward: selected < current) { month = $0 }
                        .padding(.vertical, 2)
                    SpendingTotals(summary: summary)
                }

                if model.data.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No bank data yet", systemImage: "creditcard")
                    } description: {
                        Text("Connect SimpleFIN in the Accounts tab to see where your money goes.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Last 6 months") {
                        SpendingTrendChart(trend: trend, selected: selected) { month = $0 }
                            .frame(height: 170)
                            .padding(.vertical, 8)
                    }

                    Section {
                        if summary.categories.isEmpty {
                            Text("No spending recorded this month.").foregroundStyle(.secondary)
                        }
                        let largest = summary.categories.first?.amount ?? 1
                        ForEach(summary.categories) { total in
                            NavigationLink {
                                CategoryTransactionsView(category: total.category.name, month: selected)
                            } label: {
                                CategoryBarRow(total: total, largest: largest)
                            }
                        }
                    } header: {
                        Text("Where it went")
                    } footer: {
                        Text("Card payments and transfers between your accounts aren't counted. Tap a category to fix anything that's misfiled.")
                    }

                    if !summary.incomeCategories.isEmpty {
                        Section("Money in") {
                            ForEach(summary.incomeCategories) { total in
                                NavigationLink {
                                    CategoryTransactionsView(category: total.category.name, month: selected)
                                } label: {
                                    HStack {
                                        Label(total.category.name, systemImage: total.category.symbolName)
                                        Spacer()
                                        Text(Format.currency(total.amount)).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Spending")
            .refreshable { await model.refresh() }
        }
    }
}

struct MonthSwitcher: View {
    let month: MonthKey
    let canGoForward: Bool
    let onStep: (MonthKey) -> Void

    var body: some View {
        HStack {
            Button {
                onStep(month.adding(months: -1))
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month.start().formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                onStep(month.adding(months: 1))
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
    }
}

struct SpendingTotals: View {
    let summary: MonthlySummary

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent").font(.caption).foregroundStyle(.secondary)
                Text(Format.currency(summary.spending))
                    .font(.system(size: 34, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Income").font(.caption).foregroundStyle(.secondary)
                    Text(Format.currency(summary.income)).font(.subheadline.weight(.medium))
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Net").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Image(systemName: summary.net >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(Format.signedCurrency(summary.net))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(summary.net >= 0 ? Color.gain : Color.loss)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Monthly spending columns; the selected month is highlighted and labeled, the rest stay gray.
struct SpendingTrendChart: View {
    let trend: [MonthlySummary]
    let selected: MonthKey
    let onSelect: (MonthKey) -> Void
    @State private var selection: Date?

    var body: some View {
        Chart(trend) { item in
            let isSelected = item.month == selected
            BarMark(
                x: .value("Month", item.month.start(), unit: .month),
                y: .value("Spent", item.spending.doubleValue),
                width: .fixed(22)
            )
            .foregroundStyle(isSelected ? Color.chartAccent : Color.chartMuted)
            .cornerRadius(4)
            .annotation(position: .top, spacing: 4) {
                if isSelected {
                    Text(Format.compactCurrency(item.spending.doubleValue))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(item.month.start().formatted(.dateTime.month(.wide).year()))
            .accessibilityValue(Format.currency(item.spending))
        }
        .chartXSelection(value: $selection)
        .onChange(of: selection) { _, date in
            if let date { onSelect(MonthKey(date)) }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Format.compactCurrency(amount))
                    }
                }
            }
        }
    }
}

/// A category with a bar sized against the month's largest category.
struct CategoryBarRow: View {
    let total: CategoryTotal
    let largest: Decimal

    var body: some View {
        let fraction = largest > 0 ? min(max((total.amount / largest).doubleValue, 0), 1) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(total.category.name, systemImage: total.category.symbolName)
                    .foregroundStyle(.primary)
                Spacer()
                Text(Format.currency(total.amount))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.chartAccentTrack.opacity(0.5))
                        Capsule().fill(Color.chartAccent)
                            .frame(width: max(proxy.size.width * fraction, 4))
                    }
                }
                .frame(height: 6)
                Text("\(total.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct CategoryTransactionsView: View {
    @Environment(AppModel.self) private var model
    let category: String
    let month: MonthKey

    var body: some View {
        let items = model.summary(for: month).transactions.filter { $0.category == category }
        List {
            ForEach(items) { item in
                NavigationLink {
                    TransactionDetailView(transactionID: item.id)
                } label: {
                    TransactionRow(item: item, accountName: model.account(id: item.transaction.accountId)?.displayName)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray", description: Text("No \(category) transactions this month."))
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
    }
}
