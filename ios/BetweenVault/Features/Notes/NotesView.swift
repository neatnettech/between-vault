import SwiftUI

struct NotesView: View {
    let category: Category
    var filter: NoteState?
    @Environment(AppServices.self) private var services
    @State private var all: [Note] = []

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
                NoteRow(note: note)
                    .listRowBackground(Theme.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(category.name)
        .task { all = (try? services.noteRepository.notes(in: category.id)) ?? [] }
    }

    /// A category hidden by the filter is not an empty category. Saying "Nothing here yet" over a
    /// full category, with nothing on screen admitting a filter is on, is the kind of quiet
    /// dishonesty the product promises not to ship.
    @ViewBuilder
    private var emptyState: some View {
        if let filter, !all.isEmpty {
            let word = StateBadge.spec(for: filter, changedSinceSent: false).word.lowercased()
            EmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                headline: "No \(word) notes in \(category.name)",
                message: "This category has \(all.count == 1 ? "1 note" : "\(all.count) notes"). Clear the filter on the vault home to see them."
            )
        } else {
            EmptyState(
                systemImage: "note.text",
                headline: "Nothing here yet",
                message: "Add a note to this category."
            )
        }
    }
}
