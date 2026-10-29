import SwiftUI
import WorthCore

/// The user's "always categorize X as Y" rules. They're created from a transaction's
/// category screen; here they can be reviewed and deleted.
struct RulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                if model.data.rules.isEmpty {
                    Text("No rules yet. Open a transaction, change its category and leave \"Apply to matching transactions\" on.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.data.rules.sorted { $0.pattern < $1.pattern }) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.pattern).font(.body.monospaced())
                        Text("→ \(rule.category)").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { model.deleteRule(id: rule.id) }
                    }
                }
            } footer: {
                Text("Rules match text anywhere in the bank's description and override the built-in merchant list. Swipe left to delete.")
            }

            if !model.data.customCategories.isEmpty {
                Section("Your categories") {
                    ForEach(model.data.customCategories) { category in
                        LabeledContent(category.name, value: category.kind.title)
                    }
                }
            }
        }
        .navigationTitle("Category rules")
    }
}
