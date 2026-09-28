import Foundation
import SwiftData
import Testing

@testable import BetweenVault

@MainActor
struct CategoryRepositoryTests {
    /// Returns the repository together with the container: the container must stay
    /// alive for the whole test, otherwise SwiftData traps when the context is used.
    private func makeRepository() throws -> (repository: CategoryRepository, container: ModelContainer) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self,
            configurations: configuration
        )
        return (CategoryRepository(context: container.mainContext), container)
    }

    @Test func seedingCreatesSixCategoriesExactlyOnce() throws {
        let setup = try makeRepository()
        let repository = setup.repository

        try repository.seedIfNeeded()
        try repository.seedIfNeeded()

        let categories = try repository.categories()
        #expect(categories.count == 6)
        #expect(categories.map(\.name) == ["Emergency", "Home", "Documents", "Finance", "Personal", "Other"])
        #expect(categories.filter(\.isBuiltIn).map(\.name) == ["Emergency", "Other"])
    }

    @Test func deletingACategoryMovesNotesToOther() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let finance = try repository.categories().first { $0.name == "Finance" }!
        let other = try repository.categories().first { $0.name == "Other" }!

        let context = repository.context
        context.insert(NoteRecord(id: UUID(), categoryID: finance.id, stateRaw: "private", version: 1, baseVersion: 0, ciphertext: Data()))

        try repository.delete(id: finance.id)

        let notes = try context.fetch(FetchDescriptor<NoteRecord>())
        #expect(notes.count == 1)
        #expect(notes[0].categoryID == other.id)
        #expect(try repository.categories().count == 5)
    }

    @Test func builtInCategoriesAreNeverDeleted() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let emergency = try repository.categories().first { $0.name == "Emergency" }!
        try repository.delete(id: emergency.id)

        #expect(try repository.categories().count == 6)
    }
}
