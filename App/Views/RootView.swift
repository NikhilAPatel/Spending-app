import SwiftUI
import WorthCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    /// Leaving the app briefly (to copy a SimpleFIN token or a Kraken key) doesn't lock it,
    /// so half-filled screens survive. The app-switcher snapshot is still hidden.
    private static let lockGracePeriod: TimeInterval = 5 * 60

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
                backgroundedAt = Date()
            case .active:
                // The Face ID prompt itself makes the app briefly inactive; only a real trip
                // to the background (not a cancelled prompt) should prompt again.
                guard let since = backgroundedAt else { break }
                backgroundedAt = nil
                if Date().timeIntervalSince(since) > Self.lockGracePeriod {
                    lock.lock()
                }
                Task {
                    if model.data.requireFaceID { await lock.unlock() }
                    await model.refreshIfStale()
                }
            default:
                break
            }
        }
        .onChange(of: model.data.requireFaceID) { _, isRequired in
            // Turning the lock on (or erasing data, which resets it) shouldn't lock you out mid-session.
            if isRequired { lock.markUnlocked() }
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
                ForEach(Array(model.refreshMessages.enumerated()), id: \.offset) { _, message in
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
