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

    /// Board U1: a flag on Shared, never a fourth state. Edited since the last time this note left
    /// the device.
    var hasChangedSinceSent: Bool {
        state == .shared && version > partnerKnownVersion
    }
}
