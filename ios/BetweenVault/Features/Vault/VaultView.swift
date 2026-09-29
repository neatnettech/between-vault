import SwiftUI

struct VaultView: View {
    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter: NoteState?
    @State private var snapshot = Snapshot()
    @State private var managingCategories = false
    @State private var composingNote = false

    /// Categories, per category counts and the unfiltered total, read in one pass so the two halves
    /// of the screen can never disagree about the same vault.
    ///
    /// ponytail: refreshed by hand from `.task` and the filter chips. Once 1.7 and 1.8 add mutation
    /// sites, move this behind an observed model rather than adding a `load()` call per site.
    private struct Snapshot {
        var categories: [Category] = []
        var counts: [UUID: Int] = [:]
        /// Every note in the vault, ignoring the filter. A filter that matches nothing is not an
        /// empty vault, and the first run prompt must tell those two apart.
        var totalNotes = 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if snapshot.totalNotes == 0 {
                        firstRunPrompt
                    }
                    filterChips
                    categoryGrid
                    localOnlyFooter
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabVault)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        lockManager.lock()
                    } label: {
                        Image(systemName: "lock")
                    }
                    .accessibilityLabel(Copy.lockNow)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(Copy.edit) { managingCategories = true }
                    Button {
                        composingNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Copy.newNote)
                }
            }
            .sheet(isPresented: $managingCategories, onDismiss: {
                Task { await load() }
            }) {
                CategoryManagementView()
            }
            .sheet(isPresented: $composingNote, onDismiss: {
                Task { await load() }
            }) {
                NoteEditorView(defaultCategory: snapshot.categories.first(where: { $0.builtInKey == .emergency }))
            }
            .task { await load() }
        }
    }

    private func load() async {
        let categories = (try? services.categoryRepository.categories()) ?? []
        let counts = (try? services.noteRepository.countsByCategory(state: filter)) ?? [:]
        let total = (try? services.noteRepository.noteCount()) ?? 0
        snapshot = Snapshot(categories: categories, counts: counts, totalNotes: total)
    }

    private var firstRunPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(Copy.startWithEmergency)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.emergencyPrompt)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
            if let emergency = snapshot.categories.first(where: { $0.builtInKey == .emergency }) {
                NavigationLink {
                    NotesView(category: emergency, filter: filter)
                } label: {
                    Text(Copy.writeTheFirstNote)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.vaultPrimary)
                .padding(.top, Theme.Space.xs)
            }
            Text(Copy.starterCategoriesNote)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.tertiary)
                .padding(.top, Theme.Space.xxs)
        }
        .padding(Theme.Space.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                FilterChip(title: Copy.filterAll, systemImage: "square.stack.3d.up", isSelected: filter == nil) {
                    filter = nil
                    Task { await load() }
                }
                ForEach(NoteState.allCases, id: \.self) { state in
                    let spec = StateBadge.spec(for: state, changedSinceSent: false)
                    FilterChip(
                        title: spec.word,
                        systemImage: spec.outlineSymbol,
                        isSelected: filter == state
                    ) {
                        filter = filter == state ? nil : state
                        Task { await load() }
                    }
                }
            }
        }
    }

    /// Two up normally. At accessibility sizes a half width tile is narrower than a single word like
    /// "Documents", which would truncate, so the grid collapses to one column instead.
    private var tileColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Space.sm), GridItem(.flexible())]
    }

    private var categoryGrid: some View {
        let regular = snapshot.categories.filter { $0.builtInKey != .emergency }
        return VStack(spacing: Theme.Space.sm) {
            if let emergency = snapshot.categories.first(where: { $0.builtInKey == .emergency }) {
                NavigationLink {
                    NotesView(category: emergency, filter: filter)
                } label: {
                    CategoryTile(
                        name: emergency.name,
                        count: snapshot.counts[emergency.id] ?? 0,
                        symbol: emergency.symbol,
                        subtitle: Copy.emergencyTileSubtitle
                    )
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: tileColumns, spacing: Theme.Space.sm) {
                ForEach(regular) { category in
                    NavigationLink {
                        NotesView(category: category, filter: filter)
                    } label: {
                        CategoryTile(
                            name: category.name,
                            count: snapshot.counts[category.id] ?? 0,
                            symbol: category.symbol
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    managingCategories = true
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "plus")
                        Text(Copy.newCategory)
                            .font(Theme.Typography.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.panel)
                            .stroke(Theme.Colors.borderStrong)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var localOnlyFooter: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "cloud.slash")
                .imageScale(.small)
            Text(Copy.localOnlyFooter)
                .font(Theme.Typography.footnote)
        }
        .font(Theme.Typography.footnote)
        .foregroundStyle(Theme.Colors.secondary)
        .padding(.top, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

