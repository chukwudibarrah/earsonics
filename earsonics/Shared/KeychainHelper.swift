// Shared/KeychainHelper.swift
import Foundation
import Security

/// Minimal wrapper around the Keychain for storing per-server secrets
/// (currently the Subsonic password). Values are keyed by an `account`
/// string — we use the server's UUID — under a single service namespace.
///
/// Stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: available
/// after the first unlock following a reboot, and never included in encrypted
/// backups or synced to other devices.
enum KeychainHelper {
    private static let service = "com.wonderworks.earsonics.servers"

    /// Stores `value` for `account`, replacing any existing entry.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first so we always insert cleanly.
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the stored value for `account`, or `nil` if none exists.
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Removes the stored value for `account` (no-op if absent).
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
