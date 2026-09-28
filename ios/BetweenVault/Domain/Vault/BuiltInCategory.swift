import Foundation

/// The two categories that always exist. They can be renamed and reordered, never deleted, so the
/// vault is never without a category to put a note in.
///
/// The raw value is what `CategoryRecord.builtInKey` stores, so it is a persisted contract: renaming
/// a case renames the stored key and orphans the pin on every existing vault.
enum BuiltInCategory: String, CaseIterable, Sendable {
    case emergency
    case other

    /// Seed name. The user may rename the category afterwards; the key is what identifies it.
    var seedName: String {
        switch self {
        case .emergency: "Emergency"
        case .other: "Other"
        }
    }
}
