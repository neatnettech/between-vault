import SwiftUI

/// Board 6: title, body, category, and state. Attachments stay locked until 1.1.
struct NoteEditorView: View {
    /// The note being edited, nil for a new note.
    var note: Note?
    /// Category preselected for a new note.
    var defaultCategory: Category?

    @Environment(AppServices.self) private var services
    @Environment(LockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var state: NoteState = .private
    @State private var category: Category?
    @State private var categories: [Category] = []
    @State private var saveFailed = false

    init(note: Note? = nil, defaultCategory: Category? = nil) {
        self.note = note
        self.defaultCategory = defaultCategory
    }

    /// A title is required: the list row, the detail title, the delete dialog and the exchange
    /// review all name a note by it.
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var navigationTitle: String { note == nil ? Copy.newNoteTitle : Copy.editNoteTitle }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.title, text: $title, axis: .vertical)
                        .font(Theme.Typography.body)
                    TextField(Copy.body, text: $bodyText, axis: .vertical)
                        .font(Theme.Typography.body)
                        .lineLimit(6...)
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
                // Once the partner holds a copy, Private would be false and resealing is the detail
                // screen's Seal update (U2), so editing keeps the state as it is (U1).
                if !(note?.partnerHasCopy ?? false) {
                    Section {
                        Picker(Copy.state, selection: $state) {
                            Text(Copy.statePrivate).tag(NoteState.private)
                            Text(Copy.stateSealed).tag(NoteState.sealed)
                        }
                        .pickerStyle(.segmented)
                        Text(Copy.sharedSetBySending)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.tertiary)
                    }
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
            .alert(Copy.notSaved, isPresented: $saveFailed) {
                Button(Copy.ok, role: .cancel) {}
            } message: {
                Text(Copy.noteNotSaved)
            }
        }
        // A swipe down would drop a draft without a word; Cancel stays the explicit way out.
        .interactiveDismissDisabled(title != (note?.title ?? "") || bodyText != (note?.body ?? ""))
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        var saved: Note
        if let note {
            saved = note.edited(
                title: trimmedTitle,
                body: trimmedBody,
                categoryID: category?.id ?? note.categoryID
            )
            saved.state = state
            guard saved != note else {
                dismiss()
                return
            }
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
        // Dismiss only once the note is stored: a failed save keeps the sheet and the typed text.
        do {
            try services.noteRepository.save(saved)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
