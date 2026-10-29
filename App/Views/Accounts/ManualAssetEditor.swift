import SwiftUI
import WorthCore

/// Add or edit something entered by hand: a private deal, stock plan, art, property, a loan.
struct ManualAssetEditor: View {
    @Environment(AppModel.self) private var model
    let assetID: UUID?

    var body: some View {
        if let assetID {
            if let asset = model.data.manualAssets.first(where: { $0.id == assetID }) {
                ManualAssetForm(existing: asset)
            } else {
                ContentUnavailableView("Removed", systemImage: "trash")
            }
        } else {
            ManualAssetForm(existing: nil)
        }
    }
}

private struct ManualAssetForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: ManualAsset?

    @State private var name: String
    @State private var kind: ManualAssetKind
    @State private var valueText: String
    @State private var symbol: String
    @State private var quantityText: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var confirmingDelete = false

    init(existing: ManualAsset?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .privateCompany)
        _valueText = State(initialValue: existing.map { "\($0.value)" } ?? "")
        _symbol = State(initialValue: existing?.symbol ?? "")
        _quantityText = State(initialValue: existing?.quantity.map { "\($0)" } ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var value: Decimal? { Self.parse(valueText) }
    private var quantity: Decimal? { Self.parse(quantityText) }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .cryptoHolding {
            return !symbol.trimmingCharacters(in: .whitespaces).isEmpty && quantity != nil
        }
        return value != nil
    }

    /// Accepts "$1,250,000", "1250000" or "1.25e6".
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Decimal(apiString: cleaned)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. Acme Series A, Rothko print"))
                Picker("Type", selection: $kind) {
                    ForEach(ManualAssetKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
            }

            if kind == .cryptoHolding {
                Section {
                    TextField("Coin symbol", text: $symbol, prompt: Text("e.g. SOL, ETH, BTC"))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Amount", text: $quantityText, prompt: Text("e.g. 120.5"))
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Priced from Kraken on every refresh. Use this for staked coins or chains Worth doesn't read directly.")
                }
            } else {
                Section {
                    TextField("Value", text: $valueText, prompt: Text("$0"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text(kind.isLiability ? "Amount owed" : "Current value")
                } footer: {
                    Text(valueFooter)
                }
            }

            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            if let existing, existing.history.count > 1 {
                Section("Value history") {
                    ForEach(existing.history.reversed(), id: \.date) { point in
                        LabeledContent(point.date.formatted(date: .abbreviated, time: .omitted), value: Format.currency(point.value))
                    }
                }
            }

            if existing != nil {
                Section {
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(existing == nil ? "Add asset or debt" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if existing == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!isValid || isSaving)
            }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let existing { model.deleteManualAsset(id: existing.id) }
                dismiss()
            }
        }
    }

    private var valueFooter: String {
        switch kind {
        case .privateCompany: "Your stake at the latest round price or your own estimate. Update it after new rounds or distributions."
        case .stockPlan: "Vested shares × current price, e.g. from Morgan Stanley at Work. Leave out unvested shares if you prefer."
        case .art: "Latest appraisal or insured value."
        case .realEstate: "Estimated market value. Add the mortgage separately as a loan if it isn't synced."
        case .loan, .otherDebt: "Enter the balance owed as a positive number; it's subtracted from net worth."
        default: "Enter the value in US dollars."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()

        var asset = existing ?? ManualAsset(name: trimmedName, kind: kind, value: value ?? 0)
        asset.name = trimmedName
        asset.kind = kind
        asset.notes = notes
        if kind == .cryptoHolding {
            asset.symbol = trimmedSymbol
            asset.quantity = quantity
        } else {
            asset.symbol = nil
            asset.quantity = nil
            if let value, value != asset.value || existing == nil {
                asset.setValue(value)
            }
        }
        await model.saveManualAsset(asset)
        dismiss()
    }
}
