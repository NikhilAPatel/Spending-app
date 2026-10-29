import LocalAuthentication
import Observation
import SwiftUI

/// Face ID (or passcode) gate shown at launch and whenever the app returns from the background.
@MainActor
@Observable
final class LockController {
    private(set) var isUnlocked = false
    private(set) var errorMessage: String?
    private var isAuthenticating = false

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication falls back to the passcode if Face ID fails.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on this device: there is nothing to authenticate against.
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Worth to see your finances.")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lock() {
        isUnlocked = false
    }
}

struct LockedView: View {
    @Environment(LockController.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Worth is locked")
                .font(.title2.weight(.semibold))
            if let message = lock.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Hides balances in the app switcher.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
