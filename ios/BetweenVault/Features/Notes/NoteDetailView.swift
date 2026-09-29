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
                Text(note.body)
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
                        ForEach(categories) { category in
                            Button(category.name) { move(to: category) }
                        }
                        Divider()
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
            Text(Copy.deleteNoteMessage)
        }
        .task {
            categories = (try? services.categoryRepository.categories()) ?? []
        }
    }

    private var metaLine: some View {
        HStack(spacing: Theme.Space.xs) {
            StateBadge(state: note.state, changedSinceSent: note.hasChangedSinceSent)
            if let categoryName {
                Text(categoryName)
                Text("·")
            }
            Text(Copy.edited(NoteRow.timestampString(for: note.updatedAt)))
        }
        .font(Theme.Typography.footnote)
        .foregroundStyle(Theme.Colors.secondary)
    }

    private var sealSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button {
                seal()
            } label: {
                Text(Copy.sealForPartner)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.vaultPrimary)
            Text(Copy.sealedNotesWait)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.tertiary)
        }
    }

    private func seal() {
        note.state = .sealed
        try? services.noteRepository.save(note)
        Task { await reload() }
    }

    private func move(to category: Category) {
        guard category.id != note.categoryID else { return }
        note.categoryID = category.id
        try? services.noteRepository.save(note)
        Task { await reload() }
    }

    private func deleteNote() {
        try? services.noteRepository.delete(id: note.id)
        dismiss()
    }

    private func reload() async {
        guard let fresh = try? services.noteRepository.note(id: note.id) else {
            dismiss()
            return
        }
        note = fresh
    }
}
