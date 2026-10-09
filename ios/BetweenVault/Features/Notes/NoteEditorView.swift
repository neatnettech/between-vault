import SwiftUI
import UIKit

/// Board 6: title, body, category, and state. No attachment row until attachments exist: App
/// Review rejects a feature shown locked with nothing to unlock it.
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
    @State private var editor = BodyEditorController()
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
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        BodyEditor(text: $bodyText, controller: editor)
                            .overlay(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text(Copy.body)
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Color(uiColor: .placeholderText))
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                        Divider()
                        formatRow
                    }
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
        let trimmedBody = NoteFormatting.trimmedBody(bodyText)
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

    // MARK: Formatting

    /// Under the body, inside its card, like the field's own footer. A tap before the body was
    /// touched starts editing at its end.
    private var formatRow: some View {
        HStack(spacing: Theme.Space.xxs) {
            formatButton(Copy.bold, systemImage: "bold", isOn: editor.isBold, action: editor.toggleBold)
            formatButton(Copy.italic, systemImage: "italic", isOn: editor.isItalic, action: editor.toggleItalic)
            formatButton(Copy.strikethrough, systemImage: "strikethrough", isOn: editor.isStruck, action: editor.toggleStrikethrough)
            formatButton(Copy.bulletedList, systemImage: "list.bullet", isOn: false) { editor.toggleList(numbered: false) }
            formatButton(Copy.numberedList, systemImage: "list.number", isOn: false) { editor.toggleList(numbered: true) }
            Spacer(minLength: 0)
        }
    }

    private func formatButton(_ label: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.body)
                .foregroundStyle(isOn ? Theme.Colors.onAccentTint : Theme.Colors.secondary)
                .frame(width: 44, height: 36)
                .background(isOn ? Theme.Colors.accentTint : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        // Borderless: in a form row a plain button acts for the whole row, so every tap hit all five.
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Body editor

/// The body with its formatting as it will look: bold is bold while it is typed, no marks. A UIKit
/// text view, because before iOS 26 a SwiftUI text field holds plain text only. What is stored stays
/// plain text with marks (`NoteFormatting`).
private struct BodyEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: BodyEditorController

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // Only what the format row offers, so nothing pasted brings a style the marks cannot keep.
        view.allowsEditingTextAttributes = false
        view.tintColor = UIColor(Theme.Colors.accent)
        view.accessibilityLabel = Copy.body
        controller.attach(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        controller.onChange = { text = $0 }
        controller.load(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // Room for six lines before it grows, as the plain field had.
        return CGSize(width: width, height: max(fitting.height, controller.font.lineHeight * 6))
    }
}

/// Runs the body's text view for the format row, and says which formats the row shows as on.
@MainActor @Observable
final class BodyEditorController: NSObject, UITextViewDelegate {
    private(set) var isBold = false
    private(set) var isItalic = false
    private(set) var isStruck = false

    @ObservationIgnored var onChange: (String) -> Void = { _ in }
    @ObservationIgnored private weak var textView: UITextView?
    /// The body last loaded or sent out, so the editor's own edits never come back as a reload.
    @ObservationIgnored private var body = ""
    @ObservationIgnored private var sizeCategory: UIContentSizeCategory?

    var font: UIFont { .preferredFont(forTextStyle: .body) }
    private var color: UIColor { UIColor(Theme.Colors.text) }
    private var plain: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }

    func attach(_ textView: UITextView) {
        self.textView = textView
        textView.delegate = self
        textView.typingAttributes = plain
    }

    /// A body from outside (the note being opened), or the same one again at a new text size.
    func load(_ body: String) {
        guard let textView else { return }
        let category = textView.traitCollection.preferredContentSizeCategory
        guard body != self.body || category != sizeCategory else { return }
        self.body = body
        sizeCategory = category
        let selection = textView.selectedRange
        textView.attributedText = NoteFormatting.styled(body, font: font, color: color)
        textView.typingAttributes = plain
        if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
        refresh()
    }

    // MARK: The format row

    func toggleBold() { toggle(.traitBold) }
    func toggleItalic() { toggle(.traitItalic) }

    func toggleStrikethrough() {
        restyle(isOn: Self.isStruck) { attributes, on in
            attributes[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        }
    }

    func toggleList(numbered: Bool) {
        guard let textView = editing() else { return }
        let change = NoteFormatting.toggleList(in: textView.text, selection: textView.selectedRange, numbered: numbered)
        replace(change.edits, selection: change.selection)
    }

    // MARK: UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) { publish() }

    func textViewDidChangeSelection(_ textView: UITextView) { refresh() }

    /// Return on a list line continues the list, or ends it on an empty item.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n", let edit = NoteFormatting.returnEdit(in: textView.text, at: range) else { return true }
        replace([edit], selection: NSRange(location: edit.range.location + (edit.replacement as NSString).length, length: 0))
        return false
    }

    // MARK: Pieces

    private func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
        let font = self.font
        restyle(isOn: { Self.traits($0).contains(trait) }) { attributes, on in
            var traits = Self.traits(attributes)
            if on { traits.insert(trait) } else { traits.remove(trait) }
            attributes[.font] = NoteFormatting.font(font, traits)
        }
    }

    /// Turns a format on for the selection, or off when all of it has it already. At a caret it
    /// is for what is typed next.
    private func restyle(
        isOn: ([NSAttributedString.Key: Any]) -> Bool,
        change: (inout [NSAttributedString.Key: Any], Bool) -> Void
    ) {
        guard let textView = editing() else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var typing = textView.typingAttributes
            change(&typing, !isOn(typing))
            textView.typingAttributes = typing
        } else {
            let on = !all(of: range, isOn)
            let storage = textView.textStorage
            storage.beginEditing()
            storage.enumerateAttributes(in: range) { attributes, run, _ in
                var attributes = attributes
                change(&attributes, on)
                storage.setAttributes(attributes, range: run)
            }
            storage.endEditing()
            textView.selectedRange = range
            // Edits made on the storage directly would leave UIKit's undo steps pointing at the wrong text.
            textView.undoManager?.removeAllActions()
            publish()
        }
        refresh()
    }

    private func replace(_ edits: [NoteFormatting.Edit], selection: NSRange) {
        guard let textView else { return }
        let typing = textView.typingAttributes
        let storage = textView.textStorage
        storage.beginEditing()
        for edit in edits {
            storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: plain))
        }
        storage.endEditing()
        textView.selectedRange = selection
        textView.typingAttributes = typing
        textView.undoManager?.removeAllActions()
        publish()
    }

    /// The text view, editing. Not yet touched, it starts at the end of the note.
    private func editing() -> UITextView? {
        guard let textView else { return nil }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
        }
        return textView
    }

    private func publish() {
        guard let textView else { return }
        body = NoteFormatting.stored(textView.attributedText)
        onChange(body)
        refresh()
    }

    private func refresh() {
        guard let textView else { return }
        let range = textView.selectedRange
        let has: (([NSAttributedString.Key: Any]) -> Bool) -> Bool = { test in
            range.length == 0 ? test(textView.typingAttributes) : self.all(of: range, test)
        }
        let bold = has { Self.traits($0).contains(.traitBold) }
        let italic = has { Self.traits($0).contains(.traitItalic) }
        let struck = has(Self.isStruck)
        if bold != isBold { isBold = bold }
        if italic != isItalic { isItalic = italic }
        if struck != isStruck { isStruck = struck }
    }

    private func all(of range: NSRange, _ test: ([NSAttributedString.Key: Any]) -> Bool) -> Bool {
        var result = true
        textView?.textStorage.enumerateAttributes(in: range) { attributes, _, stop in
            if !test(attributes) {
                result = false
                stop.pointee = true
            }
        }
        return result
    }

    private static func traits(_ attributes: [NSAttributedString.Key: Any]) -> UIFontDescriptor.SymbolicTraits {
        ((attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []).intersection([.traitBold, .traitItalic])
    }

    private static func isStruck(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.strikethroughStyle] as? Int ?? 0) != 0
    }
}
