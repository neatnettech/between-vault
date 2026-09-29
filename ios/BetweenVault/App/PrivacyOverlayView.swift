import SwiftUI
import UIKit

/// Full screen cover shown whenever the vault is locked, including the app switcher
/// snapshot. No content is ever visible behind it.
struct PrivacyOverlayView: View {
    let lockManager: LockManager

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.md) {
                Image(systemName: "lock.fill")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.accent)
                Text(Copy.locked)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.text)
                Button(Copy.unlockWithFaceID) {
                    Task { await unlock() }
                }
                .buttonStyle(.vaultPrimary)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .padding(Theme.Space.lg)
        }
        .accessibilityElement(children: .contain)
    }

    private func unlock() async {
        await lockManager.unlock()
        if !lockManager.isLocked {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
