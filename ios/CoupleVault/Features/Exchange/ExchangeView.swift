import SwiftUI

struct ExchangeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Ready to send") {
                    EmptyState(
                        systemImage: "tray",
                        headline: "Nothing sealed yet",
                        message: "Seal a note to get it ready for your partner."
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
                Section("Waiting for me") {
                    EmptyState(
                        systemImage: "tray.and.arrow.down",
                        headline: "Nothing waiting",
                        message: "When your partner sends you a file, open it here."
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
                Section("Recently exchanged") {
                    EmptyState(
                        systemImage: "clock.arrow.circlepath",
                        headline: "No exchanges yet",
                        message: "Sent and received items show up here."
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle("Exchange")
        }
    }
}
