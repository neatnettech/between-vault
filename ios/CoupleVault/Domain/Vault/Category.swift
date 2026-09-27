import Foundation

struct Category: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sort: Int
}
