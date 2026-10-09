import Foundation
import UIKit

/// Note bodies are stored as plain text with a few inline marks (`**bold**`, `*italic*`,
/// `~~struck~~`) and list prefixes kept as typed (`• `, `1. `), so the store and the exchange format
/// never change. The editor shows them as real formatting: these turn the stored body into styled
/// text and back, and work out the list edits the format bar and Return make.
enum NoteFormatting {
    static let bullet = "• "

    /// One replacement in the editor's text, in UTF-16 units as UIKit counts them.
    typealias Edit = (range: NSRange, replacement: String)

    // MARK: Stored body and styled text

    /// The editor's styled text for a stored body.
    static func styled(_ body: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let parsed = parse(body)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            var attributes: [NSAttributedString.Key: Any] = [.font: Self.font(font, traits), .foregroundColor: color]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    /// The stored body for the editor's styled text. Marks hug the words (spaces stay outside, each
    /// line closes its own), and every character a mark or a link could start with is escaped, so a
    /// password like `a*b*c` is stored and shown exactly as typed.
    static func stored(_ text: NSAttributedString) -> String {
        // Grouped by what the marks can say, so a difference they cannot (a font size) never splits one.
        var pieces: [(marks: String, text: String)] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            let struck = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            let marks = (struck ? "~~" : "") + (traits.contains(.traitBold) ? "**" : "") + (traits.contains(.traitItalic) ? "*" : "")
            let piece = (text.string as NSString).substring(with: range)
            if pieces.last?.marks == marks {
                pieces[pieces.count - 1].text += piece
            } else {
                pieces.append((marks, piece))
            }
        }
        return pieces.map { marks, piece in
            piece.components(separatedBy: "\n").map { wrap(escaped($0), in: marks) }.joined(separator: "\n")
        }
        .joined()
    }

    /// What the detail screen and the list row show: the marks applied, lists as typed. Links are
    /// dropped, a note never opens anything. Text the parser refuses shows as written.
    static func rendered(_ body: String) -> AttributedString {
        var text = parse(body)
        text.link = nil
        return text
    }

    /// The same face and size with exactly these of bold and italic.
    static func font(_ base: UIFont, _ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    // MARK: Lists

    /// Adds `• ` or `1. 2. 3.` to every line the selection touches, or takes it off when they all
    /// have it; bullets over numbers swap. The edits come last line first, so each range is still
    /// right when it is applied. A caret keeps its place in the line's text; a selection becomes the
    /// whole changed block.
    static func toggleList(in text: String, selection: NSRange, numbered: Bool) -> (edits: [Edit], selection: NSRange) {
        let string = text as NSString
        // A selection ending just after a line break does not reach into the next line.
        var end = NSMaxRange(selection)
        if selection.length > 0, string.character(at: end - 1) == 0x0A { end -= 1 }
        let block = string.lineRange(for: NSRange(location: selection.location, length: end - selection.location))
        var lines: [NSRange] = []
        string.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, line, _, _ in lines.append(line) }
        if lines.isEmpty { lines = [NSRange(location: block.location, length: 0)] }

        let prefixes = lines.map { listPrefixLength(string.substring(with: $0)) }
        let removing = zip(lines, prefixes).allSatisfy { line, length in
            guard let length else { return false }
            return (string.substring(with: NSRange(location: line.location, length: length)) == bullet) != numbered
        }
        let edits: [Edit] = zip(lines, prefixes).enumerated().map { number, entry in
            (NSRange(location: entry.0.location, length: entry.1 ?? 0), removing ? "" : numbered ? "\(number + 1). " : bullet)
        }
        let delta = edits.reduce(0) { $0 + ($1.replacement as NSString).length - $1.range.length }

        let first = lines[0], last = lines[lines.count - 1]
        guard selection.length == 0 else {
            return (edits.reversed(), NSRange(location: first.location, length: NSMaxRange(last) - first.location + delta))
        }
        // The caret's distance from the end of its line is untouched text, so it survives the change.
        let fromEnd = NSMaxRange(first) - selection.location
        return (edits.reversed(), NSRange(location: first.location + max(0, first.length + delta - fromEnd), length: 0))
    }

    /// What Return does on a list line: the next item, or on an empty item the end of the list.
    /// Nil anywhere else, Return there is just a new line.
    static func returnEdit(in text: String, at selection: NSRange) -> Edit? {
        let string = text as NSString
        var line = string.lineRange(for: NSRange(location: selection.location, length: 0))
        if line.length > 0, string.character(at: NSMaxRange(line) - 1) == 0x0A { line.length -= 1 }
        let content = string.substring(with: line)
        guard let prefix = listPrefixLength(content),
              selection.location >= line.location + prefix,
              NSMaxRange(selection) <= NSMaxRange(line) else { return nil }
        if line.length == prefix {
            return (NSRange(location: line.location, length: prefix), "")
        }
        if content.hasPrefix(bullet) { return (selection, "\n" + bullet) }
        let number = Int(content.prefix(prefix - 2)) ?? 0
        return (selection, "\n\(number + 1). ")
    }

    /// The body as saved: trimmed like the title, and without an empty last item, which Done on a
    /// fresh "• " would otherwise keep as a lone "•".
    static func trimmedBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed[..<trimmed.endIndex].lastIndex(of: "\n").map { trimmed.index(after: $0) } ?? trimmed.startIndex
        let last = trimmed[start...]
        guard last == "•" || (last.hasSuffix(".") && isItemNumber(last.dropLast())) else { return trimmed }
        return trimmed[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Pieces

    private static func parse(_ body: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    }

    /// `• `, or up to three digits and `. `, at the start of a line: its length in UTF-16 units.
    private static func listPrefixLength(_ line: String) -> Int? {
        if line.hasPrefix(bullet) { return (bullet as NSString).length }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard isItemNumber(digits), line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return digits.count + 2
    }

    private static func isItemNumber(_ digits: Substring) -> Bool {
        (1...3).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func escaped(_ line: String) -> String {
        var result = ""
        for character in line {
            if "\\*_~`[<&".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func wrap(_ line: String, in marks: String) -> String {
        let leading = line.prefix { $0.isWhitespace }
        guard !marks.isEmpty, leading.count < line.count else { return line }
        let trailing = String(line.reversed().prefix { $0.isWhitespace }.reversed())
        let core = line.dropFirst(leading.count).dropLast(trailing.count)
        // Each mark reads the same backwards, so the reversed opening is the matching closing.
        return leading + marks + core + String(marks.reversed()) + trailing
    }
}
