import Foundation
import Security
import WorthCore

/// Stores credentials (SimpleFIN access URL, Kraken keys) in the iOS keychain. Items are
/// readable only while the phone is unlocked and never sync to iCloud or other devices.
struct KeychainSecretStore: SecretStore {
    private let service = "com.nikhilapatel.worth"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain error \(status)" }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func secret(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String?, for key: String) throws {
        SecItemDelete(baseQuery(key) as CFDictionary)
        guard let value else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
