import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LockManager {
    private(set) var isLocked = true {
        didSet { if !isLocked { lastActivity = now() } }
    }
    /// The last touch or keystroke, for auto lock (row 2.5). Not observed: it changes constantly.
    @ObservationIgnored private var lastActivity = Date.distantPast
    /// Why biometrics cannot open the vault right now, for the lock screen. `nil` when they can.
    private(set) var blocked: LAError.Code?
    /// Board R1: a file from the partner was opened while locked. The lock screen says so, and
    /// shows nothing of it before unlocking.
    var fileWaiting = false
    /// The enrolled faces or fingers changed since the vault passcode last opened the vault.
    private(set) var biometryChanged = false
    /// True at launch, so opening the app counts as a return.
    @ObservationIgnored private var promptOnActive = true
    /// Not active, the cover shows only the vault mark: it is what the app switcher keeps, and a
    /// keypad there reads as an invitation. The lock screen is back once the app is.
    private(set) var isSceneActive = false

    /// Set while the biometric prompt is up, so the app root and a sheet's cover never prompt twice.
    private var isAuthenticating = false

    /// Board 2d and Settings. Off means the vault passcode is the only way in.
    var biometricsEnabled: Bool {
        didSet { defaults.set(biometricsEnabled, forKey: Keys.biometrics) }
    }
    /// Board 2d and Settings. Enforced by `lockIfIdle()`.
    var autoLockMinutes: Int {
        didSet { defaults.set(autoLockMinutes, forKey: Keys.autoLock) }
    }
    static let autoLockChoices = [1, 5, 15]

    /// Five tries, then a wait (board 1a, 1b). Each wrong try after that waits longer; the last
    /// step repeats.
    static let freeTries = 5
    static let waits: [TimeInterval] = [5 * 60, 15 * 60, 60 * 60]

    private let defaults: UserDefaults
    private let now: () -> Date
    private let matches: (String) throws -> Bool
    /// Reads the current enrollment after a passcode unlock. A parameter only for tests.
    private let enrollmentContext: () -> LAContext

    /// Row 2.2's shown once flag, read here and written by the app root through @AppStorage.
    nonisolated static let onboardedKey = "betweenvault.onboarded"

    /// Persisted keys. Renaming one resets that setting or, for the attempt counter, the wait.
    private enum Keys {
        static let biometrics = "betweenvault.unlockWithBiometrics"
        static let autoLock = "betweenvault.autoLockMinutes"
        static let failures = "betweenvault.passcodeFailures"
        static let waitUntil = "betweenvault.passcodeWaitUntil"
        static let domainState = "betweenvault.biometryDomainState"
    }

    /// Everything is a parameter only so a test can hand in its own store, clock and passcode.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        matches: @escaping (String) throws -> Bool = { try Passcode.matches($0) },
        enrollmentContext: @escaping () -> LAContext = { LAContext() }
    ) {
        self.defaults = defaults
        self.now = now
        self.matches = matches
        self.enrollmentContext = enrollmentContext
        biometricsEnabled = defaults.object(forKey: Keys.biometrics) as? Bool ?? true
        autoLockMinutes = defaults.object(forKey: Keys.autoLock) as? Int ?? 1
    }

    /// Face ID or Touch ID, for the unlock button.
    let biometry: LABiometryType = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }()

    /// Biometrics only: the device passcode never unlocks the vault (spec section 21). The context
    /// is a parameter only so a test can hand in a failing one.
    func unlock(context: sending LAContext = LAContext()) async {
        guard isLocked, biometricsEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // An empty title hides the prompt's "Enter Password" button. The vault passcode takes
        // that place, on the lock screen.
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No match, no vault. Face ID turned off for the app, reset or never set up, the device
            // passcode removed, a lockout: each stays locked and the lock screen says why, since
            // all of them are within reach of someone who only knows the device passcode. The vault
            // passcode stays the way in.
            blocked = error.flatMap { LAError.Code(rawValue: $0.code) }
            return
        }
        blocked = nil
        // Anyone who knows the device passcode can enroll their own face. A changed enrollment,
        // or none recorded yet, needs the vault passcode once before biometrics open the vault.
        // Before onboarding there is no passcode to fall back on and nothing recorded, so the
        // enrollment of the day is trusted; onboarding records it (rc.1 vaults reach it this way).
        // ponytail: an attacker who can edit a restored backup can clear both flags. Upgrade:
        // keep them in the Keychain beside the passcode.
        let recorded = defaults.data(forKey: Keys.domainState)
        let trusted = recorded ?? (defaults.bool(forKey: Self.onboardedKey) ? nil : context.evaluatedPolicyDomainState)
        guard let enrolled = context.evaluatedPolicyDomainState, enrolled == trusted else {
            biometryChanged = true
            return
        }
        biometryChanged = false
        do {
            let granted = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: Copy.unlockReason
            )
            // A match that lands after the app went to the background must not open it there
            // (spec 22). Inactive is fine: the Face ID sheet itself makes the app inactive.
            if granted, UIApplication.shared.applicationState != .background {
                // The owner just proved who they are, so leftover wrong tries start over.
                defaults.removeObject(forKey: Keys.failures)
                defaults.removeObject(forKey: Keys.waitUntil)
                isLocked = false
            }
        } catch {
            // A lockout reached during the prompt shows its reason; a cancel shows nothing.
            blocked = (error as? LAError)?.code
        }
    }

    func lock() {
        isLocked = true
    }

    /// Spec 21: open the app, Face ID, unlocked. Launch and every return from the background ask
    /// once. An inactive blip (the Face ID sheet itself, Control Center) and Lock now do not, so a
    /// cancelled prompt never loops and Lock now stays locked. Spec 22: anything but active locks.
    /// Returns whether to ask for biometrics now. Before onboarding nothing is guarded, so nothing
    /// asks; the pending ask waits for the next return, which sets it again anyway.
    func sceneChanged(to phase: ScenePhase, guarded: Bool) -> Bool {
        isSceneActive = phase == .active
        switch phase {
        case .active:
            guard guarded, promptOnActive else { return false }
            promptOnActive = false
            return true
        case .background:
            promptOnActive = true
            lock()
        default:
            lock()
        }
        return false
    }

    /// The app's own system alert (the camera permission) is about to make the scene inactive,
    /// which locks; the return asks for biometrics like a return from the background would.
    func expectSystemPrompt() {
        promptOnActive = true
    }

    /// Row 2.5: any touch or keystroke while open.
    func noteActivity() {
        lastActivity = now()
    }

    /// Row 2.5, spec 22: locks once the vault sat open and untouched for the auto lock time.
    func lockIfIdle() {
        guard !isLocked, now().timeIntervalSince(lastActivity) >= TimeInterval(autoLockMinutes * 60) else { return }
        lock()
    }

    /// The end of onboarding: the owner just chose the passcode, so asking for it again is noise.
    func openAfterSetup() {
        recordEnrollment()
        isLocked = false
    }

    /// Row 2.4, after the vault is erased: every setting and the attempt count start over, and
    /// onboarding takes the screen. The lock stays on: a sheet being dismissed must not show its
    /// note on the way out. Onboarding draws uncovered and ends with `openAfterSetup()`.
    func forget() {
        for key in [Self.onboardedKey, Keys.biometrics, Keys.autoLock, Keys.failures, Keys.waitUntil, Keys.domainState] {
            defaults.removeObject(forKey: key)
        }
        biometricsEnabled = true
        autoLockMinutes = 1
        biometryChanged = false
        blocked = nil
    }

    /// Trusts the faces or fingers enrolled right now. Only after the vault passcode was entered.
    private func recordEnrollment() {
        let context = enrollmentContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        defaults.set(context.evaluatedPolicyDomainState, forKey: Keys.domainState)
        biometryChanged = false
    }

    enum PasscodeResult: Equatable {
        case opened
        case wrong(triesLeft: Int)
        case wait(until: Date)
        /// The stored passcode could not be read. Not counted as a wrong try.
        case unreadable
    }

    /// The running wait, if any, for the lock screen to show board 1b straight away.
    var waitingUntil: Date? {
        guard let until = defaults.object(forKey: Keys.waitUntil) as? Date, until > now() else { return nil }
        return until
    }

    /// Board 1a. During a wait even the right passcode is refused, or the wait would only slow
    /// down guesses that happen to be wrong.
    ///
    /// ponytail: the wait is wall clock in UserDefaults, so changing the device clock skips it.
    /// Upgrade: a monotonic clock plus a Keychain copy of the counter, if that ever matters.
    func unlock(passcode: String) -> PasscodeResult {
        guard isLocked else { return .opened }
        if let until = waitingUntil { return .wait(until: until) }
        let isMatch: Bool
        do { isMatch = try matches(passcode) } catch { return .unreadable }
        if isMatch {
            defaults.removeObject(forKey: Keys.failures)
            defaults.removeObject(forKey: Keys.waitUntil)
            recordEnrollment()
            blocked = nil
            isLocked = false
            return .opened
        }
        let failures = defaults.integer(forKey: Keys.failures) + 1
        defaults.set(failures, forKey: Keys.failures)
        let over = failures - Self.freeTries
        guard over >= 0 else { return .wrong(triesLeft: -over) }
        let until = now().addingTimeInterval(Self.waits[min(over, Self.waits.count - 1)])
        defaults.set(until, forKey: Keys.waitUntil)
        return .wait(until: until)
    }
}
