import Foundation
import Testing

@testable import BetweenVault

/// Runs against the simulator Keychain under a throwaway account, removed at the end.
struct PasscodeTests {
    @Test func storesOnlyTheRightPasscode() throws {
        let account = "test.passcode.\(UUID().uuidString)"
        defer { try? KeyManager.delete(account) }

        #expect(try !Passcode.matches("123456", account: account), "nothing stored never matches")
        try Passcode.set("123456", account: account)
        #expect(try Passcode.matches("123456", account: account))
        #expect(try !Passcode.matches("123457", account: account))

        let stored = try #require(try KeyManager.load(account))
        #expect(!stored.contains(Data("123456".utf8)), "the passcode is never stored as typed")
    }

    /// The Keychain outlives a reinstall while the onboarding flag does not, so onboarding again
    /// must replace the old passcode, not fail on it.
    @Test func settingAgainReplacesTheOldPasscode() throws {
        let account = "test.passcode.\(UUID().uuidString)"
        defer { try? KeyManager.delete(account) }

        try Passcode.set("111111", account: account)
        try Passcode.set("222222", account: account)
        #expect(try Passcode.matches("222222", account: account))
        #expect(try !Passcode.matches("111111", account: account))
    }
}
