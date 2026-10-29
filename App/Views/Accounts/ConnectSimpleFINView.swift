import SwiftUI
import WorthCore

struct ConnectSimpleFINView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("How it works") {
                    Step(number: 1, text: "Open SimpleFIN Bridge, create an account, and link your banks there (Wells Fargo, Chase, Amex, Robinhood…).")
                    Link(destination: URL(string: "https://bridge.simplefin.org")!) {
                        Label("Open SimpleFIN Bridge", systemImage: "safari")
                    }
                    Step(number: 2, text: "In SimpleFIN Bridge, create a setup token for a new app and copy it.")
                    Step(number: 3, text: "Paste the token below. It works once; Worth swaps it for a private access key kept in your keychain.")
                }

                Section {
                    TextField("Setup token", text: $token, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        token = strings.first ?? ""
                    }
                } header: {
                    Text("Setup token")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Color.loss)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text(isConnecting ? "Connecting…" : "Connect")
                            if isConnecting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                } footer: {
                    Text("The first sync pulls up to 90 days of transactions.")
                }
            }
            .navigationTitle("Connect banks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await model.connectSimpleFIN(setupToken: token)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text).font(.subheadline)
        }
    }
}
