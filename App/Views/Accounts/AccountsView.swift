import SwiftUI
import WorthCore

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingConnect = false
    @State private var showingAddWallet = false
    @State private var showingAddAsset = false
    @State private var confirmingDisconnect = false
    @State private var confirmingErase = false

    var body: some View {
        let accountsByInstitution = Dictionary(grouping: model.data.accounts, by: \.institution)

        NavigationStack {
            List {
                Section {
                    if model.data.simpleFINConnected {
                        LabeledContent("SimpleFIN") {
                            if let last = model.data.lastSimpleFINSync {
                                Text("Synced \(Format.relative(last))")
                            } else {
                                Text("Connected")
                            }
                        }
                        ForEach(Array(model.data.simpleFINMessages.enumerated()), id: \.offset) { _, message in
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .symbolRenderingMode(.multicolor)
                        }
                    } else {
                        Button {
                            showingConnect = true
                        } label: {
                            Label("Connect banks with SimpleFIN", systemImage: "link")
                        }
                    }
                } header: {
                    Text("Banks & cards")
                } footer: {
                    if !model.data.simpleFINConnected {
                        Text("Links Wells Fargo, Chase, Amex, Robinhood and more through SimpleFIN Bridge ($15/yr). Read-only: it can't move money.")
                    }
                }

                ForEach(accountsByInstitution.keys.sorted(), id: \.self) { institution in
                    Section(institution) {
                        ForEach(accountsByInstitution[institution] ?? []) { account in
                            NavigationLink {
                                BankAccountDetailView(accountID: account.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.displayName)
                                        Text(account.kind.displayName + (account.includeInNetWorth ? "" : " · hidden"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.currency(account.netWorthValue)).monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(model.data.wallets) { wallet in
                        NavigationLink {
                            WalletDetailView(walletID: wallet.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wallet.label)
                                    Text(wallet.source.usesAddress ? "\(wallet.source.displayName) · \(wallet.shortAddress)" : wallet.source.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if wallet.lastError != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Last update failed")
                                }
                                Text(Format.currency(wallet.totalUSD)).monospacedDigit()
                            }
                        }
                    }
                    Button {
                        showingAddWallet = true
                    } label: {
                        Label("Add wallet or exchange", systemImage: "plus")
                    }
                } header: {
                    Text("Crypto")
                } footer: {
                    Text("Wallets are read from their public address; your keys never leave your wallet.")
                }

                Section {
                    ForEach(model.data.manualAssets) { asset in
                        NavigationLink {
                            ManualAssetEditor(assetID: asset.id)
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(asset.name)
                                        Text("Updated \(asset.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: asset.kind.symbolName).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Format.currency(asset.netWorthValue)).monospacedDigit()
                            }
                        }
                    }
                    Button {
                        showingAddAsset = true
                    } label: {
                        Label("Add asset or debt", systemImage: "plus")
                    }
                } header: {
                    Text("Entered by hand")
                } footer: {
                    Text("Private deals, stock plans, art, property, loans: anything without a connection. Update the value when it changes.")
                }

                Section("Categories") {
                    NavigationLink {
                        RulesView()
                    } label: {
                        LabeledContent("Category rules", value: "\(model.data.rules.count)")
                    }
                }

                Section {
                    Toggle("Require Face ID", isOn: Binding(
                        get: { model.data.requireFaceID },
                        set: { model.setRequireFaceID($0) }
                    ))
                    NavigationLink("Optional API keys") {
                        APIKeysView()
                    }
                } header: {
                    Text("Security & settings")
                }

                Section {
                    if model.data.simpleFINConnected {
                        Button("Disconnect SimpleFIN", role: .destructive) {
                            confirmingDisconnect = true
                        }
                    }
                    Button("Erase all data", role: .destructive) {
                        confirmingErase = true
                    }
                }
            }
            .navigationTitle("Accounts")
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showingConnect) {
                ConnectSimpleFINView()
            }
            .sheet(isPresented: $showingAddWallet) {
                AddWalletView()
            }
            .sheet(isPresented: $showingAddAsset) {
                NavigationStack {
                    ManualAssetEditor(assetID: nil)
                }
            }
            .confirmationDialog("Disconnect SimpleFIN?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { model.disconnectSimpleFIN() }
            } message: {
                Text("Worth forgets its SimpleFIN access. Your accounts and history stay until you remove them. To reconnect you'll need a new setup token.")
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { model.eraseAllData() }
            } message: {
                Text("Deletes all accounts, transactions, wallets, assets, rules and stored keys from this phone. Your SimpleFIN Bridge account isn't affected.")
            }
        }
    }
}

struct APIKeysView: View {
    @Environment(AppModel.self) private var model
    @State private var ethplorer = ""
    @State private var jupiter = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("Ethplorer API key", text: $ethplorer)
            } footer: {
                Text("Ethereum balances use Ethplorer's free public key by default. If you hit rate limits, get a free personal key at ethplorer.io.")
            }
            Section {
                SecureField("Jupiter API key", text: $jupiter)
            } footer: {
                Text("Prices for Solana tokens other than SOL, USDC and USDT come from Jupiter. Add a key from portal.jup.ag if prices stop showing up.")
            }
            Section {
                Button(saved ? "Saved" : "Save") {
                    model.setOptionalAPIKey(ethplorer, for: CryptoSecretKey.ethplorerAPIKey)
                    model.setOptionalAPIKey(jupiter, for: CryptoSecretKey.jupiterAPIKey)
                    saved = true
                }
                .disabled(saved)
            }
        }
        .navigationTitle("API keys")
        .onAppear {
            ethplorer = model.secrets.secret(for: CryptoSecretKey.ethplorerAPIKey) ?? ""
            jupiter = model.secrets.secret(for: CryptoSecretKey.jupiterAPIKey) ?? ""
        }
        .onChange(of: ethplorer) { saved = false }
        .onChange(of: jupiter) { saved = false }
    }
}
