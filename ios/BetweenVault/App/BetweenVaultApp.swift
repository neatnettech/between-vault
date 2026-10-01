import SwiftData
import SwiftUI

@main
struct BetweenVaultApp: App {
    @State private var services: AppServices?
    @State private var lockManager = LockManager()
    /// Row 2.2: onboarding is shown once. Frozen key, like the other persisted names.
    @AppStorage(LockManager.onboardedKey) private var onboarded = false
    /// True at launch, so opening the app counts as a return.
    @State private var promptOnActive = true
    @Environment(\.scenePhase) private var scenePhase

    /// Notes from before onboarding existed (rc.1), or a flag lost in a restore. The flag alone
    /// must never take the lock off a vault that holds something. Unknown counts as holding.
    private let vaultHasNotes: Bool

    init() {
        let services = try? AppServices()
        _services = State(initialValue: services)
        vaultHasNotes = (try? services?.noteRepository.noteCount()).flatMap { $0 } != 0
    }

    /// The cover and the launch prompt apply once the vault exists, and before onboarding too when
    /// it already holds notes: then Face ID opens onboarding, and onboarding sets the passcode.
    private var guarded: Bool { onboarded || vaultHasNotes }

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboarded {
                    OnboardingView(lockManager: lockManager) { onboarded = true }
                } else if let services {
                    RootView()
                        .environment(services)
                        .modelContainer(services.container)
                } else {
                    ContentUnavailableView(
                        Copy.vaultUnavailable,
                        systemImage: "exclamationmark.triangle",
                        description: Text(Copy.storeCouldNotOpen)
                    )
                }
            }
            .environment(lockManager)
            .privacyCover(lockManager, enabled: guarded)
        }
        // Spec 21: open the app, Face ID, unlocked. Launch and every return from the background
        // ask once. An inactive blip (the Face ID sheet itself, Control Center) and Lock now do
        // not, so a cancelled prompt never loops and Lock now stays locked.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                // A fresh onboarding leaves promptOnActive set; it ends unlocked, and the next
                // return from the background sets it again anyway.
                guard guarded, promptOnActive else { return }
                promptOnActive = false
                Task { await lockManager.unlock() }
            case .background:
                promptOnActive = true
                lockManager.lock()
            default:
                lockManager.lock()
            }
        }
    }
}
