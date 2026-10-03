import SwiftUI

// MARK: - StateBadge

/// Board 0: icon plus word, never colour alone, so the state reads in grayscale and for
/// colourblind users. "Changed since sent" is a flag on Shared, not a fourth state.
struct StateBadge: View {
    let state: NoteState
    var changedSinceSent: Bool = false
    /// Board F2: sent as a file, not yet confirmed. Drawn in place of Sealed, as an outlined teal
    /// flag, the Shared side counterpart of "Changed since sent".
    var sentNotConfirmed: Bool = false

    struct Spec: Equatable {
        let word: String
        let symbol: String
        let voiceOver: String

        /// Board 3 draws the filter chips with outline glyphs where the badge uses the filled pair.
        /// Derived here so the chips and the badge cannot drift into two separate tables.
        var outlineSymbol: String { symbol.replacingOccurrences(of: ".fill", with: "") }
    }

    static func spec(for state: NoteState, changedSinceSent: Bool) -> Spec {
        let word: String
        let symbol: String
        switch state {
        case .private: (word, symbol) = (Copy.statePrivate, "lock.fill")
        case .sealed: (word, symbol) = (Copy.stateSealed, "envelope.fill")
        case .shared: (word, symbol) = (Copy.stateShared, "person.2.fill")
        }
        let flagged = changedSinceSent && state == .shared
        let voiceOver = flagged
            ? Copy.sharedChangedVoiceOver
            : state == .sealed ? Copy.sealedVoiceOver : Copy.stateVoiceOver(word)
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
        if sentNotConfirmed && state == .sealed {
            HStack(spacing: Theme.Space.xxs) {
                Image(systemName: "paperplane")
                    .imageScale(.small)
                Text(Copy.sentNotConfirmed)
            }
            .font(Theme.Typography.badge)
            .foregroundStyle(Theme.Colors.sharedBadgeInk)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.sm)
            .background(Theme.Colors.surface, in: Capsule())
            .overlay { Capsule().stroke(Theme.Colors.sentNotConfirmedRing, lineWidth: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.sentNotConfirmedVoiceOver)
        } else {
            badge
        }
    }

    private var badge: some View {
        HStack(spacing: Theme.Space.xxs) {
            Image(systemName: spec.symbol)
                .imageScale(.small)
            Text(spec.word)
            if isFlagged {
                HStack(spacing: Theme.Space.xxs) {
                    Image(systemName: "flag.fill")
                        .imageScale(.small)
                    Text(Copy.changedSinceSent)
                }
                .padding(.vertical, Theme.Space.xxs / 2)
                .padding(.horizontal, Theme.Space.xs)
                .foregroundStyle(Theme.Colors.changedFlagInk)
                .background(Theme.Colors.changedFlagBG, in: Capsule())
            }
        }
        .font(Theme.Typography.badge)
        .foregroundStyle(ink)
        .padding(.vertical, Theme.Space.xxs)
        .padding(.horizontal, Theme.Space.sm)
        .background(background, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.voiceOver)
    }
}

// MARK: - NoteRow

/// Board 4: title with a trailing compact date on the first line, a two line preview,
/// then the state badge on its own line. Row padding comes from the board's `.nr` spec.
struct NoteRow: View {
    let note: Note

    /// Board 4 shows "2d ago", "1w ago", "3w ago", then an absolute date ("Jun 12"), and U1 shows
    /// "Just now". The minute and hour rungs are derived, the boards never show them.
    ///
    /// `nonisolated` because `View` is `@MainActor`, which would otherwise pull this pure date
    /// arithmetic onto the main actor and make it unreachable from a nonisolated test.
    nonisolated static func timestampString(for date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        let days = Int(seconds / 86_400)
        if seconds < 60 { return Copy.justNow }
        if seconds < 3_600 { return Copy.minutesAgo(Int(seconds / 60)) }
        if seconds < 86_400 { return Copy.hoursAgo(Int(seconds / 3_600)) }
        if days < 7 { return Copy.daysAgo(days) }
        if days < 28 { return Copy.weeksAgo(days / 7) }
        var style = Date.FormatStyle()
            .month(.abbreviated)
            .day()
        if !Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(note.title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: Theme.Space.xs)
                Text(Self.timestampString(for: note.updatedAt))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            Text(note.body)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.secondary)
                .lineLimit(2)
                // lineLimit only shortens what is drawn; VoiceOver would read the whole body.
                .accessibilityLabel(String(note.body.prefix(120)))
            HStack(spacing: Theme.Space.xs) {
                StateBadge(state: note.state, changedSinceSent: note.hasChangedSinceSent, sentNotConfirmed: note.isSentNotConfirmed)
                // Never colour alone: the bar is paired with words.
                if note.origin == .partner {
                    Text(Copy.fromPartnerLabel)
                        .font(Theme.Typography.badge)
                        .foregroundStyle(Theme.Colors.partner)
                }
            }
        }
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
        .overlay(alignment: .leading) {
            if note.origin == .partner {
                Capsule()
                    .fill(Theme.Colors.partner)
                    .frame(width: 3)
                    .padding(.vertical, Theme.Space.sm)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CategoryTile

/// Board 3: a card tile, icon plus name and count. The Emergency tile adds a subtitle
/// and spans the full width.
struct CategoryTile: View {
    let name: String
    let count: Int
    /// Comes from the stored category, never derived from `name`: the name is user editable once 1.7
    /// ships rename, and it is English, so keying the icon on it would lose the glyph on any rename
    /// and on any translation.
    let symbol: String
    var subtitle: String?

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 24

    /// "Home, 1 note" rather than "1 notes". `inflect:` also hands localisation the plural rule.
    /// The subtitle is included because `.accessibilityElement(children: .ignore)` would otherwise
    /// make the Emergency tile's subtitle unreachable to VoiceOver.
    nonisolated static func accessibilityText(name: String, count: Int, subtitle: String?) -> String {
        let counted = String(
            AttributedString(localized: "^[\(count) note](inflect: true)").characters
        )
        return [name, counted, subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? Theme.Space.lg : Theme.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: iconSize))
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: Theme.Space.xs)
                    Text("\(count)")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.secondary)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(name: name, count: count, subtitle: subtitle))
    }
}

// MARK: - FilterChip

/// Board 3: state filter chips. Selected is a dark fill, not the accent.
///
/// The chip owns its `Button`, so the accessibility element and the `.isSelected` trait are the same
/// view. Wrapping a plain-styled `Button` around a chip instead would put the trait on the label and
/// leave the button announcing no selection state.
struct FilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
            }
            .font(Theme.Typography.subheadline)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Theme.Colors.bg : Theme.Colors.text)
            .background(isSelected ? Theme.Colors.text : Theme.Colors.surface, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(Theme.Colors.hairline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

/// Six digits grouped 3 + 3. At XXXL Dynamic Type and beyond the groups stack rather than truncate.
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
        // Keyed by position, not value: the two halves of a code like "481481" are equal, and
        // `id: \.self` would give them the same SwiftUI identity.
        let keyed = Array(groups.enumerated())
        Group {
            if typeSize >= .xxxLarge {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(keyed, id: \.offset) { Text($0.element).font(font) }
                }
            } else {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(keyed, id: \.offset) { Text($0.element).font(font) }
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
            .accessibilityLabel("\(Copy.fingerprint) \(groups.joined(separator: ", "))")
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
                .accessibilityHidden(true)
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
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.footnote)
        }
        .foregroundStyle(Theme.Colors.onAccent)
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.toast))
    }
}

// MARK: - Passcode entry

/// Boards 2e and 1a: six digit dots over a 3 by 4 keypad. Light or dark follows the color scheme,
/// so onboarding draws it light and the lock screen dark. Calls `onComplete` at the sixth digit;
/// the owner of `digits` clears it.
struct PasscodeEntry: View {
    @Binding var digits: String
    let onComplete: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 3)

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            HStack(spacing: 18) {
                ForEach(0..<Passcode.length, id: \.self) { index in
                    Circle()
                        .fill(index < digits.count ? Theme.Colors.text : .clear)
                        .overlay { Circle().stroke(index < digits.count ? .clear : Theme.Colors.digitRing, lineWidth: 1.5) }
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Copy.digitsEntered(digits.count))

            LazyVGrid(columns: columns, spacing: Theme.Space.md) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self, content: key)
                Color.clear.accessibilityHidden(true)
                key("0")
                Button {
                    if !digits.isEmpty { digits.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.Colors.text)
                .accessibilityLabel(Copy.delete)
            }
            .padding(.horizontal, 18)
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            guard digits.count < Passcode.length else { return }
            digits.append(digit)
            if digits.count == Passcode.length { onComplete(digits) }
        } label: {
            Text(digit)
                .font(.title)
                .frame(width: 76, height: 76)
                .background(Theme.Colors.keypadKey, in: Circle())
        }
        .foregroundStyle(Theme.Colors.text)
    }
}

// MARK: - Dark panel (boards X1, P1: the area on top of Exchange and Partner)

/// The dark area on top of the Exchange and Partner tabs: dark in both appearances, as drawn.
struct DarkPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) { content }
            .foregroundStyle(Color.white)
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.lockScreen, in: RoundedRectangle(cornerRadius: 20))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
    }
}

/// A row of text that reads side by side, and stacks at accessibility sizes so neither side is
/// squeezed to a word per line. Leave `Spacer(minLength: 0)` in the content, not a bare Spacer:
/// the stacked layout would give it the default minimum height.
struct ReflowRow<Content: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xxs))
            : AnyLayout(HStackLayout(alignment: alignment))
        layout { content }
    }
}

/// A panel's title, subtitle and the pill on the right.
struct PanelHeader: View {
    let title: String
    var subtitle: String?
    let pill: String
    var pillIcon: String?
    var pillMuted = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xs))
            : AnyLayout(HStackLayout(alignment: .top))
        layout {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Typography.title3).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(Theme.Typography.footnote).opacity(0.75) }
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            Group {
                if let pillIcon { Label(pill, systemImage: pillIcon) } else { Text(pill) }
            }
            .font(Theme.Typography.footnote.weight(.semibold))
            .foregroundStyle(pillMuted ? Color.white : Theme.Colors.onAccentTint)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.sm)
            .background(pillMuted ? Color.white.opacity(0.12) : Theme.Colors.accentTint, in: Capsule())
        }
    }
}

/// A counter on the panel; amber when it warns.
struct PanelChip: View {
    let text: String
    var warning = false

    var body: some View {
        Text(text)
            .font(Theme.Typography.footnote.weight(.semibold))
            .foregroundStyle(warning ? Theme.Colors.sealedBadgeInk : Color.white)
            .padding(.vertical, Theme.Space.xxs)
            .padding(.horizontal, Theme.Space.sm)
            .background(warning ? Theme.Colors.sealedBadgeBG : Color.white.opacity(0.12), in: Capsule())
    }
}

/// The panel's one main action, teal, full width.
struct PanelPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.Colors.onAccent)
        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }
}

/// The fallback under the main action: a row, not a second button.
struct PanelAltRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Divider().overlay(Color.white.opacity(0.15))
            Button(action: action) {
                HStack {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.Typography.body)
                        Text(subtitle).font(Theme.Typography.footnote).opacity(0.75)
                    }
                    Spacer()
                    if enabled {
                        Image(systemName: "chevron.right").font(Theme.Typography.footnote).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.55)
        }
    }
}

// MARK: - A pair of equal buttons

/// Boards 8, N3, R2: a quiet action and the main one at equal size, Cancel or Decline never
/// smaller than send. Side by side while the wider label fits half the width on one line;
/// otherwise stacked full width, the main action on top. A label never wraps inside a half width
/// button (found on a real phone: "Create encrypted file" broke over two lines).
struct EqualButtons: View {
    let secondary: String
    let primary: String
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        EqualOrStacked(spacing: Theme.Space.sm) {
            Button(action: onSecondary) { Text(secondary) }
                .buttonStyle(.vaultSecondary)
            Button(action: onPrimary) { Text(primary) }
                .buttonStyle(.vaultPrimary)
        }
    }
}

/// Two subviews: equal widths in a row when the wider one's single line width fits half the
/// space, else a column with the second (main) one on top.
private struct EqualOrStacked: Layout {
    let spacing: CGFloat

    private func sideBySide(_ subviews: Subviews, width: CGFloat) -> Bool {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * 2 + spacing <= width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(spacing, +)
        if sideBySide(subviews, width: width) {
            let half = (width - spacing) / 2
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: half, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if sideBySide(subviews, width: bounds.width) {
            let half = (bounds.width - spacing) / 2
            for (index, subview) in subviews.enumerated() {
                let x = bounds.minX + CGFloat(index) * (half + spacing)
                subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: half, height: bounds.height))
            }
        } else {
            var y = bounds.minY
            for subview in subviews.reversed() {
                let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            }
        }
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
        partnerKnownVersion: 2,
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
                StateBadge(state: .sealed, sentNotConfirmed: true)

                NoteRow(note: note)
                CategoryTile(
                    name: "Emergency",
                    count: 5,
                    symbol: "plus.circle",
                    subtitle: Copy.emergencyTileSubtitle
                )
                CategoryTile(name: "Home", count: 1, symbol: "house")
                ReviewRow(title: "Boiler service", categoryName: "Home")
                CodeDisplay(code: "481923")
                FingerprintDisplay(fingerprint: "5F2A91C07E3B44D8")

                HStack(spacing: Theme.Space.xs) {
                    FilterChip(title: Copy.filterAll, systemImage: "square.stack.3d.up", isSelected: true) {}
                    FilterChip(title: Copy.statePrivate, systemImage: "lock", isSelected: false) {}
                    FilterChip(title: Copy.stateSealed, systemImage: "envelope", isSelected: false) {}
                    FilterChip(title: Copy.stateShared, systemImage: "person.2", isSelected: false) {}
                }

                Button(Copy.encryptAndShare) {}.buttonStyle(.vaultPrimary)
                Button(Copy.cancel) {}.buttonStyle(.vaultSecondary)
                Button(Copy.unpairPartner) {}.buttonStyle(.vaultDestructive)
                Button(Copy.encryptAndShare) {}.buttonStyle(.vaultPrimary).disabled(true)
                Button(Copy.cancel) {}.buttonStyle(.vaultSecondary).disabled(true)

                EmptyState(
                    systemImage: "tray",
                    headline: Copy.nothingSealedYet,
                    message: Copy.sealANote
                )
                Toast(systemImage: "checkmark.circle.fill", text: Copy.toastItemsImported)
                Toast(systemImage: "arrow.up.right.circle.fill", text: Copy.toastExchangeReady)
                Toast(systemImage: "doc.on.clipboard.fill", text: Copy.toastClipboardCleared)
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
