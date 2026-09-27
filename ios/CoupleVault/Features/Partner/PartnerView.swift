import SwiftUI

struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?

    var body: some View {
        NavigationStack {
            List {
                if let partner {
                    Section("Paired partner") {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("Fingerprint")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondary)
                            FingerprintDisplay(fingerprint: partner.fingerprint)
                        }
                        Text("Your partner can recover your vault. This is by design.")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondary)
                    }
                    .listRowBackground(Theme.Colors.surface)
                } else {
                    Section {
                        EmptyState(
                            systemImage: "person.2",
                            headline: "No partner paired yet",
                            message: "Pairing lands with the exchange work."
                        )
                        Button("Pair with partner") {
                            // Pairing flow lands with the exchange work item.
                        }
                        .buttonStyle(.vaultPrimary)
                    }
                    .listRowBackground(Theme.Colors.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle("Partner")
            .task {
                partner = try? services.partnerRepository.partner()
            }
        }
    }
}
