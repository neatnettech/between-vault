import SwiftUI

/// Board X4: seal straight from Exchange. Private notes and Shared notes changed since they were
/// sent can be sealed; a Shared note with nothing new shows "Already shared"; sealed notes are
/// already in To send, so they are not listed. Sealing sends nothing.
struct AddNotesSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [(category: String, notes: [Note])] = []
    @State private var ticked = Set<UUID>()
    @State private var search = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.notes) { note in row(note) }
                    }
                }
                if failed {
                    Text(Copy.changeNotSaved).foregroundStyle(Theme.Colors.destructive)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .searchable(text: $search, prompt: Copy.searchNotes)
            .navigationTitle(Copy.addNotesToSend)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Space.sm) {
                    Button(Copy.sealNotes(ticked.count), action: seal)
                        .buttonStyle(.vaultPrimary)
                        .disabled(ticked.isEmpty)
                    Text(Copy.sealingSendsNothing)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.bg)
            }
            .task { load() }
        }
    }

    private var filtered: [(category: String, notes: [Note])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let notes = group.notes.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return notes.isEmpty ? nil : (group.category, notes)
        }
    }

    @ViewBuilder
    private func row(_ note: Note) -> some View {
        if note.state == .shared && !note.hasChangedSinceSent {
            HStack {
                Text(note.title).foregroundStyle(Theme.Colors.tertiary)
                Spacer()
                Text(Copy.alreadyShared).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.tertiary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button {
                if ticked.contains(note.id) { ticked.remove(note.id) } else { ticked.insert(note.id) }
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: ticked.contains(note.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ticked.contains(note.id) ? Theme.Colors.accent : Theme.Colors.tertiary)
                    Text(note.title).foregroundStyle(Theme.Colors.text)
                    Spacer()
                    if note.hasChangedSinceSent { StateBadge(state: .shared, changedSinceSent: true) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(ticked.contains(note.id) ? .isSelected : [])
        }
    }

    private func load() {
        let categories = (try? services.categoryRepository.categories()) ?? []
        let notes = ((try? services.noteRepository.notes(in: nil)) ?? []).filter { $0.state != .sealed }
        let known = Set(categories.map(\.id))
        groups = categories.compactMap { category in
            let inCategory = notes.filter { $0.categoryID == category.id }.sorted { $0.title < $1.title }
            return inCategory.isEmpty ? nil : (category.name, inCategory)
        }
        // A note without a known category is listed too, never silently missing.
        let loose = notes.filter { $0.categoryID.map { !known.contains($0) } ?? true }
        if !loose.isEmpty { groups.append((Copy.none, loose.sorted { $0.title < $1.title })) }
    }

    /// Seal update for a changed Shared note, Seal for partner for a Private one: either way the
    /// note goes Sealed and waits in To send.
    private func seal() {
        do {
            for id in ticked {
                guard var note = try services.noteRepository.note(id: id) else { continue }
                note.state = .sealed
                try services.noteRepository.save(note, commit: false)
            }
            try services.noteRepository.commit()
            dismiss()
        } catch {
            failed = true
        }
    }
}
