import SwiftUI

struct SettingsView: View {
    @Environment(LockManager.self) private var lockManager

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
                Section(Copy.about) {
                    LabeledContent(Copy.version, value: version)
                    Text(Copy.collectsNothing)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabSettings)
        }
    }
}
