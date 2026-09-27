import SwiftData
import SwiftUI

@main
struct BetweenVaultApp: App {
    @State private var services: AppServices?
    @State private var lockManager = LockManager()
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
                        "Vault unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The local store could not be opened. Your data is safe, but the app cannot start.")
                    )
                }
            }
            .environment(lockManager)
            .overlay {
                if lockManager.isLocked {
                    PrivacyOverlayView(lockManager: lockManager)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                lockManager.lock()
            }
        }
    }
}
