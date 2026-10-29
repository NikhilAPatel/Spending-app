import SwiftUI
import WorthCore

struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case uncategorized = "Uncategorized"
        case spending = "Spending"
        case income = "Income"
        case transfers = "Transfers"

        var id: String { rawValue }
    }

    private var items: [CategorizedTransaction] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.categorized.filter { item in
            switch filter {
            case .all: break
            case .uncategorized: guard item.category == SpendingCategory.uncategorized else { return false }
            case .spending: guard item.kind == .expense else { return false }
            case .income: guard item.kind == .income else { return false }
            case .transfers: guard item.kind == .transfer else { return false }
            }
            guard !query.isEmpty else { return true }
            return item.transaction.description.lowercased().contains(query)
                || (item.transaction.payee?.lowercased().contains(query) ?? false)
                || item.category.lowercased().contains(query)
        }
        .sorted { $0.transaction.date > $1.transaction.date }
    }

    var body: some View {
        let visible = items
        let days = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.transaction.date) }
        let sortedDays = days.keys.sorted(by: >)

        NavigationStack {
            List {
                ForEach(sortedDays, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(days[day] ?? []) { item in
                            NavigationLink(value: item.id) {
                                TransactionRow(item: item, accountName: model.account(id: item.transaction.accountId)?.displayName)
                            }
                        }
                    }
                }
            }
            .overlay {
                if visible.isEmpty {
                    if model.data.transactions.isEmpty {
                        ContentUnavailableView("No transactions yet", systemImage: "list.bullet.rectangle", description: Text("Connect SimpleFIN in the Accounts tab."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Merchant or category")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter")
                }
            }
            .navigationTitle(filter == .all ? "Transactions" : filter.rawValue)
            .navigationDestination(for: String.self) { id in
                TransactionDetailView(transactionID: id)
            }
            .refreshable { await model.refresh() }
        }
    }
}

struct TransactionRow: View {
    let item: CategorizedTransaction
    let accountName: String?

    var body: some View {
        let amount = item.transaction.amount
        HStack(spacing: 12) {
            Image(systemName: SpendingCategory.builtIn.first { $0.name == item.category }?.symbolName ?? "tag")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.transaction.displayName)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.category)
                    if let accountName {
                        Text("·")
                        Text(accountName).lineLimit(1)
                    }
                    if item.transaction.isPending {
                        Text("· Pending").italic()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount > 0 ? "+\(Format.currency(amount, cents: true))" : Format.currency(-amount, cents: true))
                .monospacedDigit()
                .foregroundStyle(item.kind == .transfer ? Color.secondary : (amount > 0 ? Color.gain : Color.primary))
        }
    }
}

struct TransactionDetailView: View {
    @Environment(AppModel.self) private var model
    let transactionID: String

    var body: some View {
        if let item = model.categorized.first(where: { $0.id == transactionID }) {
            let tx = item.transaction
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tx.displayName).font(.headline)
                        Text(tx.amount > 0 ? "+\(Format.currency(tx.amount, cents: true))" : Format.currency(-tx.amount, cents: true))
                            .font(.system(size: 34, weight: .semibold))
                        Text(tx.date.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        if tx.isPending {
                            Label("Pending", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink {
                        CategoryPickerView(transaction: tx, current: item.category)
                    } label: {
                        LabeledContent("Category", value: item.category)
                    }
                    if item.source == .override {
                        Button("Go back to automatic category") {
                            model.clearOverride(for: tx)
                        }
                    }
                } footer: {
                    Text(sourceDescription(item))
                }

                Section("Details") {
                    if let account = model.account(id: tx.accountId) {
                        LabeledContent("Account", value: "\(account.institution) · \(account.displayName)")
                    }
                    LabeledContent("Bank description") {
                        Text(tx.description).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                    if let memo = tx.memo, !memo.isEmpty {
                        LabeledContent("Memo", value: memo)
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Transaction not found", systemImage: "questionmark.circle", description: Text("It may have been removed by your bank."))
        }
    }

    private func sourceDescription(_ item: CategorizedTransaction) -> String {
        switch item.source {
        case .override: "You set this category for this transaction."
        case .userRule: "Set by one of your rules."
        case .builtInRule: "Recognized from the merchant name."
        case .matchedTransfer: "Matched with the same amount moving between two of your accounts, so it isn't counted as spending or income."
        case .fallback: "Not recognized. Pick a category, and optionally apply it to every transaction from this merchant."
        }
    }
}

struct CategoryPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: BankTransaction
    let current: String

    @State private var applyToSimilar = true
    @State private var pattern: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""

    init(transaction: BankTransaction, current: String) {
        self.transaction = transaction
        self.current = current
        _pattern = State(initialValue: AppModel.suggestedPattern(for: transaction))
    }

    var body: some View {
        List {
            Section {
                Toggle("Apply to matching transactions", isOn: $applyToSimilar)
                if applyToSimilar {
                    TextField("Text to match", text: $pattern)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            } footer: {
                Text(applyToSimilar
                    ? "Every transaction whose description contains \"\(pattern)\" gets this category, including future ones."
                    : "Only this transaction changes.")
            }

            ForEach(CategoryKind.allCases, id: \.self) { kind in
                Section(kind.title) {
                    ForEach(model.catalog.all.filter { $0.kind == kind }) { category in
                        Button {
                            choose(category.name)
                        } label: {
                            HStack {
                                Label(category.name, systemImage: category.symbolName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if category.name == current {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button("New category…") { showingNewCategory = true }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New category", isPresented: $showingNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Add as spending") { addCategory(kind: .expense) }
            Button("Add as income") { addCategory(kind: .income) }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
    }

    private func addCategory(kind: CategoryKind) {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCategoryName = ""
        guard !name.isEmpty else { return }
        model.addCustomCategory(name: name, kind: kind)
        choose(model.catalog.category(named: name).name)
    }

    private func choose(_ category: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        model.setCategory(category, for: transaction, rulePattern: applyToSimilar && !trimmed.isEmpty ? trimmed : nil)
        dismiss()
    }
}
