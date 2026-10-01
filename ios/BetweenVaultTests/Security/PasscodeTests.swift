import Foundation
import Testing

@testable import BetweenVault

struct PasscodeTests {
    @Test func aRecordMatchesOnlyItsOwnPasscode() {
        let stored = Passcode.record("123456")
        #expect(Passcode.check("123456", against: stored))
        #expect(!Passcode.check("123457", against: stored))
        #expect(!Passcode.check("123456", against: Data()), "nothing stored never matches")
        #expect(!stored.contains(Data("123456".utf8)), "the passcode is never stored as typed")
        #expect(Passcode.record("123456") != stored, "every record gets its own salt")
    }

    /// CI builds unsigned, so its simulator has no Keychain (errSecMissingEntitlement). Signed
    /// local runs exercise the real store.
    static let hasKeychain: Bool = {
        let account = "test.probe.\(UUID().uuidString)"
        defer { try? KeyManager.delete(account) }
        return (try? KeyManager.save(Data([1]), account: account)) != nil
    }()

    /// The Keychain outlives a reinstall while the onboarding flag does not, so onboarding again
    /// must replace the old passcode, not fail on it.
    @Test(.enabled(if: hasKeychain)) func settingAgainReplacesTheOldPasscode() throws {
        let account = "test.passcode.\(UUID().uuidString)"
        defer { try? KeyManager.delete(account) }

        #expect(try !Passcode.matches("111111", account: account), "nothing stored never matches")
        try Passcode.set("111111", account: account)
        try Passcode.set("222222", account: account)
        #expect(try Passcode.matches("222222", account: account))
        #expect(try !Passcode.matches("111111", account: account))
    }
}
