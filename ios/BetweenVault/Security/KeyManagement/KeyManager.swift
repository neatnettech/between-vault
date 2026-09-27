import Foundation
import Security

enum KeyManager {
    enum KeyError: Error {
        case keychainFailure(OSStatus)
    }

    private static let service = "tech.neatnet.betweenvault.keys"

    /// Returns the stored key for the account, creating and persisting one if absent.
    static func loadOrCreate(_ account: String) throws -> Data {
        if let existing = load(account) { return existing }
        let key = CryptoEngine.randomKey()
        try save(key, account: account)
        return key
    }

    static func load(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    static func save(_ data: Data, account: String) throws {
        SecItemDelete(baseQuery(account) as CFDictionary)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychainFailure(status) }
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
