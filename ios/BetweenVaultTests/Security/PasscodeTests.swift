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

    /// The lock trusts the faces of the day only while no passcode is stored, so only a definite
    /// "nothing stored" may read as none.
    @Test(.enabled(if: hasKeychain)) func aPasscodeIsStoredOnlyOnceSet() throws {
        let account = "test.passcode.\(UUID().uuidString)"
        defer { try? KeyManager.delete(account) }

        #expect(!Passcode.isStored(account: account))
        try Passcode.set("583920", account: account)
        #expect(Passcode.isStored(account: account))
    }

    /// Setting again writes in place: the new passcode replaces the old one, never fails on it.
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
