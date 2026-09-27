import SwiftUI

/// Full screen cover shown whenever the vault is locked, including the app switcher
/// snapshot. No content is ever visible behind it.
struct PrivacyOverlayView: View {
    let lockManager: LockManager

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                Text("Locked")
                    .font(.title3)
                Button("Unlock with Face ID") {
                    Task { await lockManager.unlock() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
