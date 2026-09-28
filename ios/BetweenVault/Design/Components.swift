import SwiftUI

// MARK: - StateBadge

/// Board 0: icon plus word, never colour alone, so the state reads in grayscale and for
/// colourblind users. "Changed since sent" is a flag on Shared, not a fourth state.
struct StateBadge: View {
    let state: NoteState
    var changedSinceSent: Bool = false

    struct Spec: Equatable {
        let word: String
        let symbol: String
        let voiceOver: String
    }

    static func spec(for state: NoteState, changedSinceSent: Bool) -> Spec {
        let word: String
        let symbol: String
        var helper = ""
        switch state {
        case .private: (word, symbol) = ("Private", "lock.fill")
        case .sealed:
            (word, symbol) = ("Sealed", "envelope.fill")
            helper = " Ready to send to your partner."
        case .shared: (word, symbol) = ("Shared", "person.2.fill")
        }
        let flagged = changedSinceSent && state == .shared
        let voiceOver = flagged
            ? "State: Shared. Changed since you sent it."
            : "State: \(word).\(helper)"
        return Spec(word: word, symbol: symbol, voiceOver: voiceOver)
    }

    private var spec: Spec { Self.spec(for: state, changedSinceSent: changedSinceSent) }

    private var isFlagged: Bool { changedSinceSent && state == .shared }

    private var background: Color {
        switch state {
        case .private: Theme.Colors.privateBadgeBG
        case .sealed: Theme.Colors.sealedBadgeBG
        case .shared: Theme.Colors.sharedBadgeBG
        }
    }

    private var ink: Color {
        switch state {
        case .private: Theme.Colors.privateBadgeInk
        case .sealed: Theme.Colors.sealedBadgeInk
        case .shared: Theme.Colors.sharedBadgeInk
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            Image(systemName: spec.symbol)
                .imageScale(.small)
            Text(spec.word)
            if isFlagged {
                Image(systemName: "flag.fill")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.changedFlagInk)
            }
        }
        .font(Theme.Typography.badge)
        .foregroundStyle(ink)
        .padding(.vertical, Theme.Space.xxs)
        .padding(.horizontal, 9)
        .background(background, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.voiceOver)
    }
}

// MARK: - NoteRow

struct NoteRow: View {
    let note: Note

    /// `Note` carries no explicit flag. Divergence from the version the partner has is the
    /// existing signal for it.
    private var changedSinceSent: Bool {
        note.state == .shared && note.version > note.baseVersion
    }

    private var relativeDate: String {
        note.updatedAt.formatted(.relative(presentation: .numeric))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(note.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: Theme.Space.xs)
                StateBadge(state: note.state, changedSinceSent: changedSinceSent)
            }
            Text(note.body)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .lineLimit(2)
            Text(relativeDate)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.tertiary)
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CategoryTile

struct CategoryTile: View {
    let name: String
    let count: Int
    /// `CategoryRecord` has no icon field yet, so every tile uses the default.
    var systemImage: String = "folder"

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Colors.accent)
            Text(name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: Theme.Space.xs)
            Text("\(count)")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) notes")
    }
}

// MARK: - ReviewRow

/// Used in the send and import review. Title and category only, never body text.
struct ReviewRow: View {
    let title: String
    var categoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            if let categoryName {
                Text(categoryName)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CodeDisplay

/// Six digits grouped 3 + 3. At accessibility text sizes the groups stack rather than truncate.
struct CodeDisplay: View {
    let code: String

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    private var groups: [String] {
        let digits = Array(code)
        guard digits.count > 3 else { return [code] }
        let split = digits.count / 2
        return [String(digits[..<split]), String(digits[split...])]
    }

    var body: some View {
        let font = Font.system(size: size, weight: .semibold, design: .monospaced)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(groups, id: \.self) { Text($0).font(font) }
                }
            } else {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(groups, id: \.self) { Text($0).font(font) }
                }
            }
        }
        .foregroundStyle(Theme.Colors.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
}

// MARK: - FingerprintDisplay

/// Board 11: grouped four by four, monospaced.
struct FingerprintDisplay: View {
    let fingerprint: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 28

    private var groups: [String] {
        let compact = fingerprint.filter { !$0.isWhitespace }
        return stride(from: 0, to: compact.count, by: 4).map { offset in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            return String(compact[start..<end])
        }
    }

    var body: some View {
        Text(groups.joined(separator: " "))
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.Colors.text)
            .accessibilityLabel("Fingerprint \(groups.joined(separator: ", "))")
    }
}

// MARK: - EmptyState

struct EmptyState: View {
    let systemImage: String
    let headline: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.secondary)
            Text(headline)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.text)
            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast

/// Counts and status only, never a content preview. Presentation lands with the exchange work.
struct Toast: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: systemImage)
            Text(text)
                .font(Theme.Typography.footnote)
        }
        .foregroundStyle(Theme.Colors.onAccent)
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.toast))
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.body)
                .foregroundStyle(isEnabled ? Theme.Colors.onAccent : Theme.Colors.disabledInk)
                .padding(.horizontal, Theme.Space.md)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        }

        private var fill: Color {
            guard isEnabled else { return Theme.Colors.disabledFill }
            return configuration.isPressed ? Theme.Colors.accentPressed : Theme.Colors.accent
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.body)
                .foregroundStyle(isEnabled ? Theme.Colors.onAccentTint : Theme.Colors.disabledInk)
                .padding(.horizontal, Theme.Space.md)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(
                    isEnabled ? Theme.Colors.accentTint : Theme.Colors.disabledFill,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.panel)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel)
                        .stroke(Theme.Colors.hairline)
                }
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// Board 1: destructive is text only. Red is never a fill and never the brand colour.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.body)
                .foregroundStyle(isEnabled ? Theme.Colors.destructive : Theme.Colors.disabledInk)
                .padding(.horizontal, Theme.Space.md)
                .frame(minHeight: 44)
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var vaultPrimary: Self { .init() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var vaultSecondary: Self { .init() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var vaultDestructive: Self { .init() }
}

// MARK: - Previews

private struct ComponentGallery: View {
    private let note = Note(
        id: UUID(),
        title: "Boiler service",
        body: "Engineer visits every March. Contract number is in the Documents category.",
        state: .shared,
        categoryID: UUID(),
        version: 3,
        baseVersion: 2,
        createdAt: .now,
        updatedAt: .now.addingTimeInterval(-172_800)
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text("Shared by choice.")
                    .font(Theme.Typography.hero)

                HStack(spacing: Theme.Space.xs) {
                    StateBadge(state: .private)
                    StateBadge(state: .sealed)
                    StateBadge(state: .shared)
                }
                StateBadge(state: .shared, changedSinceSent: true)

                NoteRow(note: note)
                CategoryTile(name: "Emergency", count: 5)
                ReviewRow(title: "Boiler service", categoryName: "Home")
                CodeDisplay(code: "481923")
                FingerprintDisplay(fingerprint: "5F2A91C07E3B44D8")

                Button("Encrypt & Share") {}.buttonStyle(.vaultPrimary)
                Button("Cancel") {}.buttonStyle(.vaultSecondary)
                Button("Unpair partner") {}.buttonStyle(.vaultDestructive)
                Button("Encrypt & Share") {}.buttonStyle(.vaultPrimary).disabled(true)
                Button("Cancel") {}.buttonStyle(.vaultSecondary).disabled(true)

                EmptyState(
                    systemImage: "tray",
                    headline: "Nothing sealed yet",
                    message: "Seal a note to get it ready for your partner."
                )
                Toast(systemImage: "checkmark.circle.fill", text: "3 items imported")
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview("Light") {
    ComponentGallery()
}

#Preview("Dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ComponentGallery()
        .environment(\.dynamicTypeSize, .accessibility5)
}
