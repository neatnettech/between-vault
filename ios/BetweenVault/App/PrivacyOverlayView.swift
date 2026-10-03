import LocalAuthentication
import SwiftUI

/// Boards 1, 1a and 1b: the lock screen, vault passcode entry and the wait after too many tries.
/// Drawn in the cover window (row 2.5), above everything the app presents.
struct PrivacyOverlayView: View {
    let lockManager: LockManager

    private enum Screen: Equatable {
        case lock
        case passcode
        case wait(until: Date)
    }

    @Environment(AppServices.self) private var services: AppServices?
    @State private var screen: Screen
    @State private var digits = ""
    @State private var alert: String?
    @State private var asksReset = false
    @State private var typesReset = false

    /// Row 2.4: paired, the notes survive a reset for restore; not paired, they are gone.
    private var isPaired: Bool { ((try? services?.partnerRepository.partner()) ?? nil) != nil }

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
        // Row 2.4, first ask. The second is typing RESET.
        .alert(Copy.resetAlertTitle, isPresented: $asksReset) {
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.continueReset, role: .destructive) { typesReset = true }
        } message: {
            Text(isPaired ? Copy.resetAlertPaired : Copy.resetAlertNotPaired)
        }
        .sheet(isPresented: $typesReset) {
            ResetConfirmation(services: services, lockManager: lockManager)
        }
    }

    // MARK: Board 1

    private var lockScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Space.md) {
                VaultMark()
                // R1: a file opened while locked. Its titles wait until after unlocking.
                Text(lockManager.fileWaiting ? Copy.aFileFromPartner : Copy.productName)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(lockManager.fileWaiting ? Copy.unlockToCheck : Copy.locked)
                    .font(Theme.Typography.subheadline)
                    .multilineTextAlignment(.center)
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
            // Reset needs the store; without it there is nothing to offer.
            if services != nil {
                Button(Copy.forgotPasscode) { asksReset = true }
                    .foregroundStyle(Theme.Colors.onAccentTint)
                    .frame(minHeight: 44)
            }
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
        VStack(spacing: Theme.Space.sm) {
            ScrollView {
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
                    if services != nil {
                        forgotCard
                            .padding(.top, Theme.Space.md)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(Copy.ok) {
                alert = nil
                screen = lockManager.biometricsEnabled ? .lock : .passcode
            }
            .buttonStyle(.vaultPrimary)
            if services != nil {
                Button { asksReset = true } label: {
                    // The frame inside the label, so the whole outline is the tap target.
                    Text(isPaired ? Copy.resetAndRestore : Copy.resetVault)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.vaultDestructive)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel)
                        .stroke(Theme.Colors.destructive.opacity(0.4))
                }
                Text(Copy.resetAsksTwice)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, Theme.Space.lg)
    }

    /// Board 1b's "Forgot it?" card. The amber line only when nothing could restore the vault.
    private var forgotCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(Copy.forgotIt)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.resetExplained)
                .foregroundStyle(Theme.Colors.secondary)
            if !isPaired {
                Text(Copy.notPairedWarning)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .font(Theme.Typography.subheadline)
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
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

/// Row 2.4, second ask: the word RESET, typed. No board draws it; dark like the lock screen it
/// opens from.
private struct ResetConfirmation: View {
    let services: AppServices?
    let lockManager: LockManager
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(Copy.typeReset)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                TextField(Copy.resetWord, text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(Theme.Space.sm)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                if failed {
                    Label(Copy.resetFailed, systemImage: "exclamationmark.triangle")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.warning)
                }
                Spacer()
                Button(Copy.eraseVault, role: .destructive, action: erase)
                    .buttonStyle(.vaultDestructive)
                    .frame(maxWidth: .infinity)
                    .disabled(typed != Copy.resetWord)
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Colors.lockScreen.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.cancel) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func erase() {
        do {
            guard let services else { throw VaultKeyError.awaitingRestore }
            try services.resetVault()
        } catch {
            failed = true
            AccessibilityNotification.Announcement(Copy.resetFailed).post()
            return
        }
        lockManager.forget()
        dismiss()
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

extension PrivacyOverlayView {
    /// The cover window's root. A fresh lock screen per lock, so it opens on board 1 every time.
    struct Cover: View {
        let lockManager: LockManager

        var body: some View {
            if lockManager.isLocked {
                PrivacyOverlayView(lockManager: lockManager)
            }
        }
    }
}
