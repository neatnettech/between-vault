import SwiftUI

struct NotesView: View {
    let category: CategoryRecord
    @Environment(AppServices.self) private var services
    @State private var notes: [Note] = []

    var body: some View {
        List {
            if notes.isEmpty {
                Text("Nothing here yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.body)
                    Text(note.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle(category.name)
        .task {
            notes = (try? services.noteRepository.notes(in: category.id)) ?? []
        }
    }
}
