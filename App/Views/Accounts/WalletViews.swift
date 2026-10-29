import SwiftUI
import WorthCore

struct AddWalletView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var source: CryptoSource = .bitcoin
    @State private var label = ""
    @State private var address = ""
    @State private var apiKey = ""
    @State private var privateKey = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var canAdd: Bool {
        if isAdding { return false }
        if source.usesAddress { return !address.trimmingCharacters(in: .whitespaces).isEmpty }
        return !apiKey.isEmpty && !privateKey.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $source) {
                        ForEach(CryptoSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    TextField("Name (optional)", text: $label, prompt: Text(source == .kraken ? "Kraken" : "e.g. Ledger, Phantom"))
                }

                if source.usesAddress {
                    Section {
                        TextField(source.addressPrompt, text: $address, axis: .vertical)
                            .font(.footnote.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        PasteButton(payloadType: String.self) { strings in
                            address = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        }
                    } header: {
                        Text("Public address")
                    } footer: {
                        Text(help(for: source))
                    }
                } else {
                    Section {
                        SecureField("API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Private key", text: $privateKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Kraken API key")
                    } footer: {
                        Text("On kraken.com go to Settings → API → Create API key and tick only \"Query Funds\". That key can see balances but can't trade or withdraw. Both keys are stored in your phone's keychain.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.loss)
                    }
                }
            }
            .navigationTitle("Add crypto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await add() } }
                            .disabled(!canAdd)
                    }
                }
            }
            .onChange(of: source) { errorMessage = nil }
            .interactiveDismissDisabled(isAdding)
        }
    }

    private func help(for source: CryptoSource) -> String {
        switch source {
        case .bitcoin:
            "Paste a receiving address, or your wallet's xpub to include every address it has used. Add one entry per address if your wallet only shows a zpub."
        case .ethereum:
            "Includes ETH and tokens with a known price. Tokens on other networks (Base, Arbitrum…) aren't included yet."
        case .solana:
            "Includes SOL and tokens. Natively staked SOL isn't included; add it under \"Entered by hand\" as a coin amount."
        case .hyperliquid:
            "Your Hyperliquid (EVM) address. Includes perps account value, spot tokens, staked HYPE and vault deposits."
        case .kraken:
            ""
        }
    }

    private func add() async {
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            if source.usesAddress {
                try await model.addWallet(source: source, label: label, address: address)
            } else {
                try await model.addKrakenAccount(label: label, apiKey: apiKey, privateKey: privateKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WalletDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let walletID: UUID
    @State private var confirmingRemove = false
    @State private var newLabel = ""
    @State private var renaming = false

    var body: some View {
        if let wallet = model.data.wallets.first(where: { $0.id == walletID }) {
            let priced = wallet.holdings.filter { $0.valueUSD != nil }
            let unpriced = wallet.unpricedHoldings

            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wallet.source.displayName).font(.subheadline).foregroundStyle(.secondary)
                        Text(Format.currency(wallet.totalUSD)).font(.system(size: 34, weight: .semibold))
                        if let updated = wallet.lastUpdated {
                            Text("Updated \(Format.relative(updated))").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if let error = wallet.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .symbolRenderingMode(.multicolor)
                    }
                }

                if !priced.isEmpty {
                    Section("Holdings") {
                        ForEach(priced) { holding in
                            HoldingRow(holding: holding)
                        }
                    }
                }

                if !unpriced.isEmpty {
                    Section {
                        ForEach(unpriced) { holding in
                            HoldingRow(holding: holding)
                        }
                    } header: {
                        Text("No price found")
                    } footer: {
                        Text("Counted as $0. Often these are spam tokens airdropped to your address.")
                    }
                }

                if wallet.source.usesAddress {
                    Section("Address") {
                        Text(wallet.address)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button("Rename") {
                        newLabel = wallet.label
                        renaming = true
                    }
                    Button("Remove", role: .destructive) {
                        confirmingRemove = true
                    }
                }
            }
            .navigationTitle(wallet.label)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .alert("Rename", isPresented: $renaming) {
                TextField("Name", text: $newLabel)
                Button("Save") { model.renameWallet(id: walletID, to: newLabel) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Remove \(wallet.label)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.removeWallet(id: walletID)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Wallet removed", systemImage: "trash")
        }
    }
}

private struct HoldingRow: View {
    let holding: CryptoHolding

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                Text([holding.name, holding.fixedValueUSD == nil ? Format.quantity(holding.quantity) : nil]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let value = holding.valueUSD {
                    Text(Format.currency(value, cents: value < 100)).monospacedDigit()
                }
                if let price = holding.priceUSD, holding.fixedValueUSD == nil {
                    Text("@ \(Format.currency(price, cents: true))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
