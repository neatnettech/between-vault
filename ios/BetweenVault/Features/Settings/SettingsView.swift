import SwiftUI

struct SettingsView: View {
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
                    LabeledContent(Copy.unlockWithFaceIDSetting, value: Copy.on)
                    LabeledContent(Copy.autoLock, value: Copy.oneMinute)
                    LabeledContent(Copy.clearClipboard, value: Copy.after60s)
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
