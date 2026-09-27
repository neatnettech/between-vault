import SwiftUI

struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?

    var body: some View {
        NavigationStack {
            List {
                if let partner {
                    Section("Paired partner") {
                        LabeledContent("Fingerprint", value: partner.fingerprint)
                        Text("Your partner can recover your vault. This is by design.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("No partner paired yet.")
                            .foregroundStyle(.secondary)
                        Button("Pair with partner") {
                            // Pairing flow lands with the exchange work item.
                        }
                    }
                }
            }
            .navigationTitle("Partner")
            .task {
                partner = try? services.partnerRepository.partner()
            }
        }
    }
}
