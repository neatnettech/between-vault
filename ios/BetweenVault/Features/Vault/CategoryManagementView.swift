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
    /// The repository's refusal or failure, worded for the user. Row 1.7 surfaces these.
    @State private var failure: String?

    /// Deleted notes move to Other by key, so the dialog names Other as it is called now.
    private var otherName: String {
        categories.first { $0.builtInKey == .other }?.name ?? BuiltInCategory.other.seedName
    }

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
                        .accessibilityHint(Copy.renameCategory)
                        .deleteDisabled(category.isBuiltIn)
                    }
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                        attempt { try services.categoryRepository.reorder(categories.map(\.id)) }
                    }
                    .onDelete { offsets in
                        deleting = offsets.first.map { categories[$0] }
                    }
                } footer: {
                    Text(Copy.categoriesFooter)
                }
            }
            // Board 3b is always editing: delete controls on user categories, move handles on all.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(Copy.categoriesTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.add) {
                        draftName = ""
                        adding = true
                    }
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
                ),
                presenting: renaming
            ) { category in
                TextField(Copy.name, text: $draftName)
                Button(Copy.cancel, role: .cancel) {}
                Button(Copy.save) { rename(category) }
            }
            .alert(Copy.newCategoryPrompt, isPresented: $adding) {
                TextField(Copy.name, text: $draftName)
                Button(Copy.cancel, role: .cancel) {}
                Button(Copy.add) { addCategory() }
            }
            .confirmationDialog(
                deleting.map { Copy.deleteCategoryTitle($0.name) } ?? Copy.deleteCategoryFallback,
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleting
            ) { category in
                Button(Copy.delete, role: .destructive) {
                    attempt { try services.categoryRepository.delete(id: category.id) }
                }
                Button(Copy.cancel, role: .cancel) {}
            } message: { category in
                Text(Copy.deleteCategoryMessage(counts[category.id] ?? 0, movingTo: otherName))
            }
            .alert(
                Copy.notSaved,
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { failure = nil } }
                ),
                presenting: failure
            ) { _ in
                Button(Copy.ok, role: .cancel) {}
            } message: { message in
                Text(message)
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
        // Spoken the way the vault tile speaks it ("Home, 12 notes"), not glyph plus bare number.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            CategoryTile.accessibilityText(
                name: category.name,
                count: counts[category.id] ?? 0,
                subtitle: category.isBuiltIn ? Copy.builtIn : nil
            )
        )
    }

    private func load() async {
        categories = (try? services.categoryRepository.categories()) ?? []
        counts = (try? services.noteRepository.countsByCategory()) ?? [:]
    }

    /// Runs one repository change and reloads, so a refusal or a failed save is shown instead of
    /// the list quietly staying as it was.
    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            failure = Copy.categoryFailure(error)
        }
        Task { await load() }
    }

    private func beginRename(_ category: Category) {
        draftName = category.name
        renaming = category
    }

    private func rename(_ category: Category) {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        attempt { try services.categoryRepository.rename(id: category.id, name: name) }
    }

    private func addCategory() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        attempt { _ = try services.categoryRepository.add(name: name) }
    }
}
