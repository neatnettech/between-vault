import Foundation

struct Category: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sort: Int
    /// The SF Symbol drawn on the tile. Stored rather than derived from `name`, so renaming a
    /// category keeps its icon.
    var symbol: String
    /// `nil` for user created categories. Carried as the key rather than a `Bool` so the mapping to
    /// `CategoryRecord` round trips in both directions.
    var builtInKey: BuiltInCategory?

    var isBuiltIn: Bool { builtInKey != nil }
}
