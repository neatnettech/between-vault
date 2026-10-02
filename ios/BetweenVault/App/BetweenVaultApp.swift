import SwiftData
import SwiftUI

@main
struct BetweenVaultApp: App {
    @State private var services: AppServices?
    @State private var lockManager = LockManager()
    @State private var cover = CoverWindow()
    /// Row 2.2: onboarding is shown once. Frozen key, like the other persisted names.
    @AppStorage(LockManager.onboardedKey) private var onboarded = false
    /// True at launch, so opening the app counts as a return.
    @State private var promptOnActive = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _services = State(initialValue: try? AppServices())
    }

    /// The cover and the launch prompt apply once the vault exists, and before onboarding too when
    /// it already holds notes (rc.1, a flag lost in a restore): the flag alone must never take the
    /// lock off a vault that holds something. Then Face ID opens onboarding, which sets the passcode.
    private var guarded: Bool { onboarded || services?.guardsOnboarding ?? true }
    private var covered: Bool { guarded && lockManager.isLocked }

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
            // The lock screen itself is in the cover window. This plain shield only spares the
            // first frame at launch, before that window exists.
            .overlay {
                if covered { Theme.Colors.lockScreen.ignoresSafeArea() }
            }
            .onAppear {
                cover.install(lockManager: lockManager, services: services)
                cover.show(covered)
            }
            .onChange(of: covered) { _, covered in
                // A reset drops `guarded` while still locked: take any vault sheet down first.
                if !covered, lockManager.isLocked { cover.dismissPresented() }
                cover.show(covered)
            }
            // Row 2.5: auto lock. Checked often enough that a minute means about a minute.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    lockManager.lockIfIdle()
                }
            }
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
