import SwiftUI
import UIKit

/// Boards P1 to P5: the Partner tab, same components as Exchange (replaces board 14). A dark panel
/// says where the pairing and the recovery copies stand and offers the one thing to do; below it,
/// the two recovery copies, trust, and unpairing. Not paired (P3): the way to pair.
///
/// The recovery copy is the vault key only (owner's choice), so its states are about whether the
/// partner holds the current one: up to date, not sent yet, sent as a file and not confirmed, or
/// needing an update after pairing again. Never "N changes since": a key copy brings no notes back.
struct PartnerView: View {
    @Environment(AppServices.self) private var services
    @State private var partner: Partner?
    @State private var yours = RecoveryStatus.Yours.notSent
    @State private var theirs = RecoveryStatus.Theirs.notReceived
    @State private var lastExchange: Date?
    @State private var pairing: PairingFlow.Role?
    @State private var choosesRole = false
    @State private var nearby = false
    @State private var sharing: SharedFile?
    @State private var asksUnpair = false
    @State private var typesUnpair = false
    @State private var failure: String?
    @State private var unpaired = false
    @State private var restoring = false
    /// Notes on this phone wait for their key (rows 6.1, 6.3).
    @State private var awaitsRestore = false
    @State private var holdsRetired = false
    @State private var asksNewPhone = false
    @ScaledMetric(relativeTo: .footnote) private var badgeSize: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if let partner {
                        paired(partner)
                    } else {
                        notPaired
                    }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabPartner)
            .task { reload() }
            .refreshable { reload() }
            .fullScreenCover(item: $pairing, onDismiss: reload) { role in
                PairingView {
                    PairingFlow(role: role, deviceID: services.deviceID) { agreement in
                        try Pairing.commit(agreement, partners: services.partnerRepository)
                    }
                }
            }
            .fullScreenCover(isPresented: $nearby, onDismiss: reload) {
                if let partner, let key = try? KeyManager.load(Pairing.pairKeyAccount) {
                    NearbyView(partner: partner, pairKey: key, recoveryOnly: true) {
                        Task { try? await Task.sleep(for: .milliseconds(400)); sendRecoveryFile() }
                    }
                }
            }
            .sheet(item: $sharing, onDismiss: removeSharedFile) { file in
                ShareSheet(url: file.url) { completed in
                    if completed {
                        RecoveryStatus().markSentAsFile()
                        reload()
                    }
                }
            }
            // P3: one Pair button; which phone shows and which scans is chosen here.
            .confirmationDialog(Copy.whichPhone, isPresented: $choosesRole, titleVisibility: .visible) {
                Button(Copy.showMyCode) { pairing = .starter }
                Button(Copy.scanTheirCodeChoice) { pairing = .joiner }
            }
            // P5, first ask; the second is typing UNPAIR.
            .confirmationDialog(Copy.unpairFromPartner, isPresented: $asksUnpair, titleVisibility: .visible) {
                Button(Copy.unpair, role: .destructive) { typesUnpair = true }
            } message: {
                Text(Copy.unpairP5Message)
            }
            .sheet(isPresented: $typesUnpair) { TypeToUnpair(onUnpair: unpair) }
            // Row 6.2: one ask, nothing is lost; their copy stays for their new iPhone.
            .confirmationDialog(Copy.newPhoneTitle, isPresented: $asksNewPhone, titleVisibility: .visible) {
                Button(Copy.pairWithNewPhone, action: retire)
            } message: {
                Text(Copy.newPhoneMessage)
            }
            .navigationDestination(isPresented: $restoring) {
                RestoreView(paired: partner != nil, pair: { pairing = $0 }, nearby: { nearby = true })
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: unpaired) { _, new in new }
            .alert(Copy.notSaved, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(Copy.ok, role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    // MARK: P1, P2

    private var allSet: Bool {
        if case .upToDate = yours, case .upToDate = theirs { true } else { false }
    }

    private func paired(_ partner: Partner) -> some View {
        Group {
            DarkPanel {
                PanelHeader(
                    title: Copy.pairedWithPartner,
                    subtitle: Copy.pairedSince(partner.pairedAt, fingerprint: partner.fingerprint),
                    pill: Copy.verified,
                    pillIcon: "checkmark"
                )
                HStack(spacing: Theme.Space.xs) {
                    recoveryChip
                    if let lastExchange { PanelChip(text: Copy.lastExchange(lastExchange)) }
                }
                if awaitsRestore {
                    // Rows 6.1, 6.3: until the vault key is back there is no copy of it to send.
                    PanelPrimaryButton(title: Copy.restoreFromPartner, systemImage: "arrow.counterclockwise") { restoring = true }
                } else if case .upToDate = yours {
                    Text(allSet ? Copy.allSetBody : Copy.waitingForTheirCopy)
                        .font(Theme.Typography.subheadline)
                        .opacity(0.85)
                } else {
                    // P2: the one thing to do, over the nearby connection, a file as the fallback.
                    PanelPrimaryButton(
                        title: yours == .notSent ? Copy.sendRecoveryCopy : Copy.updateRecoveryCopy,
                        systemImage: "arrow.triangle.2.circlepath"
                    ) { nearby = true }
                    Text(Copy.nearbyRecoveryCaption)
                        .font(Theme.Typography.footnote)
                        .opacity(0.75)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    PanelAltRow(
                        title: Copy.sendAsFileInstead,
                        subtitle: Copy.recoveryFileFallbackSub,
                        systemImage: "doc.badge.arrow.up",
                        action: sendRecoveryFile
                    )
                }
            }

            section(Copy.recoverySection) {
                recoveryRow(Copy.yourCopyOnTheirPhone, yoursLine, warning: !isUpToDate(yours))
                Divider()
                recoveryRow(Copy.theirCopyOnYourPhone, theirsLine, warning: false)
            } footer: {
                isUpToDate(yours) ? Copy.recoveryFootnoteAllSet : Copy.recoveryFootnotePending
            }

            section(Copy.trustSection) {
                NavigationLink { CompareFingerprints(fingerprint: partner.fingerprint) } label: { chevronRow(Copy.compareFingerprints) }
                Divider()
                NavigationLink { HowRecoveryWorks() } label: { chevronRow(Copy.howRecoveryWorks) }
                Divider()
                Button { asksNewPhone = true } label: { chevronRow(Copy.partnerHasNewPhone) }
                    .buttonStyle(.plain)
            } footer: { nil }

            Button { asksUnpair = true } label: {
                Text(Copy.unpairRow)
                    .foregroundStyle(Theme.Colors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.md)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
        }
    }

    @ViewBuilder
    private var recoveryChip: some View {
        switch yours {
        case .upToDate: PanelChip(text: Copy.recoveryUpToDate)
        case .notSent: PanelChip(text: Copy.recoveryNotSent, warning: true)
        case .sentAsFile: PanelChip(text: Copy.recoveryNotConfirmed, warning: true)
        case .needsUpdate: PanelChip(text: Copy.recoveryNeedsUpdate, warning: true)
        }
    }

    private var yoursLine: String {
        switch yours {
        case let .upToDate(date): Copy.updatedUpToDate(date)
        case .notSent: Copy.notSentYet
        case let .sentAsFile(date): Copy.sentAsFileNotConfirmedOn(date)
        case .needsUpdate: Copy.needsUpdatingPairedAgain
        }
    }

    private var theirsLine: String {
        switch theirs {
        case let .upToDate(date): Copy.updatedUpToDate(date)
        case .notReceived: Copy.notReceivedYet
        }
    }

    private func isUpToDate(_ yours: RecoveryStatus.Yours) -> Bool {
        if case .upToDate = yours { true } else { false }
    }

    // MARK: P3

    private var notPaired: some View {
        Group {
            DarkPanel {
                PanelHeader(title: Copy.noPartnerYet, subtitle: Copy.pairOnce, pill: Copy.notPairedPill, pillMuted: true)
                Text(Copy.afterPairingBody).font(Theme.Typography.subheadline).opacity(0.85)
                if holdsRetired {
                    Text(Copy.keepingCopyForNewPhone).font(Theme.Typography.subheadline).opacity(0.85)
                }
                PanelPrimaryButton(title: Copy.pairWithPartner, systemImage: "iphone.radiowaves.left.and.right") { choosesRole = true }
                PanelAltRow(
                    title: Copy.restoreFromPartner,
                    subtitle: Copy.restoreFromPartnerSub,
                    systemImage: "arrow.counterclockwise",
                    action: { restoring = true }
                )
            }
            section(Copy.howPairingWorks) {
                ForEach(Array([Copy.pairingStep1, Copy.pairingStep2, Copy.pairingStep3].enumerated()), id: \.offset) { number, step in
                    Label {
                        Text(step).foregroundStyle(Theme.Colors.text)
                    } icon: {
                        Text("\(number + 1)")
                            .font(Theme.Typography.footnote.weight(.semibold))
                            .frame(minWidth: badgeSize, minHeight: badgeSize)
                            .background(Theme.Colors.privateBadgeBG, in: Circle())
                            .foregroundStyle(Theme.Colors.privateBadgeInk)
                    }
                }
            } footer: {
                Copy.noAccountFootnote
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, @ViewBuilder _ content: () -> some View, footer: () -> String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title.uppercased())
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondary)
                .padding(.horizontal, Theme.Space.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Theme.Space.sm) { content() }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            if let footer = footer() {
                Text(footer)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
    }

    private func recoveryRow(_ title: String, _ line: String, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Theme.Colors.text)
            Text(line)
                .font(Theme.Typography.footnote)
                .foregroundStyle(warning ? Theme.Colors.sealedBadgeInk : Theme.Colors.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func chevronRow(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Colors.text)
            Spacer()
            Image(systemName: "chevron.right").font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func reload() {
        partner = try? services.partnerRepository.partner()
        let status = RecoveryStatus()
        if let partner {
            yours = status.yours(pairedAt: partner.pairedAt)
            theirs = status.theirs(pairedAt: partner.pairedAt)
        }
        lastExchange = ((try? services.exchangeLogRepository.history()) ?? []).first?.date
        awaitsRestore = services.awaitsRestore
        holdsRetired = services.holdsRetiredRecovery
    }

    /// The fallback: the recovery copy as a file, confirmed when the phones next meet.
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

    /// Row 6.2: end this pairing, keep their copy, and go straight to pairing their new iPhone.
    private func retire() {
        do {
            try services.retirePairing()
            // After the first dialog has gone, or this one does not show.
            Task { try? await Task.sleep(for: .milliseconds(400)); choosesRole = true }
        } catch {
            failure = Copy.unpairFailed
        }
        reload()
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

// MARK: - P4

/// Compare fingerprints, side by side on both phones.
private struct CompareFingerprints: View {
    let fingerprint: String
    @Environment(\.dismiss) private var dismiss
    @State private var differ = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(Copy.compareFingerprintsBody).foregroundStyle(Theme.Colors.secondary)
                FingerprintDisplay(fingerprint: fingerprint)
                    .padding(Theme.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                Text(Copy.compareFingerprintsFootnote).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(Copy.sameOnBoth) { dismiss() }.buttonStyle(.vaultPrimary)
                Button(Copy.theyAreDifferent) { differ = true }.buttonStyle(.vaultSecondary)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.bg)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.compareFingerprints)
        .alert(Copy.fingerprintsDifferTitle, isPresented: $differ) {
            Button(Copy.ok, role: .cancel) {}
        } message: {
            Text(Copy.fingerprintsDifferBody)
        }
    }
}

/// "How recovery works": the key only copy, honestly. No board draws it.
private struct HowRecoveryWorks: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(Copy.howRecoveryWorksBody, id: \.self) { paragraph in
                    Text(paragraph).foregroundStyle(Theme.Colors.text)
                }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.howRecoveryWorks)
    }
}

// MARK: - P5, second ask

/// Type UNPAIR, as reset types RESET. The board draws only the first ask.
private struct TypeToUnpair: View {
    let onUnpair: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(Copy.typeUnpair).font(Theme.Typography.title3).accessibilityAddTraits(.isHeader)
                TextField(Copy.unpairWord, text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(Theme.Space.sm)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                Text(Copy.unpairP5Message).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
                Spacer()
                Button(Copy.unpair, role: .destructive) {
                    dismiss()
                    onUnpair()
                }
                .buttonStyle(.vaultDestructive)
                .frame(maxWidth: .infinity)
                .disabled(typed != Copy.unpairWord)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Copy.cancel) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The system share sheet for one file, reporting whether it was handed over.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            MainActor.assumeIsolated { completion(completed) }
        }
        return sheet
    }

    func updateUIViewController(_: UIActivityViewController, context: Context) {}
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
