import SwiftUI
import UIKit

/// Rows 4.2, 4.3, 4.5, 4.6: board 7 (with U3's New and Update), the review sheet (8), the handoff
/// and Recently exchanged (18). Receiving lands with cycle 5; "Waiting for me" is its shell.
struct ExchangeView: View {
    @Environment(AppServices.self) private var services
    @State private var tab = Tab.ready
    @State private var outbox: [ExchangeService.OutboxItem] = []
    @State private var paired = false
    @State private var reviewing = false
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
                ReviewSheet(items: outbox) { sentToast = true }
            }
            .overlay(alignment: .bottom) {
                if sentToast {
                    Toast(systemImage: "checkmark.circle", text: Copy.toastExchangeReady)
                        .padding(.bottom, Theme.Space.lg)
                        .transition(.opacity)
                }
            }
            .task(id: sentToast) {
                guard sentToast else { return }
                AccessibilityNotification.Announcement(Copy.toastExchangeReady).post()
                try? await Task.sleep(for: .seconds(2))
                withAnimation { sentToast = false }
            }
            .sensoryFeedback(.success, trigger: sentToast) { _, new in new }
        }
    }

    // MARK: Board 7, U3

    @ViewBuilder
    private var readyToSend: some View {
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
                Button(Copy.reviewAndSend) { reviewing = true }
                    .buttonStyle(.vaultPrimary)
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

    private var waitingForMe: some View {
        Section {
            EmptyState(systemImage: "tray.and.arrow.down", headline: Copy.nothingWaiting, message: Copy.openPartnerFile)
        }
        .listRowBackground(Theme.Colors.bg)
    }

    private func reload() {
        outbox = (try? services.exchangeService.outbox()) ?? []
        paired = ((try? services.partnerRepository.partner()) ?? nil) != nil
    }
}

// MARK: - Board 8

/// "Exactly what leaves this iPhone": names and categories, never body text. Cancel is the same
/// size as Encrypt & Share. Nothing changes until the share sheet reports the handoff done.
private struct ReviewSheet: View {
    let items: [ExchangeService.OutboxItem]
    let onSent: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.itemsEncrypted(items.count))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                }
                .listRowBackground(Color.clear)
                Section {
                    ForEach(items) { ReviewRow(title: $0.note.title, categoryName: $0.categoryName) }
                }
                .listRowBackground(Theme.Colors.surface)
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(Copy.included).bold() + Text(" ") + Text(Copy.includedLine(items.count))
                        Text(Copy.notIncluded).bold() + Text(" ") + Text(Copy.notIncludedLine)
                        Text(Copy.handOverNext).foregroundStyle(Theme.Colors.secondary)
                    }
                    .font(Theme.Typography.subheadline)
                } footer: {
                    Text(Copy.sentNotDelivered)
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
            .navigationTitle(Copy.exactlyWhatLeaves)
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
                    Button(Copy.encryptAndShare, action: share)
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
            prepared = try services.exchangeService.prepare()
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
            do {
                try services.exchangeService.markSent(prepared)
                onSent()
                dismiss()
            } catch {
                failure = Copy.sentNotRecorded
            }
        }
    }
}

/// The system share sheet, from UIKit: SwiftUI's ShareLink cannot tell a completed handoff from a
/// cancelled one, and "Shared means sent" depends on exactly that.
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
                            Text(entry.direction == .sent ? Copy.sentItems(entry.itemCount) : Copy.receivedItems(entry.itemCount))
                                .foregroundStyle(Theme.Colors.text)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
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
}
