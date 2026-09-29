import SwiftUI

struct NotesView: View {
    let category: Category
    var filter: NoteState?
    @Environment(AppServices.self) private var services
    @State private var all: [Note] = []
    @State private var composing = false

    private var visible: [Note] {
        guard let filter else { return all }
        return all.filter { $0.state == filter }
    }

    var body: some View {
        List {
            if visible.isEmpty {
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

    @Sendable private func reload() async {
        all = (try? services.noteRepository.notes(in: category.id)) ?? []
    }

    /// A category hidden by the filter is not an empty category. Saying "Nothing here yet" over a
    /// full category, with nothing on screen admitting a filter is on, is the kind of quiet
    /// dishonesty the product promises not to ship.
    @ViewBuilder
    private var emptyState: some View {
        if let filter, !all.isEmpty {
            let word = StateBadge.spec(for: filter, changedSinceSent: false).word
            EmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                headline: Copy.noFilteredNotes(state: word, category: category.name),
                message: Copy.filteredEmptyMessage(count: all.count)
            )
        } else {
            EmptyState(
                systemImage: "note.text",
                headline: Copy.nothingHereYet,
                message: Copy.addANoteToThisCategory
            )
        }
    }
}
