import SwiftData
import SwiftUI

struct VaultView: View {
    @Query(sort: \CategoryRecord.sort) private var categories: [CategoryRecord]
    @Query private var noteRecords: [NoteRecord]

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    EmptyState(
                        systemImage: "folder",
                        headline: "No categories yet",
                        message: "Add one to start."
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
                ForEach(categories) { category in
                    NavigationLink {
                        NotesView(category: category)
                    } label: {
                        CategoryTile(name: category.name, count: noteCount(in: category))
                    }
                    .listRowBackground(Theme.Colors.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle("Vault")
        }
    }

    private func noteCount(in category: CategoryRecord) -> Int {
        noteRecords.count { $0.categoryID == category.id }
    }
}
