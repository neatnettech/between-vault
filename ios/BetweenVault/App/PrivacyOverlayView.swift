import SwiftUI
import UIKit

/// Full screen cover shown whenever the vault is locked, including the app switcher
/// snapshot. Applied through `privacyCover` at the app root and at every sheet root.
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
        // Modal, so VoiceOver cannot swipe past the lock into the vault drawn underneath.
        .accessibilityAddTraits(.isModal)
    }

    private func unlock() async {
        await lockManager.unlock()
        if !lockManager.isLocked {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

extension View {
    /// A sheet is presented above the root view, so the root overlay cannot cover it. Every sheet
    /// root applies this too, which keeps an open draft out of the app switcher snapshot without
    /// dismissing it.
    ///
    /// ponytail: one cover per presentation root; alerts and dialogs still float above. Row 2.5
    /// moves the cover into its own window to catch everything.
    func privacyCover(_ lockManager: LockManager) -> some View {
        overlay {
            if lockManager.isLocked {
                PrivacyOverlayView(lockManager: lockManager)
            }
        }
    }
}
