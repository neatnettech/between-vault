import Foundation
import LocalAuthentication
import Testing

@testable import BetweenVault

/// A context whose preflight fails with a fixed LocalAuthentication code, so the failure path of
/// unlock() runs without Face ID hardware.
private final class FailingContext: LAContext {
    private let code: LAError.Code

    init(_ code: LAError.Code) {
        self.code = code
        super.init()
    }

    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        error?.pointee = NSError(domain: LAError.errorDomain, code: code.rawValue)
        return false
    }
}

@MainActor
struct LockManagerTests {
    /// No match, no vault. Every preflight failure, including the ones someone who only knows the
    /// device passcode can cause (Face ID off for the app, reset, no passcode, locked out), keeps
    /// the vault locked and records why for the lock screen.
    @Test func aFailedPreflightNeverOpensTheVault() async {
        for code in [LAError.Code.biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet, .biometryLockout] {
            let lock = LockManager()
            await lock.unlock(context: FailingContext(code))
            #expect(lock.isLocked, "\(code)")
            #expect(lock.blocked == code, "\(code)")
        }
    }
}
