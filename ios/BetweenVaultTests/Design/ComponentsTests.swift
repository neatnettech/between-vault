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

    // MARK: - Changed since sent

    private func shared(version: Int, partnerKnows: Int, state: NoteState = .shared) -> Note {
        Note(
            id: UUID(),
            title: "Boiler service",
            body: "Engineer visits every March.",
            state: state,
            categoryID: UUID(),
            version: version,
            baseVersion: 1,
            partnerKnownVersion: partnerKnows,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Reads partnerKnownVersion, not baseVersion. Spec section 16 defines base_version as the
    /// common ancestor the partner's copy was based on, which is not the same as what we last sent,
    /// and row 4.8 requires the flag to clear once the update is sent.
    @Test func changedSinceSentTracksWhatWasLastSent() {
        #expect(shared(version: 3, partnerKnows: 2).hasChangedSinceSent)
        #expect(!shared(version: 3, partnerKnows: 3).hasChangedSinceSent)
    }

    /// A freshly received item is Shared but was never edited by the receiver.
    @Test func aJustReceivedNoteIsNotFlagged() {
        #expect(!shared(version: 1, partnerKnows: 1).hasChangedSinceSent)
    }

    /// U1: the flag belongs to Shared. It is not a fourth state and never appears on the others.
    @Test func onlySharedNotesCarryTheFlag() {
        #expect(!shared(version: 3, partnerKnows: 2, state: .private).hasChangedSinceSent)
        #expect(!shared(version: 3, partnerKnows: 2, state: .sealed).hasChangedSinceSent)
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
