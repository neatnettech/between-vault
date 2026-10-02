import SwiftUI

/// Board 14 when paired; Pair and Scan when not (row 3.7).
struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?
    @State private var pairing: PairingFlow.Role?
    @State private var comparing = false
    @State private var sharing: SharedFile?
    @State private var asksUnpair = false
    @State private var asksUnpairAgain = false
    @State private var failure: String?
    @State private var unpaired = false

    var body: some View {
        NavigationStack {
            List {
                if let partner {
                    profile(partner)
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
            .task { reload() }
            .fullScreenCover(item: $pairing, onDismiss: reload) { role in
                PairingView {
                    PairingFlow(role: role, deviceID: services.deviceID) { agreement in
                        try Pairing.commit(agreement, partners: services.partnerRepository)
                    }
                }
            }
            .sheet(isPresented: $comparing) {
                if let partner { CompareFingerprint(fingerprint: partner.fingerprint) }
            }
            .sheet(item: $sharing, onDismiss: removeSharedFile) { file in
                ShareSheet(url: file.url)
            }
            .confirmationDialog(Copy.unpairTitle, isPresented: $asksUnpair, titleVisibility: .visible) {
                Button(Copy.unpair, role: .destructive) { asksUnpairAgain = true }
            } message: {
                Text(Copy.unpairMessage)
            }
            .alert(Copy.unpairAgainTitle, isPresented: $asksUnpairAgain) {
                Button(Copy.cancel, role: .cancel) {}
                Button(Copy.unpair, role: .destructive, action: unpair)
            } message: {
                Text(Copy.unpairAgainMessage)
            }
            // Row 4.7 and handoff C8: confirmation on unpair.
            .sensoryFeedback(.impact(weight: .heavy), trigger: unpaired) { _, new in new }
            .alert(Copy.notSaved, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(Copy.ok, role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    // MARK: Board 14

    private func profile(_ partner: Partner) -> some View {
        Group {
            Section {
                LabeledContent(Copy.paired, value: Copy.since(partner.pairedAt))
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(Copy.deviceFingerprint)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                    FingerprintDisplay(fingerprint: partner.fingerprint)
                }
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                (Text(Copy.partnerCanRecover).bold() + Text(" ") + Text(Copy.alsoNewPhone))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            .listRowBackground(Theme.Colors.accentTint)

            Section {
                Button(action: sendRecoveryFile) {
                    rowLabel(Copy.sendRecoveryFile)
                }
                Button { comparing = true } label: {
                    rowLabel(Copy.compareFingerprintAgain)
                }
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Button(Copy.unpairPartner, role: .destructive) { asksUnpair = true }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text(Copy.unpairFootnote)
            }
            .listRowBackground(Theme.Colors.surface)
        }
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Colors.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func reload() {
        partner = try? services.partnerRepository.partner()
    }

    private func sendRecoveryFile() {
        do {
            sharing = SharedFile(url: try services.recoveryFile())
        } catch {
            failure = Copy.recoveryFileNotMade
        }
    }

    /// The file is the vault key under a key only the two phones hold, but it still does not
    /// linger in a temporary folder once the share sheet is gone.
    private func removeSharedFile() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory
            .appending(path: "Between Vault recovery.\(Pairing.RecoveryFile.fileExtension)"))
    }

    private func unpair() {
        do {
            try services.unpair()
            unpaired = true
        } catch {
            failure = Copy.unpairFailed
        }
        reload()
    }
}

/// "Compare fingerprint again": the fingerprint large, for a side by side look.
private struct CompareFingerprint: View {
    let fingerprint: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    FingerprintDisplay(fingerprint: fingerprint)
                    Text(Copy.compareFingerprintBody)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.secondary)
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.bg.ignoresSafeArea())
            .navigationTitle(Copy.compareFingerprintAgain)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The system share sheet for one file: AirDrop, Messages, Files.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context: Context) {}
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
