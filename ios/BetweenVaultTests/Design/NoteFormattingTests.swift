import Foundation
import Testing
import UIKit

@testable import BetweenVault

/// The note body: stored marks to the editor's styled text and back, and the list edits of the
/// format row and Return. In the strings below `[` and `]` mark the selection and `|` the caret.
struct NoteFormattingTests {
    private let font = UIFont.systemFont(ofSize: 17)

    @Test func styledTextCarriesTheFormatsWithoutTheMarks() {
        let text = NoteFormatting.styled("**b** *i* ~~s~~", font: font, color: .label)
        #expect(text.string == "b i s")
        #expect(traits(of: text, at: 0).contains(.traitBold))
        #expect(traits(of: text, at: 2).contains(.traitItalic))
        #expect(text.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func styledTextRoundTripsThroughTheMarks() {
        for body in [
            "**bold** *italic* ~~struck~~",
            "***both*** and ~~**struck bold**~~",
            "**a***b* then *c***d**",
            "• **milk**\n1. eggs\nplain",
            "**two**\n**lines**",
        ] {
            #expect(roundTrip(body) == body)
        }
    }

    /// A vault holds passwords: a typed `*` or `_` must never turn into formatting and vanish.
    @Test func typedCharactersShowExactlyAsTyped() {
        let typed = "pa*ss_w~rd \\ `x` [y](z) <b> &amp; 2*3*4"
        let stored = NoteFormatting.stored(NSAttributedString(string: typed, attributes: [.font: font]))
        #expect(String(NoteFormatting.rendered(stored).characters) == typed)
        #expect(roundTrip(stored) == stored)
    }

    @Test func marksHugTheWordsAndCloseOnEachLine() {
        let text = NSMutableAttributedString(string: "say hello world\nnext", attributes: [.font: font])
        let bold = NoteFormatting.font(font, .traitBold)
        text.addAttribute(.font, value: bold, range: NSRange(location: 3, length: 7))
        #expect(NoteFormatting.stored(text) == "say **hello** world\nnext")
        text.addAttribute(.font, value: bold, range: NSRange(location: 10, length: 10))
        #expect(NoteFormatting.stored(text) == "say **hello world**\n**next**")
    }

    @Test func listsToggleOnEveryTouchedLine() {
        #expect(list("[a\nb]") == "[• a\n• b]")
        #expect(list("[• a\n• b]") == "[a\nb]")
        #expect(list("[a\nb\nc]", numbered: true) == "[1. a\n2. b\n3. c]")
        #expect(list("[• a\n• b]", numbered: true) == "[1. a\n2. b]")
        // A selection that ends just after a line break leaves the next line alone.
        #expect(list("[a\n]b") == "[• a]\nb")
    }

    @Test func aCaretKeepsItsPlaceInTheLine() {
        #expect(list("x\nab|c") == "x\n• ab|c")
        #expect(list("|• abc") == "|abc")
        #expect(list("|") == "• |")
        #expect(list("👨‍👩‍👧 é|") == "• 👨‍👩‍👧 é|")
    }

    @Test func returnContinuesOrEndsAList() {
        #expect(pressReturn("• milk|") == "• milk\n• |")
        #expect(pressReturn("9. a|") == "9. a\n10. |")
        #expect(pressReturn("• ab|cd") == "• ab\n• |cd")
        #expect(pressReturn("• a\n• |") == "• a\n|")
        #expect(pressReturn("plain|") == nil)
        #expect(pressReturn("|• a") == nil)
    }

    @Test func savingDropsAnEmptyLastItem() {
        #expect(NoteFormatting.trimmedBody("• milk\n• ") == "• milk")
        #expect(NoteFormatting.trimmedBody("1. a\n2. \n") == "1. a")
        #expect(NoteFormatting.trimmedBody("  plain  ") == "plain")
        #expect(NoteFormatting.trimmedBody("• ") == "")
    }

    @Test func renderingAppliesTheMarksAndDropsLinks() {
        let styled = NoteFormatting.rendered("**b** *i* ~~s~~")
        #expect(String(styled.characters) == "b i s")
        #expect(intent(of: "b", in: styled) == .stronglyEmphasized)
        #expect(intent(of: "i", in: styled) == .emphasized)
        #expect(intent(of: "s", in: styled) == .strikethrough)

        let link = NoteFormatting.rendered("[x](https://example.com)")
        #expect(String(link.characters) == "x")
        #expect(link.runs.allSatisfy { $0.link == nil })

        #expect(String(NoteFormatting.rendered("1. a\n• b").characters) == "1. a\n• b")
        #expect(String(NoteFormatting.rendered("**a").characters) == "**a")
    }

    // MARK: Shorthand

    private func roundTrip(_ body: String) -> String {
        NoteFormatting.stored(NoteFormatting.styled(body, font: font, color: .label))
    }

    private func traits(of text: NSAttributedString, at index: Int) -> UIFontDescriptor.SymbolicTraits {
        (text.attribute(.font, at: index, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits ?? []
    }

    private func intent(of word: String, in text: AttributedString) -> InlinePresentationIntent? {
        text.range(of: word).flatMap { text[$0].inlinePresentationIntent }
    }

    private func list(_ marked: String, numbered: Bool = false) -> String {
        let (text, selection) = parse(marked)
        let change = NoteFormatting.toggleList(in: text, selection: selection, numbered: numbered)
        return show(apply(change.edits, to: text), change.selection)
    }

    private func pressReturn(_ marked: String) -> String? {
        let (text, selection) = parse(marked)
        guard let edit = NoteFormatting.returnEdit(in: text, at: selection) else { return nil }
        let caret = edit.range.location + (edit.replacement as NSString).length
        return show(apply([edit], to: text), NSRange(location: caret, length: 0))
    }

    private func apply(_ edits: [NoteFormatting.Edit], to text: String) -> String {
        let result = NSMutableString(string: text)
        for edit in edits { result.replaceCharacters(in: edit.range, with: edit.replacement) }
        return result as String
    }

    private func parse(_ marked: String) -> (String, NSRange) {
        var text = ""
        var lower = 0
        var upper = 0
        for character in marked {
            switch character {
            case "|": lower = text.utf16.count; upper = lower
            case "[": lower = text.utf16.count
            case "]": upper = text.utf16.count
            default: text.append(character)
            }
        }
        return (text, NSRange(location: lower, length: upper - lower))
    }

    private func show(_ text: String, _ selection: NSRange) -> String {
        let string = text as NSString
        let head = string.substring(to: selection.location)
        let tail = string.substring(from: NSMaxRange(selection))
        guard selection.length > 0 else { return head + "|" + tail }
        return head + "[" + string.substring(with: selection) + "]" + tail
    }
}
