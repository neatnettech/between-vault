import SwiftData
import SwiftUI

@main
struct BetweenVaultApp: App {
    @State private var services: AppServices?
    @State private var lockManager = LockManager()
    /// True at launch, so opening the app counts as a return.
    @State private var promptOnActive = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _services = State(initialValue: try? AppServices())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let services {
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
            .privacyCover(lockManager)
        }
        // Spec 21: open the app, Face ID, unlocked. Launch and every return from the background
        // ask once. An inactive blip (the Face ID sheet itself, Control Center) and Lock now do
        // not, so a cancelled prompt never loops and Lock now stays locked.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                guard promptOnActive else { return }
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
