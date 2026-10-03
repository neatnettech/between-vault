import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Board X1 to X3: the Exchange tab with its exchange area (replaces boards 7 and 9). The area
/// on top holds the partner, the counts and the one main action, Exchange nearby; below it, what
/// is to send, files waiting for a decision, and History. Not paired, only the way to pair.
struct ExchangeView: View {
    /// X3 Pair now: the Partner tab, where pairing starts.
    var onPairNow: () -> Void = {}

    @Environment(AppServices.self) private var services
    @State private var outbox: [ExchangeService.OutboxItem] = []
    @State private var unconfirmed: [ExchangeService.OutboxItem] = []
    @State private var waiting: [PendingPackage] = []
    @State private var lastEntry: ExchangeLogEntry?
    @State private var lastFileSend: Date?
    @State private var partner: Partner?
    @State private var sendingFile = false
    @State private var resending = false
    @State private var nearby = false
    @State private var addingNotes = false
    @State private var opening = false
    @State private var reviewing: ImportReviewView.Content?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if partner == nil {
                        notPaired
                    } else {
                        exchangeArea
                        toSend
                        waitingForYou
                        historyRow
                    }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabExchange)
            .task { reload() }
            .refreshable { reload() }
            .sheet(isPresented: $sendingFile, onDismiss: reload) {
                ReviewSheet(items: outbox, resend: false) { toast = Copy.toastFileHandedOver }
            }
            .sheet(isPresented: $resending, onDismiss: reload) {
                ReviewSheet(items: unconfirmed, resend: true) { toast = Copy.toastFileHandedOver }
            }
            .sheet(isPresented: $addingNotes, onDismiss: reload) { AddNotesSheet() }
            .sheet(item: $reviewing, onDismiss: reload) { content in
                ImportReviewView(content: content) { outcome in
                    reviewing = nil
                    toast = BetweenVaultApp.toast(for: outcome)
                }
            }
            .fullScreenCover(isPresented: $nearby, onDismiss: reload) {
                if let partner, let key = try? KeyManager.load(Pairing.pairKeyAccount) {
                    NearbyView(partner: partner, pairKey: key) {
                        // N0, N1 "Send as a file instead": once the cover is gone.
                        Task { try? await Task.sleep(for: .milliseconds(400)); sendingFile = !outbox.isEmpty }
                    }
                }
            }
            // Waiting for you: Open a file, for a file saved in the Files app.
            .fileImporter(isPresented: $opening, allowedContentTypes: [UTType(exportedAs: "tech.neatnet.nvlt")]) { result in
                if case let .success(url) = result { review(fileAt: url) }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Toast(systemImage: "checkmark.circle", text: toast)
                        .padding(.bottom, Theme.Space.lg)
                        .transition(.opacity)
                }
            }
            .task(id: toast) {
                guard let toast else { return }
                AccessibilityNotification.Announcement(toast).post()
                try? await Task.sleep(for: .seconds(2))
                withAnimation { self.toast = nil }
            }
            .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
        }
    }

    // MARK: X1, X2: the exchange area

    private var exchangeArea: some View {
        DarkPanel {
            PanelHeader(
                title: Copy.withYourPartner,
                subtitle: lastEntry.map { Copy.lastExchange($0.date) },
                pill: Copy.pairedPill,
                pillIcon: "checkmark"
            )
            HStack(spacing: Theme.Space.xs) {
                PanelChip(text: Copy.toSendChip(outbox.count))
                PanelChip(text: Copy.waitingChip(waiting.count))
                if !unconfirmed.isEmpty { PanelChip(text: Copy.notConfirmedChip(unconfirmed.count)) }
            }
            PanelPrimaryButton(title: Copy.exchangeNearby, systemImage: "iphone.radiowaves.left.and.right") { nearby = true }
            Text(outbox.isEmpty && unconfirmed.isEmpty ? Copy.nothingToSendCaption : Copy.nearbyCaption(notConfirmed: unconfirmed.count))
                .font(Theme.Typography.footnote)
                .opacity(0.75)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            PanelAltRow(
                title: Copy.sendAsFileInstead,
                subtitle: outbox.isEmpty ? Copy.addNotesFirst : Copy.fileOptionSub,
                systemImage: "doc.badge.arrow.up",
                enabled: !outbox.isEmpty
            ) { sendingFile = true }
        }
        .accessibilityLabel(Copy.withYourPartner)
    }

    // MARK: X1, X2: To send

    private var toSend: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionHeader(Copy.toSendSection(outbox.count), link: outbox.isEmpty ? nil : (Copy.addNotes, "plus", { addingNotes = true }))
            if outbox.isEmpty {
                card {
                    Button { addingNotes = true } label: {
                        Label(Copy.addNotesToSend, systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            } else {
                card {
                    ForEach(outbox) { item in
                        HStack {
                            Text(item.note.title).foregroundStyle(Theme.Colors.text)
                            Spacer()
                            tag(item.isUpdate ? Copy.updateTag : Copy.newTag, amber: item.isUpdate)
                        }
                        .accessibilityElement(children: .combine)
                        if item.id != outbox.last?.id { Divider() }
                    }
                }
            }
            // F2 as a drill-in: notes sent as a file, waiting for confirmation.
            if !unconfirmed.isEmpty {
                NavigationLink {
                    SentAsFileView(items: unconfirmed, sentAt: lastFileSend, onNearby: { nearby = true }, onResend: { resending = true })
                } label: {
                    card {
                        HStack {
                            Image(systemName: "doc.badge.clock").foregroundStyle(Theme.Colors.secondary)
                            Text(Copy.sentAsFileNotConfirmed).foregroundStyle(Theme.Colors.text)
                            Spacer()
                            Text("\(unconfirmed.count)").foregroundStyle(Theme.Colors.secondary)
                            Image(systemName: "chevron.right").font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: X1, X2: Waiting for you

    private var waitingForYou: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionHeader(Copy.waitingSection(waiting.count), link: (Copy.openAFile, "folder", { opening = true }))
            card {
                if waiting.isEmpty {
                    Text(Copy.nothingWaiting).foregroundStyle(Theme.Colors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(waiting) { file in
                        Button { review(file) } label: {
                            HStack {
                                Text(Copy.fileFromPartner).foregroundStyle(Theme.Colors.text)
                                Text(Copy.itemsSuffix(file.itemCount)).foregroundStyle(Theme.Colors.secondary)
                                Spacer()
                                Text(Copy.review).foregroundStyle(Theme.Colors.accent)
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        if file.id != waiting.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var historyRow: some View {
        NavigationLink { HistoryView() } label: {
            card {
                HStack {
                    Text(Copy.history).foregroundStyle(Theme.Colors.text)
                    Spacer()
                    if let lastEntry {
                        Text(Copy.historySummary(lastEntry)).foregroundStyle(Theme.Colors.secondary)
                    }
                    Image(systemName: "chevron.right").font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.tertiary)
                }
            }
        }
    }

    // MARK: X3: not paired

    private var notPaired: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            DarkPanel {
                PanelHeader(title: Copy.pairFirstTitle, subtitle: Copy.pairFirstSub, pill: Copy.notPairedPill, pillMuted: true)
                Text(Copy.pairFirstBody).font(Theme.Typography.subheadline).opacity(0.85)
                PanelPrimaryButton(title: Copy.pairNow, systemImage: "iphone.radiowaves.left.and.right", action: onPairNow)
            }
            Text(Copy.gotAFileAlready)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ title: String, link: (String, String, () -> Void)?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondary)
            Spacer()
            if let link {
                Button(action: link.2) { Label(link.0, systemImage: link.1) }
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) { content() }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    /// X1: New grey, Update amber.
    private func tag(_ text: String, amber: Bool) -> some View {
        Text(text)
            .font(Theme.Typography.badge)
            .foregroundStyle(amber ? Theme.Colors.sealedBadgeInk : Theme.Colors.privateBadgeInk)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.xs)
            .background(amber ? Theme.Colors.sealedBadgeBG : Theme.Colors.privateBadgeBG, in: Capsule())
    }

    // MARK: Actions

    private func reload() {
        partner = (try? services.partnerRepository.partner()) ?? nil
        outbox = (try? services.exchangeService.outbox()) ?? []
        unconfirmed = (try? services.exchangeService.unconfirmed()) ?? []
        waiting = (try? services.pendingPackages.all()) ?? []
        let history = (try? services.exchangeLogRepository.history()) ?? []
        lastEntry = history.first
        lastFileSend = history.first { $0.unconfirmed }?.date
    }

    /// A waiting file: checked again, then the same review as when it arrived. One that no longer
    /// opens (already imported, or the pairing changed) stops waiting and says why.
    private func review(_ file: PendingPackage) {
        do {
            reviewing = .review(try services.importService.inspect(file.data), data: file.data, receivedAt: file.receivedAt)
        } catch let failure as ImportService.ImportFailure {
            try? services.pendingPackages.remove(file.exchangeID)
            reviewing = .failed(failure)
        } catch {
            reviewing = .failed(.damaged)
        }
    }

    /// Open a file: a .nvlt picked in the Files app.
    private func review(fileAt url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            reviewing = .review(try services.importService.inspect(data), data: data, receivedAt: .now)
        } catch let failure as ImportService.ImportFailure {
            reviewing = .failed(failure)
        } catch {
            reviewing = .failed(.damaged)
        }
    }
}

extension ImportReviewView.Content: Identifiable {
    var id: String {
        switch self {
        case let .review(incoming, _, _): incoming.exchangeID
        case let .failed(failure): "\(failure)"
        }
    }
}

// MARK: - F2, drilled into from To send

/// Board F2: notes sent as a file, not yet confirmed. A nearby exchange confirms them, or sends
/// them again if they never arrived.
private struct SentAsFileView: View {
    let items: [ExchangeService.OutboxItem]
    let sentAt: Date?
    let onNearby: () -> Void
    let onResend: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(Copy.sentAsFileF2Banner(sentAt))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.changedFlagInk)
                    .padding(Theme.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.changedFlagBG, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                VStack(spacing: Theme.Space.sm) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.note.title).foregroundStyle(Theme.Colors.text)
                            Spacer()
                            StateBadge(state: .sealed, sentNotConfirmed: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
            .padding(Theme.Space.md)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(Copy.exchangeNearbyToConfirm, action: onNearby).buttonStyle(.vaultPrimary)
                Button(Copy.sendFileAgain, action: onResend).foregroundStyle(Theme.Colors.accent).frame(minHeight: 44)
            }
            .padding(Theme.Space.md)
            .background(Theme.Colors.bg)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.sendAsFile)
    }
}

// MARK: - Boards 8 and F1

/// Send as a file: board F1's explanation over board 8's "exactly what leaves": names and
/// categories, never body text. Cancel is the same size as Create encrypted file. After the
/// handoff the notes are "Sent · not confirmed" (F2); only the partner's phone confirms them.
private struct ReviewSheet: View {
    let items: [ExchangeService.OutboxItem]
    /// F2's Send the file again: the notes still waiting for confirmation.
    let resend: Bool
    let onSent: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.sendAsFileBody)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                }
                .listRowBackground(Color.clear)
                Section {
                    ForEach(Array([Copy.fileStep1, Copy.fileStep2, Copy.fileStep3].enumerated()), id: \.offset) { number, step in
                        Label {
                            Text(step)
                        } icon: {
                            Text("\(number + 1)")
                                .font(Theme.Typography.footnote.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .background(Theme.Colors.privateBadgeBG, in: Circle())
                                .foregroundStyle(Theme.Colors.privateBadgeInk)
                        }
                    }
                } footer: {
                    Text(Copy.cantSeeArrival)
                }
                .listRowBackground(Theme.Colors.surface)
                Section {
                    ForEach(items) { ReviewRow(title: $0.note.title, categoryName: $0.categoryName) }
                } header: {
                    Text(Copy.itemsEncrypted(items.count))
                }
                .listRowBackground(Theme.Colors.surface)
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(Copy.included).bold() + Text(" ") + Text(Copy.includedLine(items.count))
                        Text(Copy.notIncluded).bold() + Text(" ") + Text(Copy.notIncludedLine)
                        Text(Copy.handOverNext).foregroundStyle(Theme.Colors.secondary)
                    }
                    .font(Theme.Typography.subheadline)
                }
                .listRowBackground(Theme.Colors.surface)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.destructive)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.sendAsFile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Board 8: two equal buttons, Cancel never smaller than send.
                EqualButtons(secondary: Copy.cancel, primary: Copy.createEncryptedFile,
                             onSecondary: { dismiss() }, onPrimary: share)
                .padding(Theme.Space.md)
                .background(Theme.Colors.bg)
            }
        }
    }

    private func share() {
        let prepared: ExchangeService.Prepared
        do {
            prepared = try services.exchangeService.prepare(resend: resend)
        } catch {
            failure = Copy.packageNotMade
            return
        }
        failure = nil
        // Choosing a contact or a folder is not a touch on the app, so it counts as activity for
        // auto lock while the sheet is up, at most 5 minutes, as in pairing.
        let keepAwake = Task {
            for _ in 0..<60 {
                lockManager.noteActivity()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        presentShareSheet(prepared.file) { completed, sheetClosed in
            guard completed else {
                // An activity cancelled inside a sheet that stays up (Messages, then Cancel) keeps
                // the file for another try; only the sheet closing ends the attempt.
                if sheetClosed {
                    keepAwake.cancel()
                    services.exchangeService.discard(prepared)
                }
                return
            }
            keepAwake.cancel()
            // iOS reports AirDrop done even when the transfer was interrupted (found on two
            // phones), so a handover proves only that the file left: "Sent · not confirmed".
            do {
                try services.exchangeService.markHandedOver(prepared)
                onSent()
                dismiss()
            } catch {
                failure = Copy.sentNotRecorded
            }
        }
    }
}

/// The system share sheet, from UIKit: SwiftUI's ShareLink cannot tell a completed handoff from a
/// cancelled one, and a cancel must leave the notes in the outbox.
@MainActor
/// `completion(completed, sheetClosed)`: no activity type means the sheet itself was dismissed.
private func presentShareSheet(_ file: URL, completion: @escaping (Bool, Bool) -> Void) {
    let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    sheet.completionWithItemsHandler = { activityType, completed, _, _ in
        MainActor.assumeIsolated { completion(completed, activityType == nil) }
    }
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
    while let next = top?.presentedViewController { top = next }
    top?.present(sheet, animated: true)
}

// MARK: - Board 18

private struct HistoryView: View {
    @Environment(AppServices.self) private var services
    @State private var entries: [ExchangeLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                EmptyState(systemImage: "clock.arrow.circlepath", headline: Copy.noExchangesYet, message: Copy.exchangeHistoryHint)
                    .listRowBackground(Theme.Colors.bg)
            } else {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(Self.title(entry)).foregroundStyle(Theme.Colors.text)
                            Text(Self.detail(entry))
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text(Copy.historyFooter)
                }
                .listRowBackground(Theme.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.recentlyExchanged)
        .task { entries = (try? services.exchangeLogRepository.history()) ?? [] }
    }

    private static func title(_ entry: ExchangeLogEntry) -> String {
        switch entry.direction {
        case .sent: Copy.sentItems(entry.itemCount)
        case .received: Copy.receivedItems(entry.itemCount)
        case .declined: Copy.declinedFiles(1)
        }
    }

    /// Board 18: "Today, 14:02 · 1 conflict, kept both".
    private static func detail(_ entry: ExchangeLogEntry) -> String {
        let date = entry.date.formatted(date: .abbreviated, time: .shortened)
        return entry.conflictsKeptBoth > 0 ? "\(date) · \(Copy.keptBoth(entry.conflictsKeptBoth))" : date
    }
}
