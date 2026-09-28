import Foundation
import SwiftData

enum CategoryError: Error, Equatable {
    /// Emergency and Other exist so the vault always has somewhere to put a note.
    case builtInCannotBeDeleted
    case notFound
    /// Deleting moves notes to Other, so without Other there is nowhere safe to move them.
    /// Refusing beats silently leaving notes with no category, which hides them from every screen.
    case otherCategoryMissing
}

@MainActor
final class CategoryRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Only Emergency and Other are built in. The other four starters are ordinary
    /// user categories: deletable, with notes moving to Other.
    private static let starters: [(name: String, symbol: String, key: BuiltInCategory?)] = [
        ("Emergency", "plus.circle", .emergency),
        ("Home", "house", nil),
        ("Documents", "doc", nil),
        ("Finance", "creditcard", nil),
        ("Personal", "person", nil),
        ("Other", "ellipsis", .other),
    ]

    /// First launch: create the six starter categories. Emergency and Other are built in and can
    /// never be deleted.
    ///
    /// Also repairs a store written before `builtInKey` existed. Adding the attribute is a
    /// lightweight migration, so those rows come back with `builtInKey == nil` and would lose the
    /// two pins permanently, because the seeding branch below only runs on an empty store.
    func seedIfNeeded() throws {
        let existing = try context.fetch(
            FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sort)])
        )

        guard existing.isEmpty else {
            try backfillBuiltInKeys(in: existing)
            return
        }

        for (offset, item) in Self.starters.enumerated() {
            context.insert(
                CategoryRecord(
                    name: item.name,
                    sort: offset,
                    symbol: item.symbol,
                    builtInKey: item.key?.rawValue
                )
            )
        }
        try context.save()
    }

    /// Matches on the seed name, the only stable handle a keyless row has left.
    private func backfillBuiltInKeys(in existing: [CategoryRecord]) throws {
        guard existing.allSatisfy({ $0.builtInKey == nil }) else { return }

        var repaired = false
        for key in BuiltInCategory.allCases {
            guard let match = existing.first(where: { $0.name == key.seedName }) else { continue }
            match.builtInKey = key.rawValue
            repaired = true
        }
        if repaired { try context.save() }
    }

    func categories() throws -> [Category] {
        let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sort)]))
        return records.map(Self.domain)
    }

    func save(_ category: Category) throws {
        let id = category.id
        if let existing = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            existing.name = category.name
            existing.sort = category.sort
            existing.symbol = category.symbol
            existing.builtInKey = category.builtInKey?.rawValue
        } else {
            context.insert(
                CategoryRecord(
                    id: category.id,
                    name: category.name,
                    sort: category.sort,
                    symbol: category.symbol,
                    builtInKey: category.builtInKey?.rawValue
                )
            )
        }
        try context.save()
    }

    /// Deletes a user created category. Its notes move to Other, no notes are deleted.
    /// Built in categories are refused: they can be renamed and moved, never deleted.
    func delete(id: UUID) throws {
        let matches = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        )
        guard let record = matches.first else { throw CategoryError.notFound }
        guard record.builtInKey == nil else { throw CategoryError.builtInCannotBeDeleted }

        let otherKey = BuiltInCategory.other.rawValue
        guard let other = try context.fetch(
            FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.builtInKey == otherKey })
        ).first else { throw CategoryError.otherCategoryMissing }

        // Resolved before anything is mutated, so a missing Other cannot leave notes half moved.
        let otherID = other.id
        let orphaned = try context.fetch(
            FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.categoryID == id })
        )
        for note in orphaned {
            note.categoryID = otherID
        }

        context.delete(record)
        try context.save()
    }

    private static func domain(_ record: CategoryRecord) -> Category {
        Category(
            id: record.id,
            name: record.name,
            sort: record.sort,
            symbol: record.symbol,
            builtInKey: record.builtInKey.flatMap(BuiltInCategory.init(rawValue:))
        )
    }
}
