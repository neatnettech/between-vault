import SwiftUI

struct SettingsView: View {
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
                    LabeledContent(Copy.exportBackup, value: "1.1")
                    LabeledContent(Copy.attachmentsUnlock, value: "1.1")
                }
                .listRowBackground(Theme.Colors.surface)
                Section(Copy.about) {
                    LabeledContent(Copy.version, value: "1.0 (1)")
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
