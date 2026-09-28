import Foundation
import SwiftData

@MainActor
final class CategoryRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Only Emergency and Other are built in. The other four starters are ordinary
    /// user categories: deletable, with notes moving to Other.
    private static let starters: [(name: String, key: String?, sort: Int)] = [
        ("Emergency", "emergency", 0),
        ("Home", nil, 1),
        ("Documents", nil, 2),
        ("Finance", nil, 3),
        ("Personal", nil, 4),
        ("Other", "other", 5),
    ]

    /// First launch only: create the six starter categories. Emergency and Other
    /// are built in and can never be deleted.
    func seedIfNeeded() throws {
        let count = try context.fetchCount(FetchDescriptor<CategoryRecord>())
        guard count == 0 else { return }
        for item in Self.starters {
            context.insert(CategoryRecord(name: item.name, sort: item.sort, builtInKey: item.key))
        }
        try context.save()
    }

    func categories() throws -> [Category] {
        let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sort)]))
        return records.map {
            Category(id: $0.id, name: $0.name, sort: $0.sort, isBuiltIn: $0.builtInKey != nil)
        }
    }

    func save(_ category: Category) throws {
        let id = category.id
        if let existing = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            existing.name = category.name
            existing.sort = category.sort
        } else {
            context.insert(CategoryRecord(id: category.id, name: category.name, sort: category.sort))
        }
        try context.save()
    }

    /// Deletes a user created category. Its notes move to Other, no notes are deleted.
    /// Built in categories are refused: they can be renamed and moved, never deleted.
    func delete(id: UUID) throws {
        let matches = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        )
        guard let record = matches.first, record.builtInKey == nil else { return }

        let otherKey: String? = "other"
        let other = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.builtInKey == otherKey })
        ).first

        let notes = try context.fetch(FetchDescriptor<NoteRecord>())
        for note in notes where note.categoryID == id {
            note.categoryID = other?.id
        }

        context.delete(record)
        try context.save()
    }
}
