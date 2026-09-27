import SwiftUI

struct ExchangeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Ready to send") {
                    Text("Nothing sealed yet")
                        .foregroundStyle(.secondary)
                    Text("Seal a note to get it ready for your partner.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Section("Waiting for me") {
                    Text("Nothing waiting")
                        .foregroundStyle(.secondary)
                    Text("When your partner sends you a file, open it here.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Section("Recently exchanged") {
                    Text("No exchanges yet")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Exchange")
        }
    }
}
