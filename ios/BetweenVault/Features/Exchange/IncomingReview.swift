import SwiftUI

/// Boards N3 and R2: one review for what the partner sends, nearby or as a file. Same title
/// pattern, same list, Decline and Accept at equal size, the same conflict sheets. Only three
/// things differ by route: the source line, Decide later (files only: nearby, putting it off is
/// really a decline), and what Decline does, which the caller decides.
struct IncomingReview: View {
    enum Source: Equatable {
        case nearby
        case file(receivedAt: Date)
    }

    let incoming: ImportService.Incoming
    let source: Source
    /// Imports with the owner's answers to any conflicts. Throws if nothing could be saved.
    let accept: (_ resolutions: [UUID: ImportService.Resolution]) throws -> Void
    let decline: () -> Void
    /// Files only.
    var decideLater: (() -> Void)?

    @State private var resolutions: [UUID: ImportService.Resolution] = [:]
    @State private var conflictIndex: Int?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "envelope")
                    .foregroundStyle(Theme.Colors.onAccentTint)
                    .frame(width: 48, height: 48)
                    .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typography.title3).foregroundStyle(Theme.Colors.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(sourceLine).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
                }
            }
            ScrollView {
                VStack(spacing: Theme.Space.sm) {
                    ForEach(incoming.items) { item in
                        HStack {
                            Text(item.incoming.title).foregroundStyle(Theme.Colors.text)
                            Spacer()
                            trailing(item)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
            Text(footnote).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
            if let failure { Text(failure).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.destructive) }
            // N3 and R2: Decline and Accept at equal size.
            HStack(spacing: Theme.Space.sm) {
                Button(Copy.decline, action: decline).buttonStyle(.vaultSecondary)
                Button(Copy.acceptItems(incoming.items.count), action: startAccept).buttonStyle(.vaultPrimary)
            }
            if let decideLater {
                Button(Copy.decideLater, action: decideLater)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.Colors.bg)
        .sheet(isPresented: Binding(get: { conflictIndex != nil }, set: { if !$0 { conflictIndex = nil } })) {
            if let index = conflictIndex, index < incoming.conflicts.count {
                ConflictSheet(item: incoming.conflicts[index], index: index + 1, count: incoming.conflicts.count) { choice in
                    resolutions[incoming.conflicts[index].id] = choice
                    if index + 1 < incoming.conflicts.count {
                        conflictIndex = index + 1
                    } else {
                        conflictIndex = nil
                        finishAccept()
                    }
                }
            }
        }
        // Handoff C8: warning when a diverged item is found.
        .sensoryFeedback(.warning, trigger: conflictIndex) { old, new in old == nil && new != nil }
    }

    private var title: String {
        source == .nearby ? Copy.partnerWantsToSend(incoming.items.count) : Copy.partnerSentYou(incoming.items.count)
    }

    private var sourceLine: String {
        switch source {
        case .nearby: Copy.sourceNearby
        case let .file(receivedAt): Copy.sourceFile(receivedAt)
        }
    }

    private var footnote: String {
        let conflicts = incoming.conflicts.map(\.incoming.title)
        return conflicts.isEmpty ? Copy.titlesUntilAccept : Copy.changedOnBothNote(conflicts)
    }

    @ViewBuilder
    private func trailing(_ item: ImportService.Item) -> some View {
        switch item.change {
        case .conflict:
            tag(Copy.changedOnBoth)
        case .update:
            tag(Copy.updatesYours)
        default:
            Text(item.incoming.category?.name ?? "")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.secondary)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.badge)
            .foregroundStyle(Theme.Colors.sealedBadgeInk)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.xs)
            .background(Theme.Colors.sealedBadgeBG, in: Capsule())
    }

    private func startAccept() {
        resolutions = [:]
        // Board 10: one sheet per item, no default answer.
        if incoming.conflicts.isEmpty { finishAccept() } else { conflictIndex = 0 }
    }

    private func finishAccept() {
        do {
            try accept(resolutions)
            failure = nil
        } catch {
            failure = Copy.importNotSaved
        }
    }
}

/// Board R3: after a file is accepted, what happened to each item.
struct ImportResult: View {
    let incoming: ImportService.Incoming
    let resolutions: [UUID: ImportService.Resolution]
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Image(systemName: "checkmark")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.onAccentTint)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(Copy.itemsAdded(incoming.changingCount)).font(Theme.Typography.title2)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.fileRemoved).foregroundStyle(Theme.Colors.secondary)
                VStack(spacing: Theme.Space.sm) {
                    ForEach(incoming.items) { item in
                        LabeledContent(item.incoming.title, value: Self.outcome(item, resolutions[item.id]))
                    }
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Text(Copy.confirmedAfterNearby)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
                Button(Copy.done, action: done).buttonStyle(.vaultPrimary)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.bg)
        }
        .background(Theme.Colors.bg)
    }

    static func outcome(_ item: ImportService.Item, _ resolution: ImportService.Resolution?) -> String {
        switch item.change {
        case .new: Copy.outcomeAdded
        case .update: Copy.outcomeUpdated
        case .unchanged: Copy.outcomeAlreadyHere
        case .conflict:
            switch resolution {
            case .keepBoth: Copy.outcomeKeptBoth
            case .keepPartners: Copy.outcomeReplaced
            default: Copy.outcomeKeptYours
            }
        }
    }
}
