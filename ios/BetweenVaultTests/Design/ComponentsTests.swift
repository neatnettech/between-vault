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
}
