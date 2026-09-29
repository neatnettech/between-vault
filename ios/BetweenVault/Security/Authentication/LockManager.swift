import Foundation
import LocalAuthentication
import Observation
import UIKit

@MainActor
@Observable
final class LockManager {
    private(set) var isLocked = true
    /// Why biometrics cannot open the vault right now, for the lock screen. `nil` when they can.
    private(set) var blocked: LAError.Code?
    /// Set while the biometric prompt is up, so the app root and a sheet's cover never prompt twice.
    private var isAuthenticating = false

    /// Face ID or Touch ID, for the unlock button.
    let biometry: LABiometryType = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }()

    /// Biometrics only: the device passcode never unlocks the vault (spec section 21). The context
    /// is a parameter only so a test can hand in a failing one.
    func unlock(context: sending LAContext = LAContext()) async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // An empty title hides the prompt's "Enter Password" button. The vault passcode takes
        // that place with row 2.3.
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No match, no vault. Face ID turned off for the app, reset or never set up, the device
            // passcode removed, a lockout: each stays locked and the lock screen says why, since
            // all of them are within reach of someone who only knows the device passcode.
            // ponytail: a dead end until the vault passcode (2.3) becomes the other way in.
            blocked = error.flatMap { LAError.Code(rawValue: $0.code) }
            return
        }
        blocked = nil
        do {
            let granted = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: Copy.unlockReason
            )
            // A match that lands after the app went to the background must not open it there
            // (spec 22). Inactive is fine: the Face ID sheet itself makes the app inactive.
            if granted, UIApplication.shared.applicationState != .background {
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
}
