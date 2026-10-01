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

/// A context that passes the preflight with a fixed enrollment and matches when asked, so the
/// success path of unlock() runs without Face ID hardware.
private final class EnrolledContext: LAContext {
    private let state: Data

    init(_ state: Data) {
        self.state = state
        super.init()
    }

    override var evaluatedPolicyDomainState: Data? { state }
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, (any Error)?) -> Void) {
        reply(true, nil)
    }
}

@MainActor
struct LockManagerTests {
    /// No match, no vault. Every preflight failure, including the ones someone who only knows the
    /// device passcode can cause (Face ID off for the app, reset, no passcode, locked out), keeps
    /// the vault locked and records why for the lock screen.
    @Test func aFailedPreflightNeverOpensTheVault() async {
        for code in [LAError.Code.biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet, .biometryLockout] {
            let lock = LockManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            await lock.unlock(context: FailingContext(code))
            #expect(lock.isLocked, "\(code)")
            #expect(lock.blocked == code, "\(code)")
        }
    }

    /// A fresh store, a clock the test moves, and "123456" as the passcode.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private func makeLock(_ clock: Clock = Clock(), defaults: UserDefaults? = nil) -> LockManager {
        LockManager(
            defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!,
            now: { clock.now },
            matches: { $0 == "123456" }
        )
    }

    /// Board 1a: five tries, the first wrong one says four are left, the fifth starts the wait.
    @Test func wrongPasscodesCountDownToAFiveMinuteWait() {
        let clock = Clock()
        let lock = makeLock(clock)
        for left in [4, 3, 2, 1] {
            #expect(lock.unlock(passcode: "000000") == .wrong(triesLeft: left))
        }
        #expect(lock.unlock(passcode: "000000") == .wait(until: clock.now.addingTimeInterval(5 * 60)))
        #expect(lock.isLocked)
    }

    /// During a wait even the right passcode is refused, or the wait would only slow down guesses
    /// that happen to be wrong.
    @Test func theRightPasscodeIsRefusedDuringAWait() {
        let clock = Clock()
        let lock = makeLock(clock)
        for _ in 0..<5 { _ = lock.unlock(passcode: "000000") }
        clock.now.addTimeInterval(4 * 60)
        #expect(lock.unlock(passcode: "123456") == .wait(until: Date(timeIntervalSince1970: 1_000_000 + 5 * 60)))
        #expect(lock.isLocked)
    }

    /// Board 1b: each wrong try after the wait waits longer, and the last step repeats.
    @Test func everyWrongTryAfterTheWaitWaitsLonger() {
        let clock = Clock()
        let lock = makeLock(clock)
        for _ in 0..<5 { _ = lock.unlock(passcode: "000000") }
        for wait: TimeInterval in [15 * 60, 60 * 60, 60 * 60] {
            clock.now.addTimeInterval(2 * 60 * 60)
            #expect(lock.unlock(passcode: "000000") == .wait(until: clock.now.addingTimeInterval(wait)))
        }
    }

    /// The count survives a relaunch: a new LockManager on the same store is still waiting.
    @Test func theWaitSurvivesARelaunch() {
        let clock = Clock()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = makeLock(clock, defaults: defaults)
        for _ in 0..<5 { _ = first.unlock(passcode: "000000") }
        #expect(makeLock(clock, defaults: defaults).waitingUntil != nil)
    }

    /// The right passcode opens and starts the count over.
    @Test func theRightPasscodeOpensAndResetsTheCount() {
        let clock = Clock()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let lock = makeLock(clock, defaults: defaults)
        for _ in 0..<3 { _ = lock.unlock(passcode: "000000") }
        #expect(lock.unlock(passcode: "123456") == .opened)
        #expect(!lock.isLocked)
        lock.lock()
        #expect(lock.unlock(passcode: "000000") == .wrong(triesLeft: 4))
    }

    /// An unreadable passcode store is not a wrong try and never opens the vault.
    @Test func anUnreadableStoreIsNotCounted() {
        struct Unreadable: Error {}
        let lock = LockManager(defaults: UserDefaults(suiteName: UUID().uuidString)!, matches: { _ in throw Unreadable() })
        #expect(lock.unlock(passcode: "123456") == .unreadable)
        #expect(lock.isLocked)
    }

    /// Face ID off: unlock() never prompts, so the failing context is never asked.
    @Test func biometricsOffNeverPrompts() async {
        let lock = makeLock()
        lock.biometricsEnabled = false
        await lock.unlock(context: FailingContext(.biometryNotAvailable))
        #expect(lock.blocked == nil)
        #expect(lock.isLocked)
    }

    private func makeOnboardedLock(_ defaults: UserDefaults, clock: Clock = Clock(), enrolled: Data) -> LockManager {
        defaults.set(true, forKey: LockManager.onboardedKey)
        return LockManager(defaults: defaults, now: { clock.now }, matches: { $0 == "123456" },
                           enrollmentContext: { EnrolledContext(enrolled) })
    }

    /// Someone who knows the device passcode can enroll their own face. A changed enrollment never
    /// opens the vault until the vault passcode is entered, which then trusts it.
    @Test func aChangedEnrollmentNeedsTheVaultPasscodeOnce() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let lock = makeOnboardedLock(defaults, enrolled: Data("owner".utf8))
        lock.openAfterSetup()
        lock.lock()

        await lock.unlock(context: EnrolledContext(Data("intruder".utf8)))
        #expect(lock.isLocked)
        #expect(lock.biometryChanged)

        let next = makeOnboardedLock(defaults, enrolled: Data("intruder".utf8))
        #expect(next.unlock(passcode: "123456") == .opened)
        next.lock()
        await next.unlock(context: EnrolledContext(Data("intruder".utf8)))
        #expect(!next.isLocked)
    }

    /// Before onboarding nothing is recorded and no passcode exists, so biometrics still open an
    /// rc.1 vault; after onboarding, nothing recorded means changed.
    @Test func anUnrecordedEnrollmentIsTrustedOnlyBeforeOnboarding() async {
        let fresh = makeLock()
        await fresh.unlock(context: EnrolledContext(Data("owner".utf8)))
        #expect(!fresh.isLocked)

        let onboarded = makeOnboardedLock(UserDefaults(suiteName: UUID().uuidString)!, enrolled: Data("owner".utf8))
        await onboarded.unlock(context: EnrolledContext(Data("owner".utf8)))
        #expect(onboarded.isLocked)
        #expect(onboarded.biometryChanged)
    }

    /// A biometric match proves the owner, so leftover wrong tries and a running wait start over.
    @Test func aBiometricMatchClearsTheWait() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let lock = makeOnboardedLock(defaults, enrolled: Data("owner".utf8))
        lock.openAfterSetup()
        lock.lock()
        for _ in 0..<5 { _ = lock.unlock(passcode: "000000") }
        #expect(lock.waitingUntil != nil)

        await lock.unlock(context: EnrolledContext(Data("owner".utf8)))
        #expect(!lock.isLocked)
        #expect(lock.waitingUntil == nil)
        lock.lock()
        #expect(lock.unlock(passcode: "000000") == .wrong(triesLeft: 4))
    }

    /// Row 2.4: after the vault is erased, every setting and the attempt count start over, the
    /// lock comes off and onboarding runs again.
    @Test func forgetStartsEverythingOver() {
        let clock = Clock()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let lock = makeOnboardedLock(defaults, clock: clock, enrolled: Data("owner".utf8))
        lock.biometricsEnabled = false
        lock.autoLockMinutes = 15
        for _ in 0..<5 { _ = lock.unlock(passcode: "000000") }

        lock.forget()

        #expect(lock.isLocked, "a dismissing sheet stays covered")
        #expect(lock.waitingUntil == nil)
        #expect(lock.biometricsEnabled)
        #expect(lock.autoLockMinutes == 1)
        #expect(!defaults.bool(forKey: LockManager.onboardedKey))
        let relaunched = makeLock(clock, defaults: defaults)
        #expect(relaunched.biometricsEnabled)
        relaunched.lock()
        #expect(relaunched.unlock(passcode: "000000") == .wrong(triesLeft: 4))
    }
}
