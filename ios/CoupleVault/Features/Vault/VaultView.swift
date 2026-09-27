import SwiftData
import SwiftUI

struct VaultView: View {
    @Query(sort: \CategoryRecord.sort) private var categories: [CategoryRecord]

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    Text("No categories yet. Add one to start.")
                        .foregroundStyle(.secondary)
                }
                ForEach(categories) { category in
                    NavigationLink(category.name) {
                        NotesView(category: category)
                    }
                }
            }
            .navigationTitle("Vault")
        }
    }
}
