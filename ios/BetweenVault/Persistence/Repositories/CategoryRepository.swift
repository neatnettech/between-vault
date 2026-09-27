import Foundation
import SwiftData

@MainActor
final class CategoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func categories() throws -> [Category] {
        let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sort)]))
        return records.map { Category(id: $0.id, name: $0.name, sort: $0.sort) }
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

    func delete(id: UUID) throws {
        let matches = try context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id }))
        for record in matches {
            context.delete(record)
        }
        try context.save()
    }
}
