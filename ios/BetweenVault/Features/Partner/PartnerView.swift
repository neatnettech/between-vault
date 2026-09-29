import SwiftUI

struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?

    var body: some View {
        NavigationStack {
            List {
                if let partner {
                    Section(Copy.pairedPartner) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(Copy.fingerprint)
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondary)
                            FingerprintDisplay(fingerprint: partner.fingerprint)
                        }
                        Text(Copy.partnerCanRecover)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondary)
                    }
                    .listRowBackground(Theme.Colors.surface)
                } else {
                    Section {
                        EmptyState(
                            systemImage: "person.2",
                            headline: Copy.noPartnerPaired,
                            message: Copy.pairingLandsLater
                        )
                        Button(Copy.pairWithPartner) {
                            // Pairing flow lands with the exchange work item.
                        }
                        .buttonStyle(.vaultPrimary)
                    }
                    .listRowBackground(Theme.Colors.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabPartner)
            .task {
                partner = try? services.partnerRepository.partner()
            }
        }
    }
}
