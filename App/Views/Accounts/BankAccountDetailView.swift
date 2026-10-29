import SwiftUI
import WorthCore

struct BankAccountDetailView: View {
    @Environment(AppModel.self) private var model
    let accountID: String

    var body: some View {
        if let account = model.account(id: accountID) {
            BankAccountForm(account: account)
        } else {
            ContentUnavailableView("Account removed", systemImage: "trash", description: Text("It comes back on the next sync if it's still linked in SimpleFIN Bridge."))
        }
    }
}

private struct BankAccountForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BankAccount
    /// Edited separately and committed on Return or when leaving, so typing doesn't save per keystroke.
    @State private var nickname: String
    @State private var confirmingRemove = false

    init(account: BankAccount) {
        _draft = State(initialValue: account)
        _nickname = State(initialValue: account.nickname ?? "")
    }

    private func commitNickname() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        let value = trimmed.isEmpty ? nil : trimmed
        if draft.nickname != value { draft.nickname = value }
    }

    var body: some View {
        // Balances come from the live account (a sync may land while this screen is open);
        // the draft only holds the settings being edited.
        let live = model.account(id: draft.id) ?? draft
        let recent = model.categorized
            .filter { $0.transaction.accountId == draft.id }
            .prefix(25)

        Form {
            Section {
                LabeledContent("Balance", value: Format.currency(live.balance, cents: true))
                if let available = live.availableBalance {
                    LabeledContent("Available", value: Format.currency(available, cents: true))
                }
                LabeledContent("As of", value: live.balanceDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Counts toward net worth", value: Format.currency(live.includeInNetWorth ? live.netWorthValue : 0, cents: true))
            } header: {
                Text(live.institution)
            }

            Section {
                TextField("Nickname", text: $nickname, prompt: Text(draft.name))
                    .submitLabel(.done)
                    .onSubmit(commitNickname)
                Picker("Type", selection: $draft.kind) {
                    ForEach(AccountKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Toggle("Include in net worth", isOn: $draft.includeInNetWorth)
                Toggle("Include in spending", isOn: $draft.includeInSpending)
            } footer: {
                Text("Credit cards and loans always count as debt, whichever sign the bank reports. Turn off spending for brokerage accounts so trades aren't counted as purchases.")
            }

            if !live.holdings.isEmpty {
                Section("Holdings") {
                    ForEach(live.holdings, id: \.self) { holding in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holding.symbol)
                                if let shares = holding.shares {
                                    Text("\(Format.quantity(shares)) shares").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let value = holding.marketValue {
                                Text(Format.currency(value)).monospacedDigit()
                            }
                        }
                    }
                }
            }

            if !recent.isEmpty {
                Section("Recent transactions") {
                    ForEach(Array(recent)) { item in
                        NavigationLink {
                            TransactionDetailView(transactionID: item.id)
                        } label: {
                            TransactionRow(item: item, accountName: nil)
                        }
                    }
                }
            }

            Section {
                Button("Remove account", role: .destructive) {
                    confirmingRemove = true
                }
            } footer: {
                Text("Deletes this account and its transactions from Worth. To stop it syncing, unlink it in SimpleFIN Bridge.")
            }
        }
        .navigationTitle(draft.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, updated in
            model.updateAccount(updated)
        }
        .onDisappear(perform: commitNickname)
        .confirmationDialog("Remove \(draft.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeAccount(id: draft.id)
                dismiss()
            }
        }
    }
}
