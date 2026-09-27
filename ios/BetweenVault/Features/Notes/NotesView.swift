import SwiftUI

struct NotesView: View {
    let category: CategoryRecord
    @Environment(AppServices.self) private var services
    @State private var notes: [Note] = []

    var body: some View {
        List {
            if notes.isEmpty {
                EmptyState(
                    systemImage: "note.text",
                    headline: "Nothing here yet",
                    message: "Add a note to this category."
                )
                .listRowBackground(Theme.Colors.bg)
            }
            ForEach(notes) { note in
                NoteRow(note: note)
                    .listRowBackground(Theme.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(category.name)
        .task {
            notes = (try? services.noteRepository.notes(in: category.id)) ?? []
        }
    }
}
