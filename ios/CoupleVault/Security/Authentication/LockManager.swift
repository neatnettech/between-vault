import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class LockManager {
    private(set) var isLocked = true

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock your vault."
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let granted = (try? await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )) ?? false
            isLocked = !granted
        } else {
            // Scaffold: no biometrics available. A vault passcode fallback lands with the
            // authentication work item (spec: dedicated six digit passcode, never the device passcode).
            isLocked = false
        }
    }

    func lock() {
        isLocked = true
    }
}
