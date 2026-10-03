import Foundation

struct Note: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var state: NoteState
    var categoryID: UUID?
    var version: Int
    /// Spec section 16: "the version the partner's copy was based on at the last exchange". The
    /// common ancestor, used only by the fast forward check in section 18.
    var baseVersion: Int
    /// The version last put into a package for the partner. Distinct from `baseVersion`: this is
    /// what we sent, that is what it was based on. Drives the "Changed since sent" flag, and 4.4
    /// keeps it current at seal.
    var partnerKnownVersion: Int
    let createdAt: Date
    var updatedAt: Date
    /// Who made it: notes that arrived from the partner are drawn in the partner colour.
    var origin: NoteOrigin = .local
    /// Sent in this file exchange and not yet confirmed by the partner's phone (board F2). Only a
    /// confirmation from the partner makes it Shared: nobody can see whether a file arrived.
    var pendingExchangeID: String?
    /// The version that left in that file.
    var pendingVersion = 0

    /// Board F2: "Sent · not confirmed". A flag on Sealed, never a fourth state.
    var isSentNotConfirmed: Bool { state == .sealed && pendingExchangeID != nil }

    /// Board U1: a flag on Shared, never a fourth state. Edited since the last time this note left
    /// the device.
    var hasChangedSinceSent: Bool {
        state == .shared && version > partnerKnownVersion
    }

    /// The partner holds a copy once any version of this note left the phone, whatever the state
    /// says now. Only then may the app say so, and only then is Private no longer true.
    var partnerHasCopy: Bool {
        state == .shared || partnerKnownVersion > 0
    }

    /// Applies an edit. Only a change the partner would receive (title, body, category) makes a
    /// new version, so saving an untouched note never raises "Changed since sent".
    func edited(title: String, body: String, categoryID: UUID?, now: Date = .now) -> Note {
        var copy = self
        copy.title = title
        copy.body = body
        copy.categoryID = categoryID
        guard copy != self else { return self }
        copy.version += 1
        copy.updatedAt = now
        return copy
    }
}

/// Persisted as `NoteRecord.originRaw`; renaming a case orphans the stored value.
enum NoteOrigin: String, Sendable {
    case local
    case partner
}
