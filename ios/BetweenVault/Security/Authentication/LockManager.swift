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
    /// Measures the waits. Unlike `now`, nobody can set it.
    private let uptime: () -> TimeInterval
    private let matches: (String) throws -> Bool
    private let passcodeStored: () -> Bool
    private let keychainLoad: (String) throws -> Data?
    private let keychainStore: (Data?, String) throws -> Void
    /// Reads the current enrollment after a passcode unlock. A parameter only for tests.
    private let enrollmentContext: () -> LAContext

    /// Row 2.2's shown once flag, read here and written by the app root through @AppStorage.
    nonisolated static let onboardedKey = "betweenvault.onboarded"

    /// Keychain accounts, frozen like the passcode's. The wrong tries and the trusted enrollment
    /// sit beside the passcode, not in UserDefaults: a restored settings file cannot start the
    /// count over, and once an enrollment is recorded here it cannot plant one of its own.
    nonisolated static let attemptsAccount = "betweenvault.passcodeAttempts"
    nonisolated static let enrollmentAccount = "betweenvault.biometryDomainState"

    /// Persisted keys. Renaming one resets that setting.
    private enum Keys {
        static let biometrics = "betweenvault.unlockWithBiometrics"
        static let autoLock = "betweenvault.autoLockMinutes"
        /// Where 1.0 kept the count, the wait and the enrollment. Each moves to the Keychain on
        /// first use, so the update neither gives fresh tries nor asks for the passcode.
        static let legacyFailures = "betweenvault.passcodeFailures"
        static let legacyWaitUntil = "betweenvault.passcodeWaitUntil"
        static let legacyDomainState = "betweenvault.biometryDomainState"
    }

    /// Everything is a parameter only so a test can hand in its own store, clocks, passcode and
    /// Keychain.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = LockManager.uptime,
        matches: @escaping (String) throws -> Bool = { try Passcode.matches($0) },
        passcodeStored: @escaping () -> Bool = { Passcode.isStored() },
        keychainLoad: @escaping (String) throws -> Data? = { try KeyManager.load($0) },
        keychainStore: @escaping (Data?, String) throws -> Void = { try KeyManager.replace($0, account: $1) },
        enrollmentContext: @escaping () -> LAContext = { LAContext() }
    ) {
        self.defaults = defaults
        self.now = now
        self.uptime = uptime
        self.matches = matches
        self.passcodeStored = passcodeStored
        self.keychainLoad = keychainLoad
        self.keychainStore = keychainStore
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
        // Only a vault that never had a passcode (rc.1, before onboarding) trusts the enrollment
        // of the day, and onboarding records it. A stored passcode or the onboarded flag makes
        // nothing recorded a change, so a restored settings file that drops both still ends at
        // the passcode.
        // ponytail: a restore that also deletes the passcode's Keychain item looks like rc.1.
        // Upgrade: the vault key itself behind Face ID and the passcode.
        let recorded: Data?
        do {
            recorded = try recordedEnrollment()
        } catch {
            // Unreadable is no proof of the same faces: the passcode once, as for a change.
            biometryChanged = true
            return
        }
        let beforeAnyPasscode = !defaults.bool(forKey: Self.onboardedKey) && !passcodeStored()
        let trusted = recorded ?? (beforeAnyPasscode ? context.evaluatedPolicyDomainState : nil)
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
                clearAttempts()
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

    /// The cover must stay up whenever the vault is locked or the scene is not active, or the
    /// app switcher could keep a picture of the content. Unlocked alone does not uncover: a
    /// biometric grant lands while the Face ID sheet holds the scene inactive, and the owner can
    /// swipe the app away before it ever activates again.
    func coversScene(guarded: Bool) -> Bool {
        guarded && (isLocked || !isSceneActive)
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
    /// A count left in the Keychain by an earlier install starts over with the new vault.
    func openAfterSetup() {
        clearAttempts()
        recordEnrollment()
        isLocked = false
    }

    /// Row 2.4, after the vault is erased: every setting and the attempt count start over, and
    /// onboarding takes the screen. The lock stays on: a sheet being dismissed must not show its
    /// note on the way out. Onboarding draws uncovered and ends with `openAfterSetup()`.
    func forget() {
        for key in [Self.onboardedKey, Keys.biometrics, Keys.autoLock, Keys.legacyFailures, Keys.legacyWaitUntil, Keys.legacyDomainState] {
            defaults.removeObject(forKey: key)
        }
        for account in [Self.attemptsAccount, Self.enrollmentAccount] {
            try? keychainStore(nil, account)
        }
        biometricsEnabled = true
        autoLockMinutes = 1
        biometryChanged = false
        blocked = nil
    }

    /// Trusts the faces or fingers enrolled right now. Only after the vault passcode was entered.
    /// A write that fails asks for the passcode again next time, which is the safe side.
    private func recordEnrollment() {
        let context = enrollmentContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        try? keychainStore(context.evaluatedPolicyDomainState, Self.enrollmentAccount)
        defaults.removeObject(forKey: Keys.legacyDomainState)
        biometryChanged = false
    }

    /// The trusted enrollment. 1.0 kept it in UserDefaults: it moves to the Keychain on first
    /// use, so Face ID keeps opening without a passcode the owner may not remember.
    private func recordedEnrollment() throws -> Data? {
        if let stored = try keychainLoad(Self.enrollmentAccount) { return stored }
        guard let legacy = defaults.data(forKey: Keys.legacyDomainState) else { return nil }
        try keychainStore(legacy, Self.enrollmentAccount)
        defaults.removeObject(forKey: Keys.legacyDomainState)
        return legacy
    }

    enum PasscodeResult: Equatable {
        case opened
        case wrong(triesLeft: Int)
        case wait(until: Date)
        /// The stored passcode or the attempt count could not be read or written. The passcode
        /// was not checked, and nothing was counted.
        case unreadable
    }

    /// The wrong tries and the running wait, as JSON in the Keychain.
    private struct Attempts: Codable {
        var failures = 0
        /// `uptime` when the wait began, and how long it lasts.
        var waitStart: TimeInterval?
        var waitLength: TimeInterval?
    }

    /// `nil` when the Keychain cannot be read: then no try is counted, and none is given.
    private func attempts() -> Attempts? {
        do {
            guard let data = try keychainLoad(Self.attemptsAccount) else { return carriedOver() }
            return (try? JSONDecoder().decode(Attempts.self, from: data)) ?? Attempts()
        } catch {
            return nil
        }
    }

    /// 1.0 kept the count and the wait in UserDefaults. Carried over, so the update gives no
    /// fresh tries: the wall clock wait still left becomes an uptime wait from now. Nothing
    /// written there can help a guesser, since it can only add tries and waits.
    private func carriedOver() -> Attempts {
        let legacyUntil = defaults.object(forKey: Keys.legacyWaitUntil) as? Date
        guard defaults.object(forKey: Keys.legacyFailures) != nil || legacyUntil != nil else { return Attempts() }
        var record = Attempts(failures: defaults.integer(forKey: Keys.legacyFailures))
        if let legacyUntil, legacyUntil > now() {
            record.waitStart = uptime()
            record.waitLength = min(legacyUntil.timeIntervalSince(now()), Self.waits[Self.waits.count - 1])
        }
        // Left in place for the next try if the Keychain refuses it now.
        if (try? store(record)) != nil {
            defaults.removeObject(forKey: Keys.legacyFailures)
            defaults.removeObject(forKey: Keys.legacyWaitUntil)
        }
        return record
    }

    private func store(_ attempts: Attempts) throws {
        try keychainStore(JSONEncoder().encode(attempts), Self.attemptsAccount)
    }

    private func clearAttempts() {
        try? keychainStore(nil, Self.attemptsAccount)
        // A 1.0 count not yet carried over (a Face ID unlock came first) must not come back.
        defaults.removeObject(forKey: Keys.legacyFailures)
        defaults.removeObject(forKey: Keys.legacyWaitUntil)
    }

    /// The running wait in the record, if any, as the date the lock screen shows. A restart and
    /// a served wait update the record.
    private func runningWait(in record: inout Attempts) -> Date? {
        guard let start = record.waitStart, let length = record.waitLength else { return nil }
        let since = uptime()
        // Uptime starts over at a restart, which came after the wait began: the time since boot
        // has passed for sure. Counting only that never shortens a wait, and a wait that ended
        // before the restart stays ended.
        if since < start {
            record.waitStart = 0
            try? store(record)
        }
        let left = length - (since - (record.waitStart ?? 0))
        guard left > 0 else {
            record.waitStart = nil
            record.waitLength = nil
            try? store(record)
            return nil
        }
        return now().addingTimeInterval(left)
    }

    /// The running wait, if any, for the lock screen to show board 1b straight away.
    var waitingUntil: Date? {
        guard var record = attempts() else { return nil }
        return runningWait(in: &record)
    }

    /// Board 1a. During a wait even the right passcode is refused, or the wait would only slow
    /// down guesses that happen to be wrong. The count and the wait sit in the Keychain and the
    /// wait runs on uptime, so neither moving the clock nor restoring the settings file shortens
    /// it. Each try is counted before it is checked: one that cannot be counted is never checked.
    ///
    /// ponytail: a restore that also deletes the Keychain record starts the count over. Upgrade:
    /// the vault key itself behind the passcode.
    func unlock(passcode: String) -> PasscodeResult {
        guard isLocked else { return .opened }
        guard var record = attempts() else { return .unreadable }
        if let until = runningWait(in: &record) { return .wait(until: until) }
        let before = record
        record.failures += 1
        let over = record.failures - Self.freeTries
        if over >= 0 {
            record.waitStart = uptime()
            record.waitLength = Self.waits[min(over, Self.waits.count - 1)]
        }
        do { try store(record) } catch { return .unreadable }
        let isMatch: Bool
        do {
            isMatch = try matches(passcode)
        } catch {
            // Not checked, so not counted either.
            try? store(before)
            return .unreadable
        }
        if isMatch {
            clearAttempts()
            recordEnrollment()
            blocked = nil
            isLocked = false
            return .opened
        }
        guard over >= 0, let length = record.waitLength else { return .wrong(triesLeft: -over) }
        return .wait(until: now().addingTimeInterval(length))
    }

    /// Seconds since the phone started, sleep included. Unlike the clock, nobody can set it.
    nonisolated static func uptime() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}
