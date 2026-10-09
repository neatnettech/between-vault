import SwiftUI

/// Board 5 and 5a: the note itself, the seal action, and the more menu with move and
/// delete. Deleting is never sent: the partner's copy stays on their phone.
struct NoteDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var categories: [Category] = []
    @State private var editing = false
    @State private var pendingDelete = false
    @State private var actionFailed = false

    init(note: Note) {
        _note = State(initialValue: note)
    }

    private var categoryName: String? {
        categories.first { $0.id == note.categoryID }?.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                metaLine
                Text(NoteFormatting.rendered(note.body))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if note.state != .sealed {
                    sealSection
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Theme.Space.md) {
                    Button(Copy.edit) { editing = true }
                    Menu {
                        Menu(Copy.moveToCategory) {
                            ForEach(categories) { category in
                                Button {
                                    move(to: category)
                                } label: {
                                    if category.id == note.categoryID {
                                        Label(category.name, systemImage: "checkmark")
                                    } else {
                                        Text(category.name)
                                    }
                                }
                            }
                        }
                        Button(role: .destructive) {
                            pendingDelete = true
                        } label: {
                            Label(Copy.deleteNote, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Copy.moreActions)
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            Task { await reload() }
        }) {
            NoteEditorView(note: note)
        }
        .confirmationDialog(
            Copy.deleteNoteTitle(note.title),
            isPresented: $pendingDelete,
            titleVisibility: .visible
        ) {
            Button(Copy.deleteNote, role: .destructive) { deleteNote() }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            // A note that never left this phone has no partner copy to mention.
            Text(note.partnerHasCopy ? Copy.deleteNoteMessage : Copy.deleteNeverSentMessage)
        }
        .alert(Copy.notSaved, isPresented: $actionFailed) {
            Button(Copy.ok, role: .cancel) {}
        } message: {
            Text(Copy.changeNotSaved)
        }
        .task {
            categories = (try? services.categoryRepository.categories()) ?? []
        }
    }

    /// Board 5: the badge and "Home · Edited 3 weeks ago" on one row, stacked when the row does not
    /// fit (accessibility sizes, a long category). The text is one Text, so VoiceOver reads it in
    /// one stop.
    private var metaLine: some View {
        let badge = StateBadge(state: note.state, changedSinceSent: note.hasChangedSinceSent, sentNotConfirmed: note.isSentNotConfirmed)
        let meta = Text(
            [
                categoryName,
                Copy.edited(note.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))),
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        )
        .font(Theme.Typography.footnote)
        .foregroundStyle(Theme.Colors.secondary)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.xs) { badge; meta }
            VStack(alignment: .leading, spacing: Theme.Space.xs) { badge; meta }
        }
    }

    /// Board 5 for a Private note, U2 for a Shared one changed since it was sent, and Send again
    /// for a Shared one the partner says never arrived: sending is optimistic, so this is the way
    /// back (see ExchangeService).
    private var sealSection: some View {
        let (action, helper): (String, String) = switch (note.state, note.hasChangedSinceSent) {
        case (.shared, true): (Copy.sealUpdate, Copy.sealUpdateHelper)
        case (.shared, false): (Copy.sendAgain, Copy.sendAgainHelper)
        default: (Copy.sealForPartner, Copy.sealedNotesWait)
        }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if note.hasChangedSinceSent {
                Text(Copy.changedSinceSentNotice)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.changedFlagInk)
                    .padding(Theme.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.changedFlagBG, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            }
            // Send again is the quieter action: nothing changed, it only repeats a handoff.
            if note.state == .shared, !note.hasChangedSinceSent {
                Button(action: seal) { Text(action).frame(maxWidth: .infinity) }
                    .buttonStyle(.vaultSecondary)
            } else {
                Button(action: seal) { Text(action).frame(maxWidth: .infinity) }
                    .buttonStyle(.vaultPrimary)
            }
            Text(helper)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.tertiary)
        }
    }

    private func seal() {
        var sealed = note
        sealed.state = .sealed
        store(sealed)
    }

    /// Goes through `edited`, like the editor, so a move makes a new version on both paths.
    private func move(to category: Category) {
        guard category.id != note.categoryID else { return }
        store(note.edited(title: note.title, body: note.body, categoryID: category.id))
    }

    /// The screen shows the change only once it is stored.
    private func store(_ changed: Note) {
        do {
            try services.noteRepository.save(changed)
            note = changed
        } catch {
            actionFailed = true
        }
    }

    private func deleteNote() {
        do {
            try services.noteRepository.delete(id: note.id)
            dismiss()
        } catch {
            actionFailed = true
        }
    }

    /// Pops only when the note is gone. A failed read keeps what is on screen: nothing was lost,
    /// the editor already stored the note or said it could not.
    private func reload() async {
        let fresh: Note?
        do {
            fresh = try services.noteRepository.note(id: note.id)
        } catch {
            return
        }
        guard let fresh else {
            dismiss()
            return
        }
        note = fresh
    }
}
