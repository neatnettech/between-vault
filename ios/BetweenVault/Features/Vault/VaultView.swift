import SwiftData
import SwiftUI

struct VaultView: View {
    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Query(sort: \CategoryRecord.sort) private var categories: [CategoryRecord]
    @State private var filter: NoteState?
    @State private var counts: [UUID: Int] = [:]

    private var totalNotes: Int { counts.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if totalNotes == 0 {
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
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        lockManager.lock()
                    } label: {
                        Image(systemName: "lock")
                    }
                    .accessibilityLabel("Lock now")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Edit") {
                        // Category management lands with issue 1.7.
                    }
                    Button {
                        // New note lands with issue 1.8.
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New note")
                }
            }
            .task { await refreshCounts() }
        }
    }

    private func refreshCounts() async {
        counts = (try? services.noteRepository.countsByCategory(state: filter)) ?? [:]
    }

    private var firstRunPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Start with Emergency")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.text)
            Text("If something happened to you today, what would your partner need? Doctor, insurance, who to call, where the papers are.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
            if let emergency = categories.first(where: { $0.builtInKey == "emergency" }) {
                NavigationLink {
                    NotesView(category: emergency, filter: filter)
                } label: {
                    Text("Write the first note")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.vaultPrimary)
                .padding(.top, Theme.Space.xs)
            }
            Text("Six starter categories are created with the vault. Emergency and Other always exist, so the vault is never without a category.")
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
                Button {
                    filter = nil
                    Task { await refreshCounts() }
                } label: {
                    FilterChip(title: "All", systemImage: "square.stack.3d.up", isSelected: filter == nil)
                }
                .buttonStyle(.plain)
                ForEach(NoteState.allCases, id: \.self) { state in
                    Button {
                        filter = filter == state ? nil : state
                        Task { await refreshCounts() }
                    } label: {
                        FilterChip(
                            title: state.displayName,
                            systemImage: state.symbolName,
                            isSelected: filter == state
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryGrid: some View {
        let regular = categories.filter { $0.builtInKey != "emergency" }
        return VStack(spacing: Theme.Space.sm) {
            if let emergency = categories.first(where: { $0.builtInKey == "emergency" }) {
                NavigationLink {
                    NotesView(category: emergency, filter: filter)
                } label: {
                    CategoryTile(
                        name: emergency.name,
                        count: counts[emergency.id] ?? 0,
                        subtitle: "What your partner needs if something happens",
                        builtInKey: "emergency"
                    )
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.sm), GridItem(.flexible())], spacing: Theme.Space.sm) {
                ForEach(regular) { category in
                    NavigationLink {
                        NotesView(category: category, filter: filter)
                    } label: {
                        CategoryTile(
                            name: category.name,
                            count: counts[category.id] ?? 0,
                            builtInKey: category.builtInKey
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    // New category lands with issue 1.7.
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "plus")
                        Text("New category")
                            .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 14))
            Text("Stored locally on this iPhone. Not in any cloud.")
                .font(Theme.Typography.footnote)
        }
        .foregroundStyle(Theme.Colors.secondary)
        .padding(.top, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

private extension NoteState {
    var displayName: String {
        switch self {
        case .private: "Private"
        case .sealed: "Sealed"
        case .shared: "Shared"
        }
    }

    var symbolName: String {
        switch self {
        case .private: "lock"
        case .sealed: "envelope"
        case .shared: "person.2"
        }
    }
}
