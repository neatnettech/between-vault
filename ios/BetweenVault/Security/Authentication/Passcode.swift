import CommonCrypto
import Foundation

/// The six digit vault passcode (row 2.3). It gates opening the app, like Face ID; it does not
/// wrap the vault key (spec 21). Stored as salt plus PBKDF2, Keychain, this device only.
///
/// ponytail: six digits is a million guesses, so the hash only slows down someone who already
/// extracted the Keychain item. The attempt limit in LockManager is the real defence.
enum Passcode {
    static let length = 6
    /// Keychain account name. Frozen from the first TestFlight build onward, like the vault key's.
    static let account = "betweenvault.passcode"
    private static let rounds: UInt32 = 200_000
    private static let saltSize = 16

    /// Replaces any stored passcode. The Keychain outlives a reinstall while the onboarding flag
    /// does not, so a fresh onboarding has to be able to overwrite the old one.
    static func set(_ passcode: String, account: String = account) throws {
        try KeyManager.delete(account)
        try KeyManager.save(record(passcode), account: account)
    }

    /// False when nothing is stored, so a missing passcode never opens the vault.
    static func matches(_ passcode: String, account: String = account) throws -> Bool {
        guard let stored = try KeyManager.load(account) else { return false }
        return check(passcode, against: stored)
    }

    /// What is stored: a fresh salt, then PBKDF2 of the passcode under it.
    static func record(_ passcode: String) -> Data {
        let salt = CryptoEngine.randomKey().prefix(saltSize)
        return salt + derive(passcode, salt: salt)
    }

    static func check(_ passcode: String, against stored: Data) -> Bool {
        guard stored.count > saltSize else { return false }
        let salt = stored.prefix(saltSize)
        let expected = stored.dropFirst(saltSize)
        let actual = derive(passcode, salt: salt)
        guard expected.count == actual.count else { return false }
        // Constant time: no early exit on the first differing byte.
        var difference: UInt8 = 0
        for (a, b) in zip(expected, actual) { difference |= a ^ b }
        return difference == 0
    }

    private static func derive(_ passcode: String, salt: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passcode, passcode.utf8.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
            &out, out.count
        )
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return Data(out)
    }
}
