import Foundation

struct Note: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var state: NoteState
    var categoryID: UUID?
    var version: Int
    var baseVersion: Int
    let createdAt: Date
    var updatedAt: Date
}
