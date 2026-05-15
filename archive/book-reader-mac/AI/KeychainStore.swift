import Foundation
import Security

/// Raw Security-framework BYOK store. One entry per provider keyed by
/// `kSecAttrAccount = provider.rawValue`, `kSecAttrService = bundle id`.
/// Default accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
/// iCloud Keychain sync is opt-in via `setSynchronizable(_:)`.
public enum KeychainStore {
    public enum KeychainError: Error, Equatable {
        case unhandledStatus(OSStatus)
        case invalidUTF8
    }

    /// Sticky preference observed by `save(...)`. Default false (device-only).
    /// Stored in UserDefaults so it survives launch.
    private static let synchronizableKey = "ai.keychain.synchronizable"

    public static var isSynchronizable: Bool {
        UserDefaults.standard.bool(forKey: synchronizableKey)
    }

    public static func setSynchronizable(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: synchronizableKey)
    }

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.instant-book-reader.mac"
    }

    public static func save(key: String, for provider: ProviderID) throws {
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidUTF8 }

        // Build the unique-record query (service + account only).
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]

        // Update path: try update first. Update only the value + accessibility +
        // synchronizable bit so we don't accidentally fail when the previous
        // record was created with different accessibility.
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: isSynchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]

        // We must include kSecAttrSynchronizable in the search query for
        // SecItemUpdate to find existing synced/unsynced records — pass
        // `kSecAttrSynchronizableAny` so either kind matches.
        var searchQuery = query
        searchQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary,
                                         attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        // Insert path.
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = isSynchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    public static func load(for provider: ProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for provider: ProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }
    }
}
