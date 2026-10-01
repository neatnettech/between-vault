import SwiftUI

/// Row 2.2: boards 2a, 2b, 2c, then the vault passcode (2e, row 2.3), then 2d. Shown once; the
/// app root swaps it for the vault when `onFinish` runs.
struct OnboardingView: View {
    let lockManager: LockManager
    let onFinish: () -> Void

    private enum Step {
        case promise, noCloud, backup, choosePasscode, confirmPasscode, create
    }

    @State private var step = Step.promise
    @State private var digits = ""
    @State private var chosen = ""
    @State private var mismatch = false
    @State private var biometrics = true
    @State private var autoLockMinutes = 1
    @State private var saveFailed = false

    private var biometryName: String { lockManager.biometry == .touchID ? Copy.touchID : Copy.faceID }

    var body: some View {
        Group {
            switch step {
            case .promise:
                page(1, symbol: "lock.iphone", hero: Copy.promiseHero, body: [Copy.promiseBody], cta: Copy.continueLabel) {
                    step = .noCloud
                }
            case .noCloud:
                page(2, symbol: "icloud.slash", hero: Copy.noCloudHero, body: [Copy.noCloudBody], cta: Copy.continueLabel) {
                    step = .backup
                }
            case .backup:
                page(3, symbol: "arrow.left.arrow.right", hero: Copy.backupHero,
                     body: [Copy.partnerCanRecover, Copy.backupLimit], cta: Copy.iUnderstand) {
                    step = .choosePasscode
                }
            case .choosePasscode:
                passcodePage(title: Copy.choosePasscode, body: Copy.choosePasscodeBody) { code in
                    chosen = code
                    mismatch = false
                    step = .confirmPasscode
                }
            case .confirmPasscode:
                passcodePage(title: Copy.confirmPasscode, body: Copy.confirmPasscodeBody) { code in
                    if code == chosen {
                        step = .create
                    } else {
                        chosen = ""
                        mismatch = true
                        step = .choosePasscode
                        AccessibilityNotification.Announcement(Copy.passcodesDidNotMatch).post()
                    }
                }
            case .create:
                createPage
            }
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
        .animation(.default, value: step)
        .alert(Copy.notSaved, isPresented: $saveFailed) {
            Button(Copy.ok) {}
        } message: {
            Text(Copy.vaultNotCreated)
        }
    }

    // MARK: 2a, 2b, 2c

    /// ponytail: SF Symbols stand in for the boards' line art until the final illustrations exist.
    private func page(
        _ index: Int, symbol: String, hero: String, body: [String], cta: String, next: @escaping () -> Void
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(height: 96)
                    .accessibilityHidden(true)
                Text(hero)
                    .font(Theme.Typography.hero)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(body.enumerated()), id: \.offset) { offset, line in
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundStyle(offset == 0 ? Theme.Colors.text : Theme.Colors.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 96)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.lg) {
                PageDots(current: index, count: 3)
                Button(cta, action: next)
                    .buttonStyle(.vaultPrimary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, Theme.Space.lg)
            .background(Theme.Colors.bg)
        }
    }

    // MARK: 2e

    private func passcodePage(title: String, body: String, onComplete: @escaping (String) -> Void) -> some View {
        VStack(spacing: Theme.Space.md) {
            // Scrolls at accessibility text sizes; the keypad stays pinned below.
            ScrollView {
                passcodeHeader(title: title, body: body)
            }
            .scrollBounceBehavior(.basedOnSize)
            PasscodeEntry(digits: $digits) { code in
                digits = ""
                onComplete(code)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xl)
    }

    private func passcodeHeader(title: String, body: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            HStack {
                Button(Copy.back) {
                    digits = ""
                    mismatch = false
                    step = step == .confirmPasscode ? .choosePasscode : .backup
                }
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: 44, minHeight: 44)
                Spacer()
            }
            Text(title)
                .font(.system(.title, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(body.replacingOccurrences(of: Copy.faceID, with: biometryName))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
            if mismatch {
                Label(Copy.passcodesDidNotMatch, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.warning)
                    .multilineTextAlignment(.center)
            }
            Text(Copy.choosePasscodeFootnote)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: 2d

    private var createPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(Copy.createVaultHero)
                    .font(Theme.Typography.hero)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.createVaultBody)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                VStack(spacing: 0) {
                    LabeledContent(Copy.vaultPasscode) {
                        Label(Copy.set, systemImage: "checkmark")
                            .foregroundStyle(Theme.Colors.onAccentTint)
                    }
                    .padding(.vertical, Theme.Space.sm)
                    Divider()
                    Toggle(lockManager.biometry == .touchID ? Copy.unlockWithTouchID : Copy.unlockWithFaceID, isOn: $biometrics)
                        .tint(Theme.Colors.accent)
                        .padding(.vertical, Theme.Space.xs)
                    Divider()
                    LabeledContent(Copy.autoLock) {
                        Picker(Copy.autoLock, selection: $autoLockMinutes) {
                            ForEach(LockManager.autoLockChoices, id: \.self) { Text(Copy.afterMinutes($0)) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.secondary)
                    }
                    .padding(.vertical, Theme.Space.xxs)
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .padding(.horizontal, Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                Text(Copy.createVaultFootnote.replacingOccurrences(of: Copy.faceID, with: biometryName))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, 96)
        }
        .safeAreaInset(edge: .bottom) {
            Button(Copy.createVault, action: create)
                .buttonStyle(.vaultPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.lg)
                .background(Theme.Colors.bg)
        }
    }

    /// The passcode is saved last and alone can fail; nothing else is written until it is stored,
    /// so a failure leaves onboarding where it was.
    private func create() {
        do {
            try Passcode.set(chosen)
        } catch {
            saveFailed = true
            return
        }
        lockManager.biometricsEnabled = biometrics
        lockManager.autoLockMinutes = autoLockMinutes
        lockManager.openAfterSetup()
        onFinish()
    }
}

/// Boards 2a to 2c: the active page is a wider pill.
private struct PageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(1...count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.Colors.text : Theme.Colors.disabledFill)
                    .frame(width: index == current ? 20 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Copy.page(current, of: count))
    }
}
