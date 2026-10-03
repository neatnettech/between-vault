import SwiftUI

/// Boards N0 to N5: Exchange nearby. N0 once, before iOS asks for local network access; then the
/// link (part C) looks for the partner's phone (N1) and the session (part B) runs on it: choose
/// what to send (N2), the partner's Accept or Decline (N3), progress (N4), done (N5).
struct NearbyView: View {
    let partner: Partner
    let pairKey: Data
    /// Board P2 "Update recovery copy": the session sends this phone's recovery copy and nothing
    /// else. Notes can still arrive from the partner.
    var recoveryOnly = false
    let onSendAsFile: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// N0 is shown once; after that the screen goes straight to looking.
    @AppStorage("betweenvault.nearbyPrimerSeen") private var primerSeen = false
    @State private var link: NearbyLink?
    @State private var session: NearbySession?
    @State private var available: [ExchangeService.OutboxItem] = []
    @State private var ticked = Set<UUID>()
    /// Row 6.1: waiting for the partner's copy to bring this phone's vault key back.
    @State private var restoring = false
    @State private var restored = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Colors.bg.ignoresSafeArea())
                .navigationTitle(Copy.exchangeNearby)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(session == nil ? Copy.cancel : Copy.end) { close() }
                    }
                }
        }
        // Each step replaces the whole screen, which VoiceOver does not notice by itself.
        .onChange(of: screenKey) { AccessibilityNotification.ScreenChanged().post() }
        .onChange(of: failure) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
        .onChange(of: link?.state) { _, state in
            if state == .connected, session == nil, let connection = link?.connection { begin(on: connection) }
        }
        // The session is held up, not tapped: it counts as activity for auto lock while open,
        // at most 10 minutes.
        .task {
            for _ in 0..<120 {
                lockManager.noteActivity()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear { link?.stop() }
        // The partner's confirmations arrive just after connecting and can turn a note sent as a
        // file into Shared: the send list follows, or it offers a note that is no longer sealed.
        // Found on two phones.
        .onChange(of: session?.confirmedCount) { reloadAvailable() }
        // The partner's phone kept this phone's recovery copy: P1 says up to date.
        .onChange(of: session?.recovery) { _, recovery in
            if recovery == .delivered {
                RecoveryStatus().markDelivered()
                // Row 6.2: a returned copy is single use; their phone has it now.
                try? services.dropRetiredRecovery()
            }
        }
        .onChange(of: session?.notReceived) { reloadAvailable() }
        .sensoryFeedback(.success, trigger: deliveredCount) { _, new in new > 0 }
    }

    private var deliveredCount: Int {
        if case let .delivered(count) = session?.state { count } else { 0 }
    }

    /// Which screen `content` is drawing, so a change of state that keeps the screen (the partner's
    /// sheet opening over the list) does not post.
    private var screenKey: String {
        if !primerSeen { return "primer" }
        guard let session else {
            switch link?.state ?? .idle {
            case .localNetworkDenied: return "denied"
            case .unavailable: return "unavailable"
            default: return "looking"
            }
        }
        switch session.state {
        case .greeting: return "looking"
        case .connected where recoveryOnly: return "recovery"
        case .connected, .incoming: return "choose"
        case .waitingForAnswer, .partnerAccepted: return "sending"
        case .delivered: return "delivered"
        case .partnerDeclined: return "declined"
        case .ended: return "ended"
        }
    }

    @ViewBuilder
    private var content: some View {
        if !primerSeen {
            primer
        } else if let session {
            sessionScreen(session)
        } else {
            switch link?.state ?? .idle {
            case .localNetworkDenied:
                notice(Copy.localNetworkOffTitle, Copy.localNetworkOffBody, icon: "wifi.exclamationmark") {
                    Button(Copy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.vaultPrimary)
                }
            case .unavailable:
                notice(Copy.nearbyUnavailableTitle, Copy.nearbyUnavailableBody, icon: "antenna.radiowaves.left.and.right.slash") {
                    Button(Copy.tryAgain) { restart() }.buttonStyle(.vaultPrimary)
                }
            default:
                looking
            }
        }
    }

    // MARK: N0

    private var primer: some View {
        screen {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(Copy.exchangeSideBySide).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
            Text(Copy.nearbyPrimerBody).foregroundStyle(Theme.Colors.secondary)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach([Copy.nearbyOnlyWhileOpen, Copy.nearbyOnlyPartner, Copy.nearbyRadios], id: \.self) { line in
                    Label(line, systemImage: "checkmark").foregroundStyle(Theme.Colors.text)
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        } footer: {
            Button(Copy.continueLabel) {
                primerSeen = true
                restart()
            }
            .buttonStyle(.vaultPrimary)
            sendAsFileInstead
        }
    }

    // MARK: N1

    private var looking: some View {
        screen {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                .frame(maxWidth: .infinity)
                // The text below says it.
                .accessibilityHidden(true)
            Text(Copy.lookingForPartner)
                .font(Theme.Typography.title3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Text(Copy.lookingHint)
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        } footer: {
            Text(Copy.randomCodeOnly)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
            sendAsFileInstead
        }
        .onAppear { if link == nil { restart() } }
    }

    // MARK: N2 to N5

    @ViewBuilder
    private func sessionScreen(_ session: NearbySession) -> some View {
        switch session.state {
        case .greeting:
            looking
        case .connected where recoveryOnly:
            recoveryScreen(session)
        case .connected, .incoming:
            choose(session)
                .sheet(isPresented: Binding(get: { isIncoming(session) }, set: { _ in })) {
                    if case let .incoming(incoming) = session.state { incomingSheet(incoming, session: session) }
                }
        case let .waitingForAnswer(count), let .partnerAccepted(count):
            sending(session, count: count)
        case let .delivered(count):
            delivered(session, count: count)
        case .partnerDeclined:
            notice(Copy.partnerDeclinedTitle, Copy.partnerDeclinedBody, icon: "hand.raised") {
                Button(Copy.ok) { reloadAvailable() ; backToConnected(session) }.buttonStyle(.vaultPrimary)
            }
        case let .ended(ending):
            ended(ending)
        }
    }

    private func choose(_ session: NearbySession) -> some View {
        screen {
            connectedPill(Copy.connectedTo(partner.fingerprint))
            Text(Copy.sendToPartner).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
            if available.isEmpty {
                Text(Copy.nothingSealedNearby).foregroundStyle(Theme.Colors.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(available) { item in
                        Toggle(isOn: Binding(
                            get: { ticked.contains(item.id) },
                            set: { if $0 { ticked.insert(item.id) } else { ticked.remove(item.id) } }
                        )) {
                            ReflowRow {
                                Text(item.note.title).foregroundStyle(Theme.Colors.text)
                                Spacer(minLength: 0)
                                let notReceived = session.notReceived.contains(item.id)
                                Text(notReceived ? Copy.notReceived : item.isUpdate ? Copy.updateTag : Copy.newTag)
                                    .font(Theme.Typography.badge)
                                    .foregroundStyle(notReceived || item.isUpdate ? Theme.Colors.sealedBadgeInk : Theme.Colors.privateBadgeInk)
                            }
                        }
                        .toggleStyle(CheckboxStyle())
                        .padding(.vertical, Theme.Space.sm)
                        if item.id != available.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                Text(session.notReceived.isEmpty ? Copy.untickToKeep : Copy.untickToKeepWithNotReceived(session.notReceived.count))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            if session.receivedRecovery {
                Label(Copy.partnerRecoveryKept, systemImage: "lifepreserver")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            if session.confirmedCount > 0 {
                Label(Copy.confirmedEarlier(session.confirmedCount), systemImage: "checkmark.seal")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            Text(Copy.partnerCanSendToo)
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.destructive)
            }
        } footer: {
            Button(Copy.sendItems(ticked.count)) { send(session) }
                .buttonStyle(.vaultPrimary)
                .disabled(ticked.isEmpty)
        }
        .onAppear(perform: reloadAvailable)
    }

    /// N3: the same review as a file (R2), without Decide later: the partner is right here.
    private func incomingSheet(_ incoming: ImportService.Incoming, session: NearbySession) -> some View {
        IncomingReview(
            incoming: incoming,
            source: .nearby,
            accept: { resolutions in try session.accept(resolutions: resolutions) },
            decline: { session.decline() }
        )
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    /// Board P2's action over the connection: send, then the partner's phone says it kept it.
    private func recoveryScreen(_ session: NearbySession) -> some View {
        screen {
            connectedPill(Copy.connectedTo(partner.fingerprint))
            switch session.recovery {
            case .delivered:
                Image(systemName: "checkmark")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.onAccentTint)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(Copy.recoveryCopyUpdated).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
                Text(Copy.recoveryCopyUpdatedBody).foregroundStyle(Theme.Colors.secondary)
            case .refused:
                Text(Copy.recoveryCopyRefused).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
                Text(Copy.recoveryCopyRefusedBody).foregroundStyle(Theme.Colors.secondary)
            case .none where restoring:
                // Rows 6.1, 6.3: no key to send yet; it comes back inside the partner's copy.
                Text(Copy.waitingForTheirCopyHere).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
                Text(Copy.waitingForTheirCopyHereBody).foregroundStyle(Theme.Colors.secondary)
                ProgressView().progressViewStyle(.linear).tint(Theme.Colors.accent)
            case .none, .sending:
                Text(Copy.sendingRecoveryCopy).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
                ProgressView().progressViewStyle(.linear).tint(Theme.Colors.accent)
            }
            if restored {
                Label(Copy.vaultRestoredTitle, systemImage: "lock.open")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            if session.receivedRecovery {
                Label(Copy.partnerRecoveryKept, systemImage: "lifepreserver")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.destructive)
            }
        } footer: {
            Button(Copy.done) { close() }.buttonStyle(.vaultPrimary)
        }
        .task {
            guard session.recovery == .none else { return }
            restoring = services.awaitsRestore
            if !restoring { sendRecovery(session) }
        }
        // Their copy arrived: if it brought the vault key back, this phone's copy can go now.
        .onChange(of: session.receivedRecovery) { _, received in
            guard received, restoring else { return }
            restoring = services.awaitsRestore
            if !restoring {
                restored = true
                sendRecovery(session)
            } else {
                failure = Copy.noKeyOrNotThisVaults
            }
        }
        .sensoryFeedback(.success, trigger: session.recovery) { _, new in new == .delivered }
    }

    private func sendRecovery(_ session: NearbySession) {
        do { try session.sendRecovery() } catch { failure = Copy.recoveryFileNotMade }
    }

    private func sending(_ session: NearbySession, count: Int) -> some View {
        let accepted = if case .partnerAccepted = session.state { true } else { false }
        return screen {
            if accepted { connectedPill(Copy.partnerAccepted) }
            Text(accepted ? Copy.sendingItems(count) : Copy.waitingForPartner)
                .font(Theme.Typography.title2)
                .accessibilityAddTraits(.isHeader)
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Theme.Colors.accent)
                .accessibilityLabel(Copy.sendingItems(count))
            Text(Copy.encryptedChecked).foregroundStyle(Theme.Colors.secondary)
        } footer: {
            Text(Copy.stopNothingImported)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
            Button(Copy.stop) { close() }.buttonStyle(.vaultSecondary)
        }
    }

    private func delivered(_ session: NearbySession, count: Int) -> some View {
        NearbyDelivered(
            count: count, sent: session.sentCount, confirmed: session.confirmedCount,
            received: session.receivedCount, conflicts: session.conflictsCount,
            onDone: close, onStay: { reloadAvailable(); backToConnected(session) }
        )
    }

    private func ended(_ ending: NearbySession.Ending) -> some View {
        let (title, body) = switch ending {
        case .notYourPartner: (Copy.notYourPartnerTitle, Copy.notYourPartnerBody)
        case .newerVersion: (Copy.updateTheApp, Copy.updateTheAppBody)
        case .byPartner, .linkLost: (Copy.sessionEnded, Copy.sessionEndedBody)
        }
        return notice(title, body, icon: "personalhotspot.slash") {
            Button(Copy.done) { close() }.buttonStyle(.vaultPrimary)
        }
    }

    // MARK: Pieces

    private func connectedPill(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .font(Theme.Typography.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.onAccentTint)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.sm)
            .background(Theme.Colors.accentTint, in: Capsule())
    }

    private var sendAsFileInstead: some View {
        Button(Copy.sendAsFileInstead) {
            close()
            onSendAsFile()
        }
        .foregroundStyle(Theme.Colors.accent)
        .frame(minHeight: 44)
    }

    private func screen(@ViewBuilder _ content: () -> some View, @ViewBuilder footer: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) { content() }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) { footer() }
                .padding(Theme.Space.lg)
                .background(Theme.Colors.bg)
        }
    }

    private func notice(_ title: String, _ body: String, icon: String, @ViewBuilder action: () -> some View) -> some View {
        screen {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(title).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
            Text(body).foregroundStyle(Theme.Colors.secondary)
        } footer: {
            action()
            sendAsFileInstead
        }
    }

    // MARK: Actions

    private func restart() {
        link?.stop()
        let link = NearbyLink(pairKey: pairKey)
        self.link = link
        session = nil
        link.start()
    }

    private func begin(on connection: NearbyConnection) {
        let session = NearbySession(
            transport: connection,
            exchange: services.exchangeService,
            importer: services.importService,
            log: services.exchangeLogRepository,
            me: services.deviceID,
            partner: partner.deviceID,
            makeRecovery: { try services.recoveryFileData() },
            keepRecovery: { _ = try services.receiveRecoveryFile($0) },
            holdsRecovery: { services.holdsPartnerRecovery },
            partnerHoldsRecovery: { RecoveryStatus().partnerHolds($0) }
        )
        self.session = session
        session.start()
        reloadAvailable()
    }

    private func reloadAvailable() {
        available = (try? services.exchangeService.sealedForNearby()) ?? []
        ticked = Set(available.map(\.id))
    }

    private func send(_ session: NearbySession) {
        do {
            try session.send(ticked)
            failure = nil
        } catch ExchangeService.ExchangeError.nothingSealed {
            // What was ticked is no longer sealed (confirmed meanwhile): show what is left.
            reloadAvailable()
            failure = nil
        } catch {
            failure = Copy.packageNotMade
        }
    }

    private func backToConnected(_ session: NearbySession) {
        session.resume()
    }

    private func isIncoming(_ session: NearbySession) -> Bool {
        if case .incoming = session.state { true } else { false }
    }

    private func close() {
        session?.end()
        link?.stop()
        dismiss()
    }
}

/// N2's round ticks.
private struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Theme.Colors.accent : Theme.Colors.tertiary)
                    .accessibilityHidden(true)
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// Board N5, "Delivered and accepted".
struct NearbyDelivered: View {
    let count: Int
    let sent: Int
    let confirmed: Int
    let received: Int
    let conflicts: Int
    let onDone: () -> Void
    let onStay: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Image(systemName: "checkmark")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.onAccentTint)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(Copy.deliveredAndAccepted).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
                Text(Copy.partnerHasAll(count)).foregroundStyle(Theme.Colors.secondary)
                VStack(spacing: Theme.Space.sm) {
                    LabeledContent(Copy.sent, value: "\(sent)")
                    LabeledContent(Copy.earlierFileSendsConfirmed, value: "\(confirmed)")
                    LabeledContent(Copy.received, value: "\(received)")
                    LabeledContent(Copy.conflicts, value: conflicts == 0 ? Copy.noneWord : "\(conflicts)")
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(Copy.done, action: onDone).buttonStyle(.vaultPrimary)
                Button(Copy.stayConnected, action: onStay).buttonStyle(.vaultSecondary)
                Text(Copy.doneEndsSession)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.bg)
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
    }
}
