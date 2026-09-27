import Foundation

enum NoteState: String, Codable, CaseIterable, Sendable {
    case `private`
    case sealed
    case shared
}
