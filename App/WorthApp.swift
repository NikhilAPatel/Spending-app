import SwiftUI
import WorthCore

@main
struct WorthApp: App {
    @State private var model: AppModel
    @State private var lock = LockController()

    init() {
        let store: DataStore
        do {
            store = try FileDataStore.standard()
        } catch {
            // Practically unreachable (Application Support is always creatable); keep the app usable.
            store = InMemoryDataStore()
        }
        _model = State(initialValue: AppModel(store: store, secrets: KeychainSecretStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
        }
    }
}
