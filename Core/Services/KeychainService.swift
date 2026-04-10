import Foundation
import Security

// MARK: - KeychainService

/// Thread-safe wrapper around the macOS Keychain for storing API keys.
/// All methods are synchronous; favour background queues for callers that
/// care about not blocking the main thread.
final class KeychainService {

    // MARK: Singleton

    static let shared = KeychainService()
    private init() {}

    // MARK: - Service Label

    private let service = "com.arise.shadow-system"

    // MARK: - Public API

    /// Save (or update) a value in the Keychain under `key`.
    /// - Returns: `true` on success.
    @discardableResult
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update an existing item first.
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // Item does not exist yet — add it.
        var addQuery = query
        addQuery[kSecValueData] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Load a value from the Keychain for `key`.
    /// - Returns: The stored string, or `nil` if not found.
    func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete the Keychain entry for `key`.
    /// - Returns: `true` on success (including if the item did not exist).
    @discardableResult
    func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Well-Known Key Constants

extension KeychainService {
    /// Keychain key for the Google API key (used by GeminiService).
    static let googleKey  = "ARISE_Google_APIKey"
    /// Keychain key for the OpenAI API key (legacy — no longer needed).
    static let openAIKey  = "ARISE_OpenAI_APIKey"
    /// Keychain key for the Anthropic API key (legacy — no longer needed).
    static let claudeKey  = "ARISE_Anthropic_APIKey"
}
