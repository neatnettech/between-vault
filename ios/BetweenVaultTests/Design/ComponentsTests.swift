import Foundation
import Testing

@testable import BetweenVault

struct ComponentsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ago(days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    @Test func timestampCompactLadder() {
        #expect(NoteRow.timestampString(for: now.addingTimeInterval(-30), now: now) == "now")
        #expect(NoteRow.timestampString(for: now.addingTimeInterval(-60 * 42), now: now) == "42m ago")
        #expect(NoteRow.timestampString(for: now.addingTimeInterval(-3_600 * 5), now: now) == "5h ago")
        #expect(NoteRow.timestampString(for: ago(days: 2), now: now) == "2d ago")
        #expect(NoteRow.timestampString(for: ago(days: 8), now: now) == "1w ago")
        #expect(NoteRow.timestampString(for: ago(days: 22), now: now) == "3w ago")
    }

    @Test func timestampOldNotesUseAnAbsoluteDate() {
        let text = NoteRow.timestampString(for: ago(days: 40), now: now)
        #expect(!text.contains("ago"))
        #expect(text == ago(days: 40).formatted(.dateTime.month(.abbreviated).day()))
    }

    @Test func timestampOldNotesFromAnotherYearIncludeTheYear() {
        let text = NoteRow.timestampString(for: ago(days: 700), now: now)
        #expect(!text.contains("ago"))
        #expect(text == ago(days: 700).formatted(.dateTime.month(.abbreviated).day().year()))
    }

    // MARK: - CategoryTile

    @Test func tileLabelInflectsTheNoteCount() {
        #expect(
            CategoryTile.accessibilityText(name: "Home", count: 1, subtitle: nil)
                == "Home, 1 note"
        )
        #expect(
            CategoryTile.accessibilityText(name: "Home", count: 12, subtitle: nil)
                == "Home, 12 notes"
        )
        #expect(
            CategoryTile.accessibilityText(name: "Home", count: 0, subtitle: nil)
                == "Home, 0 notes"
        )
    }

    /// `.accessibilityElement(children: .ignore)` hides the subtitle, so the label must carry it.
    @Test func tileLabelCarriesTheSubtitle() {
        #expect(
            CategoryTile.accessibilityText(
                name: "Emergency",
                count: 5,
                subtitle: "What your partner needs if something happens"
            ) == "Emergency, 5 notes, What your partner needs if something happens"
        )
    }
}
