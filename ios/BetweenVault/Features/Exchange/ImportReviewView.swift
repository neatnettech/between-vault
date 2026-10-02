import SwiftUI

/// Rows 5.2, 5.6, 5.8: the review of a file from the partner (boards 9 and U4), one conflict sheet
/// per item changed on both phones (board 10), and the failures (9a to 9d). Nothing is written
/// until Accept, and then all of it at once.
struct ImportReviewView: View {
    enum Content {
        case review(ImportService.Incoming)
        case failed(ImportService.ImportFailure)
    }

    let content: Content
    let onDone: (_ importedCount: Int?) -> Void

    @Environment(AppServices.self) private var services
    @State private var resolutions: [UUID: ImportService.Resolution] = [:]
    @State private var conflictIndex: Int?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            switch content {
            case let .review(incoming): review(incoming)
            case let .failed(failure): failed(failure)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Boards 9, U4

    private func review(_ incoming: ImportService.Incoming) -> some View {
        let groups = Dictionary(grouping: incoming.items) { item -> Int in
            switch item.change {
            case .new: 0
            case .update: 1
            case .conflict: 2
            case .unchanged: 3
            }
        }
        return List {
            Section {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "envelope")
                        .foregroundStyle(Theme.Colors.onAccentTint)
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(Copy.fromYourPartner).font(Theme.Typography.body.weight(.semibold))
                        Text(Copy.verifiedLine(incoming.createdAt, count: incoming.items.count))
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Theme.Colors.surface)

            section(Copy.newSection, groups[0])
            section(Copy.updateSection, groups[1])
            section(Copy.conflictSection, groups[2], highlighted: true)
            section(Copy.unchangedSection, groups[3])

            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(Copy.titlesOnly)
                    if groups[1] != nil { Text(Copy.updatesReplace) }
                    if !incoming.conflicts.isEmpty { Text(Copy.conflictsToChoose(incoming.conflicts.count)) }
                    if let failure { Text(failure).foregroundStyle(Theme.Colors.destructive) }
                }
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.tabExchange)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.xs) {
                Button(Copy.acceptItems(incoming.items.count)) { accept(incoming) }
                    .buttonStyle(.vaultPrimary)
                Button(Copy.decline) { decline(incoming) }
                    .frame(minHeight: 44)
            }
            .padding(Theme.Space.md)
            .background(Theme.Colors.bg)
        }
        .sheet(isPresented: Binding(get: { conflictIndex != nil }, set: { if !$0 { conflictIndex = nil } })) {
            if let index = conflictIndex, index < incoming.conflicts.count {
                ConflictSheet(item: incoming.conflicts[index], index: index + 1, count: incoming.conflicts.count) { choice in
                    resolutions[incoming.conflicts[index].id] = choice
                    if index + 1 < incoming.conflicts.count {
                        conflictIndex = index + 1
                    } else {
                        conflictIndex = nil
                        apply(incoming)
                    }
                }
            }
        }
        // Handoff C8: warning when a diverged item is found.
        .sensoryFeedback(.warning, trigger: conflictIndex) { old, new in old == nil && new != nil }
    }

    @ViewBuilder
    private func section(_ header: (Int) -> String, _ items: [ImportService.Item]?, highlighted: Bool = false) -> some View {
        if let items, !items.isEmpty {
            Section(header(items.count)) {
                ForEach(items) { item in
                    HStack {
                        Text(item.incoming.title).foregroundStyle(Theme.Colors.text)
                        Spacer()
                        Text(item.incoming.category?.name ?? "")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(highlighted ? Theme.Colors.sealedBadgeInk : Theme.Colors.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
    }

    private func accept(_ incoming: ImportService.Incoming) {
        if incoming.conflicts.isEmpty {
            apply(incoming)
        } else {
            // Board 10: one sheet per item, no default answer.
            resolutions = [:]
            conflictIndex = 0
        }
    }

    private func apply(_ incoming: ImportService.Incoming) {
        do {
            try services.importService.accept(incoming, resolutions: resolutions)
            onDone(incoming.items.count)
        } catch {
            failure = Copy.importNotSaved
        }
    }

    private func decline(_ incoming: ImportService.Incoming) {
        try? services.importService.decline(incoming)
        onDone(nil)
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
                Button(Copy.later) { onDone(nil) }.buttonStyle(.vaultSecondary)
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
        Button(Copy.done) { onDone(nil) }.buttonStyle(.vaultPrimary)
    }
}

// MARK: - Board 10

/// One item changed on both phones: dates and length, never a diff of content, all three answers
/// always visible, none chosen for the owner.
private struct ConflictSheet: View {
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
