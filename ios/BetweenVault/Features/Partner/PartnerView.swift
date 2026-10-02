import SwiftUI

struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?
    @State private var pairing: PairingFlow.Role?

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
                            message: Copy.pairInPerson
                        )
                        // Core flows: A pairs, B scans. Board 14's empty state is not drawn.
                        Button(Copy.pairWithPartner) { pairing = .starter }
                            .buttonStyle(.vaultPrimary)
                        Button(Copy.scanPartnersCode) { pairing = .joiner }
                            .buttonStyle(.vaultSecondary)
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
            .fullScreenCover(item: $pairing, onDismiss: {
                partner = try? services.partnerRepository.partner()
            }) { role in
                PairingView {
                    PairingFlow(role: role, deviceID: services.deviceID) { agreement in
                        try Pairing.commit(agreement, partners: services.partnerRepository)
                    }
                }
            }
        }
    }
}
