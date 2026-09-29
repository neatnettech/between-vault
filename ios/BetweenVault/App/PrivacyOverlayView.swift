import LocalAuthentication
import SwiftUI

/// Board 1: the lock screen. Covers everything whenever the vault is locked, including the app
/// switcher snapshot. Applied through `privacyCover` at the app root and at every sheet root.
struct PrivacyOverlayView: View {
    let lockManager: LockManager

    /// Every iPhone on iOS 17 has Face ID or Touch ID.
    private var hasTouchID: Bool { lockManager.biometry == .touchID }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Space.md) {
                VaultMark()
                Text(Copy.productName)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.locked)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            Spacer()
            if let blocked = lockManager.blocked,
               let reason = Copy.biometryBlocked(blocked, name: hasTouchID ? Copy.touchID : Copy.faceID) {
                VStack(spacing: Theme.Space.xs) {
                    Text(reason)
                    // Only this case is fixed on the app's own Settings page.
                    if blocked == .biometryNotAvailable, let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link(Copy.openSettings, destination: settings)
                    }
                }
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Space.md)
            }
            Button {
                Task { await lockManager.unlock() }
            } label: {
                Label(
                    hasTouchID ? Copy.unlockWithTouchID : Copy.unlockWithFaceID,
                    systemImage: hasTouchID ? "touchid" : "faceid"
                )
                .multilineTextAlignment(.center)
            }
            .buttonStyle(.vaultPrimary)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.lockScreen.ignoresSafeArea())
        // The board draws the lock screen dark in both modes. A preference, not an environment
        // value, so it reaches the presentation too and the status bar turns light in Light mode.
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        // Modal, so VoiceOver cannot swipe past the lock into the vault drawn underneath.
        .accessibilityAddTraits(.isModal)
    }
}

/// Board 1 and the icon concept: two interlocking rounded rectangles, the couple and the space
/// they share. The board's 1024 point artwork scaled to 72.
private struct VaultMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Theme.Colors.markTeal, lineWidth: 4)
                .frame(width: 24, height: 31)
                .offset(x: -7.7)
            RoundedRectangle(cornerRadius: 9)
                .stroke(Theme.Colors.markLight, lineWidth: 4)
                .frame(width: 24, height: 31)
                .offset(x: 7.7)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
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
