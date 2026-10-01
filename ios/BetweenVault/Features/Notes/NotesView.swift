import SwiftUI

struct NotesView: View {
    let category: Category
    var filter: NoteState?
    @Environment(AppServices.self) private var services
    @State private var all: [Note] = []
    @State private var loadFailed = false
    @State private var awaitingRestore = false
    @State private var composing = false

    private var visible: [Note] {
        guard let filter else { return all }
        return all.filter { $0.state == filter }
    }

    var body: some View {
        List {
            if loadFailed {
                EmptyState(
                    systemImage: awaitingRestore ? "lock" : "exclamationmark.triangle",
                    headline: awaitingRestore ? Copy.awaitingRestore : Copy.notesCouldNotOpen,
                    message: awaitingRestore ? Copy.awaitingRestoreMessage : Copy.nothingWasDeleted
                )
                .listRowBackground(Theme.Colors.bg)
            } else if visible.isEmpty {
                emptyState
                    .listRowBackground(Theme.Colors.bg)
            }
            ForEach(visible) { note in
                NavigationLink {
                    NoteDetailView(note: note)
                } label: {
                    NoteRow(note: note)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.Colors.surface)
            }
            // A filter hiding some notes is said out loud too, not only one hiding all of them.
            if let filter, !visible.isEmpty, visible.count < all.count {
                Text(Copy.hiddenByFilter(all.count - visible.count, state: StateBadge.spec(for: filter, changedSinceSent: false).word))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .listRowBackground(Theme.Colors.bg)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    composing = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Copy.newNoteIn(category.name))
            }
        }
        .sheet(isPresented: $composing, onDismiss: {
            Task { await reload() }
        }) {
            NoteEditorView(defaultCategory: category)
        }
        .task { await reload() }
    }

    /// A failed read is shown as a failure, never as an empty category.
    @Sendable private func reload() async {
        do {
            all = try services.noteRepository.notes(in: category.id)
            loadFailed = false
        } catch {
            all = []
            loadFailed = true
            awaitingRestore = error as? VaultKeyError == .awaitingRestore
        }
    }

    /// A category hidden by the filter is not an empty category. Saying "Nothing here yet" over a
    /// full category, with nothing on screen admitting a filter is on, is the kind of quiet
    /// dishonesty the product promises not to ship.
    static func emptyCopy(filter: NoteState?, total: Int, category: String) -> (headline: String, message: String) {
        guard let filter, total > 0 else {
            return (Copy.nothingHereYet, Copy.addANoteToThisCategory)
        }
        let word = StateBadge.spec(for: filter, changedSinceSent: false).word
        return (Copy.noFilteredNotes(state: word, category: category), Copy.filteredEmptyMessage(count: total))
    }

    private var emptyState: some View {
        let copy = Self.emptyCopy(filter: filter, total: all.count, category: category.name)
        return EmptyState(
            systemImage: filter != nil && !all.isEmpty ? "line.3.horizontal.decrease.circle" : "note.text",
            headline: copy.headline,
            message: copy.message
        )
    }
}
