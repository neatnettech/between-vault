import SwiftUI

/// Rows 5.2, 5.6, 5.8: the review of a file from the partner (boards 9 and U4), one conflict sheet
/// per item changed on both phones (board 10), and the failures (9a to 9d). Nothing is written
/// until Accept, and then all of it at once.
struct ImportReviewView: View {
    enum Content {
        /// R2. `data` is the package as it arrived, kept only if the owner decides later.
        case review(ImportService.Incoming, data: Data, receivedAt: Date)
        case failed(ImportService.ImportFailure)
    }

    /// How the review ended, for the caller's toast.
    enum Outcome {
        case imported(Int)
        case declined
        case keptForLater
        case closed
    }

    let content: Content
    let onDone: (Outcome) -> Void

    @Environment(AppServices.self) private var services
    /// R3, once accepted.
    @State private var result: (incoming: ImportService.Incoming, resolutions: [UUID: ImportService.Resolution])?

    var body: some View {
        NavigationStack {
            switch content {
            case let .review(incoming, data, receivedAt):
                if let result {
                    ImportResult(incoming: result.incoming, resolutions: result.resolutions) {
                        onDone(.imported(result.incoming.changingCount))
                    }
                } else {
                    IncomingReview(
                        incoming: incoming,
                        source: .file(receivedAt: receivedAt),
                        accept: { resolutions in
                            try services.importService.accept(incoming, resolutions: resolutions)
                            // R3: accepted, so it no longer waits; the file itself is already gone.
                            try? services.pendingPackages.remove(incoming.exchangeID)
                            result = (incoming, resolutions)
                        },
                        decline: {
                            try? services.importService.decline(incoming)
                            try? services.pendingPackages.remove(incoming.exchangeID)
                            onDone(.declined)
                        },
                        decideLater: {
                            // The only way a file waits: the encrypted package, never its titles.
                            try? services.pendingPackages.keep(
                                exchangeID: incoming.exchangeID, data: data, itemCount: incoming.items.count, at: receivedAt
                            )
                            onDone(.keptForLater)
                        }
                    )
                }
            case let .failed(failure):
                failed(failure)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Boards 9a to 9d

    @ViewBuilder
    private func failed(_ failure: ImportService.ImportFailure) -> some View {
        switch failure {
        case .damaged:
            FailureCard(icon: "exclamationmark.triangle", title: Copy.cantBeOpened, message: Copy.cantBeOpenedBody,
                        emphasis: Copy.nothingImported, footnote: Copy.cantBeOpenedFootnote) { done }
        case .wrongDevice:
            FailureCard(icon: "iphone.slash", title: Copy.forDifferentIPhone, message: Copy.forDifferentIPhoneBody,
                        emphasis: Copy.nothingImported, footnote: Copy.forDifferentIPhoneHint) { done }
        case .newerVersion:
            FailureCard(icon: "arrow.down.app", title: Copy.updateTheApp, message: Copy.updateTheAppBody,
                        emphasis: Copy.nothingImported, footnote: nil) {
                Button(Copy.openAppStore) {
                    if let url = URL(string: "itms-apps://apps.apple.com") { UIApplication.shared.open(url) }
                }
                .buttonStyle(.vaultPrimary)
                Button(Copy.later) { onDone(.closed) }.buttonStyle(.vaultSecondary)
            }
        case let .alreadyImported(date):
            FailureCard(icon: "checkmark.circle", title: Copy.youAlreadyHaveThis, message: Copy.importedOn(date),
                        emphasis: nil, footnote: nil) { done }
        case .notPaired:
            FailureCard(icon: "person.2", title: Copy.cantBeOpened, message: Copy.pairFirstToOpen,
                        emphasis: Copy.nothingImported, footnote: nil) { done }
        case .empty:
            FailureCard(icon: "tray", title: Copy.cantBeOpened, message: Copy.emptyPackage,
                        emphasis: nil, footnote: nil) { done }
        }
    }

    private var done: some View {
        Button(Copy.done) { onDone(.closed) }.buttonStyle(.vaultPrimary)
    }
}

// MARK: - Board 10

/// One item changed on both phones: dates and length, never a diff of content, all three answers
/// always visible, none chosen for the owner.
struct ConflictSheet: View {
    let item: ImportService.Item
    let index: Int
    let count: Int
    let choose: (ImportService.Resolution) -> Void

    private var local: Note? {
        if case let .conflict(local) = item.change { local } else { nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Label(Copy.conflictCounter(index, count), systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.sealedBadgeInk)
                Text(item.incoming.title)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits {
                    HStack(alignment: .top, spacing: Theme.Space.sm) { cards }
                    VStack(spacing: Theme.Space.sm) { cards }
                }
                VStack(spacing: Theme.Space.sm) {
                    Button(Copy.keepMine) { choose(.keepMine) }.buttonStyle(.vaultSecondary)
                    Button(Copy.keepPartners) { choose(.keepPartners) }.buttonStyle(.vaultSecondary)
                    Button(Copy.keepBothAsCopy) { choose(.keepBoth) }.buttonStyle(.vaultPrimary)
                }
                Text(Copy.keepingBothAdds(item.incoming.title))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.Colors.bg)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var cards: some View {
        if let local {
            card(Copy.yours, edited: local.updatedAt, body: local.body)
        }
        card(Copy.partners, edited: item.incoming.updatedAt, body: item.incoming.body)
    }

    private func card(_ label: String, edited: Date, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
            Text(Copy.editedAgo(edited)).font(Theme.Typography.subheadline.weight(.semibold))
            Text(Copy.lineCount(body.split(separator: "\n", omittingEmptySubsequences: false).count))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.secondary)
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .accessibilityElement(children: .combine)
    }
}

/// Boards 9a to 9d: one layout, an icon, what happened, buttons pinned below.
private struct FailureCard<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    let emphasis: String?
    let footnote: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(title).font(Theme.Typography.title2).foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(Theme.Typography.body).foregroundStyle(Theme.Colors.secondary)
                if let emphasis { Text(emphasis).font(Theme.Typography.body.weight(.semibold)) }
                if let footnote { Text(footnote).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary) }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) { actions }
                .padding(Theme.Space.lg)
                .background(Theme.Colors.bg)
        }
    }
}
