import LocalAuthentication
import SwiftUI

/// Boards 1, 1a and 1b: the lock screen, vault passcode entry and the wait after too many tries.
/// Covers everything whenever the vault is locked, including the app switcher snapshot. Applied
/// through `privacyCover` at the app root and at every sheet root.
struct PrivacyOverlayView: View {
    let lockManager: LockManager

    private enum Screen: Equatable {
        case lock
        case passcode
        case wait(until: Date)
    }

    @State private var screen: Screen
    @State private var digits = ""
    @State private var alert: String?

    init(lockManager: LockManager) {
        self.lockManager = lockManager
        // A running wait shows first. With Face ID off the passcode is the only way in, so the
        // keypad is up straight away.
        let initial: Screen = if let until = lockManager.waitingUntil {
            .wait(until: until)
        } else if lockManager.biometricsEnabled {
            .lock
        } else {
            .passcode
        }
        _screen = State(initialValue: initial)
    }

    /// Every iPhone on iOS 17 has Face ID or Touch ID.
    private var hasTouchID: Bool { lockManager.biometry == .touchID }

    var body: some View {
        Group {
            switch screen {
            case .lock: lockScreen
            case .passcode: passcodeScreen
            case let .wait(until): waitScreen(until)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.lockScreen.ignoresSafeArea())
        // The board draws the lock screen dark in both modes. A preference, not an environment
        // value, so it reaches the presentation too and the status bar turns light in Light mode.
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        // Modal, so VoiceOver cannot swipe past the lock into the vault drawn underneath.
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Board 1

    private var lockScreen: some View {
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
            if lockManager.biometricsEnabled, lockManager.biometryChanged {
                Text(Copy.biometryChanged(name: hasTouchID ? Copy.touchID : Copy.faceID))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Theme.Space.md)
            } else if lockManager.biometricsEnabled, let blocked = lockManager.blocked,
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
            VStack(spacing: Theme.Space.xs) {
                if lockManager.biometricsEnabled {
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
                    Button(Copy.useVaultPasscode, action: showPasscode)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.onAccentTint)
                        .frame(minHeight: 44)
                } else {
                    Button(Copy.useVaultPasscode, action: showPasscode)
                        .buttonStyle(.vaultPrimary)
                }
            }
        }
        .padding(.bottom, Theme.Space.xxl)
    }

    // MARK: Board 1a

    private var passcodeScreen: some View {
        VStack(spacing: Theme.Space.md) {
            // Scrolls at accessibility text sizes; the keypad stays pinned below.
            ScrollView {
                passcodeHeader
            }
            .scrollBounceBehavior(.basedOnSize)
            PasscodeEntry(digits: $digits, onComplete: submit)
        }
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.lg)
        .onChange(of: alert) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    private var passcodeHeader: some View {
        VStack(spacing: Theme.Space.md) {
            HStack {
                // With Face ID off there is nothing behind Cancel but this screen, so it has none.
                if lockManager.biometricsEnabled {
                    Button(Copy.cancel) { screen = .lock }
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button {
                        screen = .lock
                        Task { await lockManager.unlock() }
                    } label: {
                        Image(systemName: hasTouchID ? "touchid" : "faceid").font(.title2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(hasTouchID ? Copy.useTouchID : Copy.useFaceID)
                }
            }
            .foregroundStyle(Theme.Colors.onAccentTint)
            .frame(minHeight: 44)

            Text(Copy.enterVaultPasscode)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if let alert {
                Label(alert, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.warning)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Board 1b

    private func waitScreen(_ until: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Image(systemName: "timer")
                .font(.title)
                .foregroundStyle(Theme.Colors.text)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.keypadKey, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
                .padding(.top, Theme.Space.xxxl)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Copy.tryAgainIn(until.timeIntervalSince(context.date)))
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(Copy.waitBody)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondary)
            Spacer()
            // ponytail: "Forgot it?" and Reset and restore from partner arrive with 2.4.
            Button(Copy.ok) {
                alert = nil
                screen = lockManager.biometricsEnabled ? .lock : .passcode
            }
            .buttonStyle(.vaultPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Space.xxl)
    }

    private func showPasscode() {
        alert = nil
        if let until = lockManager.waitingUntil {
            screen = .wait(until: until)
        } else {
            screen = .passcode
        }
    }

    private func submit(_ passcode: String) {
        digits = ""
        switch lockManager.unlock(passcode: passcode) {
        case .opened: alert = nil
        case let .wrong(triesLeft): alert = Copy.wrongPasscode(triesLeft: triesLeft)
        case let .wait(until): screen = .wait(until: until)
        case .unreadable: alert = Copy.passcodeUnreadable
        }
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
    /// moves the cover into its own window to catch everything. Until then the root and an open
    /// sheet each hold their own passcode screen; the sheet's is the one on top.
    func privacyCover(_ lockManager: LockManager, enabled: Bool = true) -> some View {
        overlay {
            if enabled, lockManager.isLocked {
                PrivacyOverlayView(lockManager: lockManager)
            }
        }
    }
}
