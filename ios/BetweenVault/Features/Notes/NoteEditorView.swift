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

    private var navigationTitle: String { note == nil ? "New note" : "Edit note" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(Theme.Typography.body)
                    TextEditor(text: $bodyText)
                        .font(Theme.Typography.body)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Body")
                }
                Section {
                    Menu {
                        ForEach(categories) { candidate in
                            Button(candidate.name) { category = candidate }
                        }
                    } label: {
                        HStack {
                            Text("Category")
                            Spacer()
                            Text(category?.name ?? "None")
                                .foregroundStyle(Theme.Colors.secondary)
                        }
                    }
                    HStack {
                        Label("Add attachment", systemImage: "paperclip")
                        Spacer()
                        Label("Unlock", systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Theme.Colors.secondary)
                    }
                    .foregroundStyle(Theme.Colors.secondary)
                    .accessibilityHint("Attachments arrive in a later update.")
                }
                Section {
                    Picker("State", selection: $state) {
                        Text("Private").tag(NoteState.private)
                        Text("Sealed").tag(NoteState.sealed)
                        if note?.state == .shared {
                            Text("Shared").tag(NoteState.shared)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Shared is set automatically after you send it. Nothing is shared by editing.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.tertiary)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
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
