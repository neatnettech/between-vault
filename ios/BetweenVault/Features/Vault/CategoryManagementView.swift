import SwiftUI

/// Board 3b and 3c: add, rename, reorder, and delete categories.
/// Emergency and Other can be renamed and moved, never deleted. Deleting a user
/// category moves its notes to Other, no notes are deleted.
struct CategoryManagementView: View {
    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [Category] = []
    @State private var counts: [UUID: Int] = [:]
    @State private var draftName = ""
    @State private var renaming: Category?
    @State private var adding = false
    @State private var deleting: Category?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            beginRename(category)
                        } label: {
                            row(for: category)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !category.isBuiltIn {
                                Button(role: .destructive) {
                                    deleting = category
                                } label: {
                                    Label(Copy.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                        persistOrder()
                    }
                } footer: {
                    Text(Copy.categoryChangesStayLocal)
                }
            }
            .navigationTitle(Copy.categoriesTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.add) { adding = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.done) { dismiss() }
                }
            }
            .task { await load() }
            .alert(
                Copy.renameCategory,
                isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                )
            ) {
                TextField(Copy.name, text: $draftName)
                Button(Copy.cancel, role: .cancel) {}
                Button(Copy.save) { saveRename() }
            }
            .alert(Copy.newCategoryPrompt, isPresented: $adding) {
                TextField(Copy.name, text: $draftName)
                Button(Copy.cancel, role: .cancel) { draftName = "" }
                Button(Copy.add) { addCategory() }
            }
            .confirmationDialog(
                deleting.map { Copy.deleteCategoryTitle($0.name) } ?? Copy.newCategoryPrompt,
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(Copy.delete, role: .destructive) { deleteSelected() }
                Button(Copy.cancel, role: .cancel) {}
            } message: {
                if let deleting {
                    Text(Copy.deleteCategoryMessage(counts[deleting.id] ?? 0))
                }
            }
        }
        .privacyCover(lockManager)
    }

    private func row(for category: Category) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: category.symbol)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: Theme.Space.lg)
            Text(category.name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            if category.isBuiltIn {
                Text(Copy.builtIn)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            } else {
                Text("\(counts[category.id] ?? 0)")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        categories = (try? services.categoryRepository.categories()) ?? []
        counts = (try? services.noteRepository.countsByCategory()) ?? [:]
    }

    private func beginRename(_ category: Category) {
        draftName = category.name
        renaming = category
    }

    private func saveRename() {
        guard let renaming, !draftName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? services.categoryRepository.rename(id: renaming.id, name: draftName.trimmingCharacters(in: .whitespaces))
        draftName = ""
        Task { await load() }
    }

    private func addCategory() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? services.categoryRepository.add(name: name)
        draftName = ""
        Task { await load() }
    }

    private func deleteSelected() {
        guard let deleting else { return }
        try? services.categoryRepository.delete(id: deleting.id)
        Task { await load() }
    }

    private func persistOrder() {
        try? services.categoryRepository.reorder(categories.map(\.id))
    }
}
