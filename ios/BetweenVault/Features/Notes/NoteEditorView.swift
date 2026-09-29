import SwiftUI

/// Board 6: title, body, category, and state. Attachments stay locked until 1.1.
struct NoteEditorView: View {
    /// The note being edited, nil for a new note.
    var note: Note?
    /// Category preselected for a new note.
    var defaultCategory: Category?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var state: NoteState = .private
    @State private var category: Category?
    @State private var categories: [Category] = []

    init(note: Note? = nil, defaultCategory: Category? = nil) {
        self.note = note
        self.defaultCategory = defaultCategory
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var navigationTitle: String { note == nil ? Copy.newNoteTitle : Copy.editNoteTitle }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.title, text: $title, axis: .vertical)
                        .font(Theme.Typography.body)
                    TextEditor(text: $bodyText)
                        .font(Theme.Typography.body)
                        .frame(minHeight: 140)
                        .accessibilityLabel(Copy.body)
                }
                Section {
                    Menu {
                        ForEach(categories) { candidate in
                            Button(candidate.name) { category = candidate }
                        }
                    } label: {
                        HStack {
                            Text(Copy.category)
                            Spacer()
                            Text(category?.name ?? Copy.none)
                                .foregroundStyle(Theme.Colors.secondary)
                        }
                    }
                    HStack {
                        Label(Copy.addAttachment, systemImage: "paperclip")
                        Spacer()
                        Label(Copy.unlock, systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Theme.Colors.secondary)
                    }
                    .foregroundStyle(Theme.Colors.secondary)
                    .accessibilityHint(Copy.attachmentsArriveLater)
                }
                Section {
                    Picker(Copy.state, selection: $state) {
                        Text(Copy.statePrivate).tag(NoteState.private)
                        Text(Copy.stateSealed).tag(NoteState.sealed)
                        if note?.state == .shared {
                            Text(Copy.stateShared).tag(NoteState.shared)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(Copy.sharedSetBySending)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.tertiary)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.done) { save() }
                        .disabled(!canSave)
                }
            }
            .task {
                categories = (try? services.categoryRepository.categories()) ?? []
                if let note {
                    title = note.title
                    bodyText = note.body
                    state = note.state
                    category = categories.first { $0.id == note.categoryID }
                } else {
                    category = defaultCategory ?? categories.first
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        let saved: Note
        if let note {
            saved = Note(
                id: note.id,
                title: trimmedTitle,
                body: trimmedBody,
                state: state,
                categoryID: category?.id ?? note.categoryID,
                version: note.version + 1,
                baseVersion: note.baseVersion,
                partnerKnownVersion: note.partnerKnownVersion,
                createdAt: note.createdAt,
                updatedAt: .now
            )
        } else {
            saved = Note(
                id: UUID(),
                title: trimmedTitle,
                body: trimmedBody,
                state: state,
                categoryID: category?.id,
                version: 1,
                baseVersion: 0,
                partnerKnownVersion: 0,
                createdAt: .now,
                updatedAt: .now
            )
        }
        try? services.noteRepository.save(saved)
        dismiss()
    }
}
