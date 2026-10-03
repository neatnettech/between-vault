import SwiftUI
import UIKit

/// Rows 4.2, 4.3, 4.5, 4.6: board 7 (with U3's New and Update), the review sheet (8), the handoff
/// and Recently exchanged (18). Receiving lands with cycle 5; "Waiting for me" is its shell.
struct ExchangeView: View {
    @Environment(AppServices.self) private var services
    @State private var tab = Tab.ready
    @State private var outbox: [ExchangeService.OutboxItem] = []
    @State private var unconfirmed: [ExchangeService.OutboxItem] = []
    @State private var lastFileSend: Date?
    @State private var paired = false
    @State private var reviewing = false
    @State private var resending = false
    @State private var nearby = false
    @State private var partner: Partner?
    @State private var sentToast = false

    private enum Tab: Hashable { case ready, waiting }

    var body: some View {
        NavigationStack {
            List {
                Picker(Copy.tabExchange, selection: $tab) {
                    Text(Copy.readyToSendCount(outbox.count)).tag(Tab.ready)
                    Text(Copy.waitingForMe).tag(Tab.waiting)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // The main action once paired: both phones side by side, every step in the app.
                if paired {
                    Section {
                        Button {
                            nearby = true
                        } label: {
                            Label(Copy.exchangeNearby, systemImage: "iphone.radiowaves.left.and.right")
                        }
                        .buttonStyle(.vaultPrimary)
                    }
                    .listRowBackground(Color.clear)
                }

                switch tab {
                case .ready: readyToSend
                case .waiting: waitingForMe
                }

                Section {
                    NavigationLink(Copy.recentlyExchanged) { HistoryView() }
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabExchange)
            .task { reload() }
            .refreshable { reload() }
            .sheet(isPresented: $reviewing, onDismiss: reload) {
                ReviewSheet(items: outbox, resend: false) { sentToast = true }
            }
            .sheet(isPresented: $resending, onDismiss: reload) {
                ReviewSheet(items: unconfirmed, resend: true) { sentToast = true }
            }
            .fullScreenCover(isPresented: $nearby, onDismiss: reload) {
                if let partner, let key = try? KeyManager.load(Pairing.pairKeyAccount) {
                    NearbyView(partner: partner, pairKey: key) {
                        // Board N0/N1 "Send as a file instead": after the cover is gone.
                        Task { try? await Task.sleep(for: .milliseconds(400)); reviewing = !outbox.isEmpty }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if sentToast {
                    Toast(systemImage: "paperplane", text: Copy.toastFileHandedOver)
                        .padding(.bottom, Theme.Space.lg)
                        .transition(.opacity)
                }
            }
            .task(id: sentToast) {
                guard sentToast else { return }
                AccessibilityNotification.Announcement(Copy.toastFileHandedOver).post()
                try? await Task.sleep(for: .seconds(2))
                withAnimation { sentToast = false }
            }
            .sensoryFeedback(.success, trigger: sentToast) { _, new in new }
        }
    }

    // MARK: Board 7, U3

    @ViewBuilder
    private var readyToSend: some View {
        if !unconfirmed.isEmpty { sentNotConfirmed }
        if outbox.isEmpty {
            Section {
                EmptyState(systemImage: "tray", headline: Copy.nothingSealedYet, message: Copy.sealANote)
            }
            .listRowBackground(Theme.Colors.bg)
        } else {
            Section {
                ForEach(outbox) { item in
                    HStack {
                        ReviewRow(title: item.note.title, categoryName: item.categoryName)
                        Spacer()
                        Text(item.isUpdate ? Copy.updateTag : Copy.newTag)
                            .font(Theme.Typography.badge)
                            .foregroundStyle(item.isUpdate ? Theme.Colors.sharedBadgeInk : Theme.Colors.sealedBadgeInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(Copy.outboxFooter)
                    if outbox.contains(where: \.isUpdate) { Text(Copy.updateFooter) }
                }
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                // F1: the fallback for when the phones are not side by side.
                Button(Copy.sendAsFile) { reviewing = true }
                    .buttonStyle(.vaultSecondary)
                    .disabled(!paired)
                if !paired {
                    Text(Copy.pairFirstToSend)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    /// Board F2: sent as a file, waiting for the partner's phone to confirm it. Nobody can see
    /// whether a file arrived, so this stays until it is confirmed during an exchange nearby.
    private var sentNotConfirmed: some View {
        Section {
            Text(Copy.sentAsFileBanner(lastFileSend))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.changedFlagInk)
                .listRowBackground(Theme.Colors.changedFlagBG)
            ForEach(unconfirmed) { item in
                HStack {
                    Text(item.note.title).foregroundStyle(Theme.Colors.text)
                    Spacer()
                    StateBadge(state: .sealed, sentNotConfirmed: true)
                }
                .accessibilityElement(children: .combine)
            }
            Button(Copy.confirmNearbyNow) { nearby = true }
                .foregroundStyle(Theme.Colors.accent)
                .disabled(!paired)
            Button(Copy.sendFileAgain) { resending = true }
                .foregroundStyle(Theme.Colors.accent)
                .disabled(!paired)
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var waitingForMe: some View {
        Section {
            EmptyState(systemImage: "tray.and.arrow.down", headline: Copy.nothingWaiting, message: Copy.openPartnerFile)
        }
        .listRowBackground(Theme.Colors.bg)
    }

    private func reload() {
        outbox = (try? services.exchangeService.outbox()) ?? []
        unconfirmed = (try? services.exchangeService.unconfirmed()) ?? []
        lastFileSend = ((try? services.exchangeLogRepository.history()) ?? []).first { $0.unconfirmed }?.date
        partner = (try? services.partnerRepository.partner()) ?? nil
        paired = partner != nil
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
                HStack(spacing: Theme.Space.sm) {
                    Button(Copy.cancel) { dismiss() }
                        .buttonStyle(.vaultSecondary)
                    Button(Copy.createEncryptedFile, action: share)
                        .buttonStyle(.vaultPrimary)
                }
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
