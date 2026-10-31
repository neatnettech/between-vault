import Foundation
import Security

enum KeyManager {
    enum KeyError: Error {
        case keychainFailure(OSStatus)
    }

    private static let service = "tech.neatnet.betweenvault.keys"

    /// Returns the stored key for the account, creating and persisting one only if none is stored.
    static func loadOrCreate(_ account: String) throws -> Data {
        if let existing = try load(account) { return existing }
        let key = CryptoEngine.randomKey()
        try save(key, account: account)
        return key
    }

    static func load(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return try storedKey(status: status, result: result)
    }

    /// `nil` only when nothing is stored. Every other failure throws: reading it as "absent" would
    /// mint a new key over the real one and leave every stored note unreadable.
    static func storedKey(status: OSStatus, result: AnyObject?) throws -> Data? {
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeyError.keychainFailure(status) }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyError.keychainFailure(status)
        }
    }

    /// Adds, never replaces: a duplicate fails instead of overwriting a key that still decrypts the
    /// vault. `loadOrCreate` and a restored key use it.
    static func save(_ data: Data, account: String) throws {
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychainFailure(status) }
    }

    /// Writes in place, adding only when nothing is stored; `nil` deletes. An update never leaves a
    /// moment with nothing stored, so a failure keeps the old value whole. Overwriting the vault key
    /// is for the rotation alone, once every note is saved under the new one.
    static func replace(_ data: Data?, account: String) throws {
        guard let data else { return try delete(account) }
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound: try save(data, account: account)
        default: throw KeyError.keychainFailure(status)
        }
    }

    /// Absent counts as deleted. On the vault key only on purpose: a reset (the partner's copy
    /// brings it back) or a fresh install.
    static func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.keychainFailure(status) }
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
