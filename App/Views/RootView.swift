import SwiftUI
import WorthCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    private var isLocked: Bool { model.data.requireFaceID && !lock.isUnlocked }

    var body: some View {
        Group {
            if isLocked {
                LockedView()
            } else {
                MainTabs()
            }
        }
        .overlay {
            if model.data.requireFaceID && scenePhase != .active {
                PrivacyCover()
            }
        }
        .task {
            if model.data.requireFaceID { await lock.unlock() }
            await model.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lock()
            case .active:
                Task {
                    if model.data.requireFaceID { await lock.unlock() }
                    await model.refreshIfStale()
                }
            default:
                break
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            NetWorthView()
                .tabItem { Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis") }
            SpendingView()
                .tabItem { Label("Spending", systemImage: "chart.bar") }
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "building.columns") }
        }
    }
}

/// Problems from the last refresh, plus when data was last updated.
struct RefreshStatusSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isRefreshing || !model.refreshMessages.isEmpty || model.saveError != nil || model.data.lastRefresh != nil {
            Section {
                if model.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Updating…").foregroundStyle(.secondary)
                    }
                }
                ForEach(model.refreshMessages, id: \.self) { message in
                    Label {
                        Text(message).font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                if let error = model.saveError {
                    Label {
                        Text(error).font(.footnote)
                    } icon: {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            } footer: {
                if let last = model.data.lastRefresh, !model.isRefreshing {
                    Text("Updated \(Format.relative(last)). Pull down to refresh.")
                }
            }
        }
    }
}
