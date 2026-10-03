import SwiftUI

/// Boards N0 to N5: Exchange nearby. N0 once, before iOS asks for local network access; then the
/// link (part C) looks for the partner's phone (N1) and the session (part B) runs on it: choose
/// what to send (N2), the partner's Accept or Decline (N3), progress (N4), done (N5).
struct NearbyView: View {
    let partner: Partner
    let pairKey: Data
    let onSendAsFile: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    /// N0 is shown once; after that the screen goes straight to looking.
    @AppStorage("betweenvault.nearbyPrimerSeen") private var primerSeen = false
    @State private var link: NearbyLink?
    @State private var session: NearbySession?
    @State private var available: [ExchangeService.OutboxItem] = []
    @State private var ticked = Set<UUID>()
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
        .onChange(of: session?.notReceived) { reloadAvailable() }
        .sensoryFeedback(.success, trigger: deliveredCount) { _, new in new > 0 }
    }

    private var deliveredCount: Int {
        if case let .delivered(count) = session?.state { count } else { 0 }
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
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Copy.lookingForPartner)
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
                            HStack {
                                Text(item.note.title).foregroundStyle(Theme.Colors.text)
                                Spacer()
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
            if session.confirmedCount > 0 {
                Label(Copy.confirmedEarlier(session.confirmedCount), systemImage: "checkmark.seal")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.onAccentTint)
            }
            Text(Copy.partnerCanSendToo)
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            if let failure { Text(failure).foregroundStyle(Theme.Colors.destructive) }
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
        screen {
            Image(systemName: "checkmark")
                .font(.title)
                .foregroundStyle(Theme.Colors.onAccentTint)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(Copy.deliveredAndAccepted).font(Theme.Typography.title2).accessibilityAddTraits(.isHeader)
            Text(Copy.partnerHasAll(count)).foregroundStyle(Theme.Colors.secondary)
            VStack(spacing: Theme.Space.sm) {
                LabeledContent(Copy.sent, value: "\(session.sentCount)")
                LabeledContent(Copy.earlierFileSendsConfirmed, value: "\(session.confirmedCount)")
                LabeledContent(Copy.received, value: "\(session.receivedCount)")
                LabeledContent(Copy.conflicts, value: session.conflictsCount == 0 ? Copy.noneWord : "\(session.conflictsCount)")
            }
            .padding(Theme.Space.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        } footer: {
            Button(Copy.done) { close() }.buttonStyle(.vaultPrimary)
            Button(Copy.stayConnected) { reloadAvailable(); backToConnected(session) }.buttonStyle(.vaultSecondary)
            Text(Copy.doneEndsSession)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
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
            partner: partner.deviceID
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
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
