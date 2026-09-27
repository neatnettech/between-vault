import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    LabeledContent("Unlock with Face ID", value: "On")
                    LabeledContent("Auto-lock", value: "1 minute")
                    LabeledContent("Clear clipboard", value: "After 60 s")
                }
                .listRowBackground(Theme.Colors.surface)
                Section("Data") {
                    LabeledContent("Export backup", value: "1.1")
                    LabeledContent("Attachments unlock", value: "1.1")
                }
                .listRowBackground(Theme.Colors.surface)
                Section("About") {
                    LabeledContent("Version", value: "1.0 (1)")
                    Text("This app collects nothing and has no server to send it to.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle("Settings")
        }
    }
}
