import Foundation
import Testing

@testable import BetweenVault

struct ComponentsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ago(days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    @Test func timestampCompactLadder() {
        #expect(NoteRow.timestampString(for: now.addingTimeInterval(-30), now: now) == "Just now")
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

    // MARK: - Editing

    /// Done on an untouched note writes nothing new: no version, so no false "Changed since sent".
    @Test func anUntouchedEditKeepsTheVersion() {
        let note = shared(version: 3, partnerKnows: 3)
        let saved = note.edited(title: note.title, body: note.body, categoryID: note.categoryID)
        #expect(saved == note)
        #expect(!saved.hasChangedSinceSent)
    }

    /// What the partner would receive changed, so the version moves and a Shared note is flagged.
    /// A move to another category counts too: the category travels in the package.
    @Test func aRealEditBumpsTheVersionAndFlagsASharedNote() {
        let note = shared(version: 3, partnerKnows: 3)
        let later = now.addingTimeInterval(60)

        let rewritten = note.edited(title: note.title, body: "Engineer visits every April.", categoryID: note.categoryID, now: later)
        #expect(rewritten.version == 4)
        #expect(rewritten.updatedAt == later)
        #expect(rewritten.hasChangedSinceSent)

        let moved = note.edited(title: note.title, body: note.body, categoryID: UUID(), now: later)
        #expect(moved.version == 4)
    }

    /// Only a note that left the phone may claim a partner copy, and only then is Private untrue.
    @Test func partnerHasACopyOnceAVersionLeftThePhone() {
        #expect(!shared(version: 1, partnerKnows: 0, state: .private).partnerHasCopy)
        #expect(!shared(version: 1, partnerKnows: 0, state: .sealed).partnerHasCopy)
        #expect(shared(version: 1, partnerKnows: 0).partnerHasCopy)
        #expect(shared(version: 3, partnerKnows: 2, state: .sealed).partnerHasCopy)
    }

    // MARK: - Category list empty states (1.11)

    @MainActor @Test func anEmptyCategoryReadsAsEmpty() {
        let copy = NotesView.emptyCopy(filter: nil, total: 0, category: "Home")
        #expect(copy.headline == "Nothing here yet")
        #expect(NotesView.emptyCopy(filter: .sealed, total: 0, category: "Home").headline == "Nothing here yet")
    }

    /// A category hidden by a filter must never read as empty.
    @MainActor @Test func aFilteredCategoryNamesTheFilterAndTheCount() {
        let copy = NotesView.emptyCopy(filter: .sealed, total: 3, category: "Home")
        #expect(copy.headline == "No sealed notes in Home")
        #expect(copy.message == "This category has 3 notes. Clear the filter on the vault home to see them.")
        #expect(NotesView.emptyCopy(filter: .sealed, total: 1, category: "Home").message
            == "This category has 1 note. Clear the filter on the vault home to see it.")
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
