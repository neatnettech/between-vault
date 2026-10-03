import SwiftUI

struct SettingsView: View {
    @Environment(LockManager.self) private var lockManager
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    /// Read from the bundle, which project.yml fills from MARKETING_VERSION and
    /// CURRENT_PROJECT_VERSION, so the screen follows every version bump.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.security) {
                    @Bindable var lockManager = lockManager
                    // Board 17: the first row, a teal action with a padlock.
                    Button {
                        lockManager.lock()
                    } label: {
                        Label(Copy.lockNow, systemImage: "lock")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Toggle(
                        lockManager.biometry == .touchID ? Copy.unlockWithTouchID : Copy.unlockWithFaceID,
                        isOn: $lockManager.biometricsEnabled
                    )
                    .tint(Theme.Colors.accent)
                    Picker(Copy.autoLock, selection: $lockManager.autoLockMinutes) {
                        ForEach(LockManager.autoLockChoices, id: \.self) { Text(Copy.minutes($0)) }
                    }
                    .pickerStyle(.navigationLink)
                    LabeledContent(Copy.clearClipboard, value: Copy.after60s)
                }
                .listRowBackground(Theme.Colors.surface)
                Section {
                    // The handoff's default is the system setting; Light and Dark are for this app.
                    Picker(Copy.appearance, selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Copy.appearance)
                } header: {
                    Text(Copy.appearance)
                } footer: {
                    Text(Copy.appearanceFooter)
                }
                .listRowBackground(Theme.Colors.surface)
                Section {
                    NavigationLink {
                        AppIconPicker()
                    } label: {
                        LabeledContent(Copy.appIcon, value: AppIconChoice.current.title)
                    }
                }
                .listRowBackground(Theme.Colors.surface)
                Section(Copy.data) {
                    LabeledContent(Copy.exportBackup, value: Copy.comingIn11)
                    LabeledContent(Copy.attachmentsUnlock, value: Copy.comingIn11)
                }
                .listRowBackground(Theme.Colors.surface)
                // Board 17's About, plus Terms of use.
                Section {
                    NavigationLink(Copy.privacyPolicy) { PrivacyStatementView() }
                    NavigationLink(Copy.threatModel) { ThreatModelView() }
                    NavigationLink { LicenseView() } label: { LabeledContent(Copy.license, value: Copy.gplv3) }
                    NavigationLink(Copy.termsOfUse) { TermsView() }
                } header: {
                    Text(Copy.about)
                } footer: {
                    Text(Copy.versionFooter(version))
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabSettings)
        }
    }
}
