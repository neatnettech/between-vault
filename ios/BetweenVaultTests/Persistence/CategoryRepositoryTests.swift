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

    // MARK: - Seeding

    @Test func seedingCreatesSixCategoriesExactlyOnce() throws {
        let setup = try makeRepository()
        let repository = setup.repository

        try repository.seedIfNeeded()
        try repository.seedIfNeeded()

        let categories = try repository.categories()
        #expect(categories.count == 6)
        #expect(categories.map(\.name) == ["Emergency", "Home", "Documents", "Finance", "Personal", "Other"])
        #expect(categories.filter(\.isBuiltIn).map(\.name) == ["Emergency", "Other"])
        #expect(categories.first?.builtInKey == .emergency)
        #expect(categories.last?.builtInKey == .other)
    }

    @Test func seedingGivesEveryStarterItsOwnIcon() throws {
        let setup = try makeRepository()
        try setup.repository.seedIfNeeded()

        let symbols = try setup.repository.categories().map(\.symbol)
        #expect(symbols == ["plus.circle", "house", "doc", "creditcard", "person", "ellipsis"])
    }

    /// A store written before `builtInKey` existed comes back from lightweight migration with the
    /// attribute nil on every row. Without a backfill the two pins would be lost permanently,
    /// because the seeding branch only runs on an empty store.
    @Test func seedingBackfillsBuiltInKeysOnAnOlderStore() throws {
        let setup = try makeRepository()
        let context = setup.repository.context
        for (offset, name) in ["Emergency", "Home", "Documents", "Finance", "Personal", "Other"].enumerated() {
            context.insert(CategoryRecord(name: name, sort: offset))
        }
        try context.save()

        try setup.repository.seedIfNeeded()

        let categories = try setup.repository.categories()
        #expect(categories.count == 6)
        #expect(categories.filter(\.isBuiltIn).map(\.builtInKey) == [.emergency, .other])
    }

    /// The backfill must not touch a store that already carries keys, or a renamed built in
    /// category would collect a second pin.
    @Test func backfillLeavesARenamedBuiltInAlone() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        var emergency = try repository.categories().first { $0.builtInKey == .emergency }!
        emergency.name = "If something happens"
        try repository.save(emergency)

        try repository.seedIfNeeded()

        let categories = try repository.categories()
        #expect(categories.count == 6)
        #expect(categories.filter(\.isBuiltIn).map(\.name) == ["If something happens", "Other"])
    }

    // MARK: - Domain mapping

    @Test func categoryRoundTripsThroughSaveWithoutLosingItsKeyOrIcon() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        var emergency = try repository.categories().first { $0.builtInKey == .emergency }!
        emergency.name = "Emergency contacts"
        try repository.save(emergency)

        let reloaded = try repository.categories().first { $0.id == emergency.id }
        #expect(reloaded == emergency)
        #expect(reloaded?.builtInKey == .emergency)
        #expect(reloaded?.symbol == "plus.circle")
    }

    @Test func insertingANewCategoryKeepsItsIconAndStaysDeletable() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let vehicle = Category(id: UUID(), name: "Vehicle", sort: 6, symbol: "car", builtInKey: nil)
        try repository.save(vehicle)

        let reloaded = try repository.categories().first { $0.id == vehicle.id }
        #expect(reloaded == vehicle)
        #expect(reloaded?.isBuiltIn == false)
    }

    // MARK: - Delete

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

    @Test func deletingABuiltInIsRefusedWithATypedError() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let emergency = try repository.categories().first { $0.builtInKey == .emergency }!

        #expect(throws: CategoryError.builtInCannotBeDeleted) {
            try repository.delete(id: emergency.id)
        }
        #expect(try repository.categories().count == 6)
    }

    @Test func deletingAnUnknownIdIsDistinguishableFromARefusal() throws {
        let setup = try makeRepository()
        try setup.repository.seedIfNeeded()

        #expect(throws: CategoryError.notFound) {
            try setup.repository.delete(id: UUID())
        }
    }

    /// Without Other there is nowhere safe to move the notes. Refusing beats the previous
    /// behaviour, which set categoryID to nil and hid those notes from every screen.
    @Test func deletingIsRefusedWhenOtherIsMissingAndNoNoteMoves() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let context = repository.context

        let finance = CategoryRecord(name: "Finance", sort: 0)
        context.insert(finance)
        let note = NoteRecord(id: UUID(), categoryID: finance.id, stateRaw: "private", version: 1, baseVersion: 0, ciphertext: Data())
        context.insert(note)
        try context.save()

        #expect(throws: CategoryError.otherCategoryMissing) {
            try repository.delete(id: finance.id)
        }
        #expect(note.categoryID == finance.id)
        #expect(try repository.categories().count == 1)
    }

    // MARK: - Add, rename, reorder

    /// Board 3b: a new category sits above Other, which stays the catch all at the end.
    @Test func addingPlacesANewCategoryAboveOther() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let car = try repository.add(name: "Car")

        #expect(car.isBuiltIn == false)
        #expect(car.symbol == CategoryRecord.defaultSymbol)
        let names = try repository.categories().map(\.name)
        #expect(names == ["Emergency", "Home", "Documents", "Finance", "Personal", "Car", "Other"])
    }

    /// Once the user has moved Other off the end, a new category simply goes last.
    @Test func addingAppendsWhenOtherIsNotLast() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()
        var ids = try repository.categories().map(\.id)
        ids.insert(ids.removeLast(), at: 0)
        try repository.reorder(ids)

        _ = try repository.add(name: "Car")

        #expect(try repository.categories().map(\.name).suffix(2) == ["Personal", "Car"])
    }

    @Test func renamingKeepsTheIconAndTheBuiltInKey() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        let emergency = try repository.categories().first { $0.builtInKey == .emergency }!
        try repository.rename(id: emergency.id, name: "If something happens")

        let reloaded = try repository.categories().first { $0.id == emergency.id }
        #expect(reloaded?.name == "If something happens")
        #expect(reloaded?.builtInKey == .emergency)
        #expect(reloaded?.symbol == "plus.circle")
    }

    @Test func reorderPersistsTheNewOrder() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.seedIfNeeded()

        var ids = try repository.categories().map(\.id)
        let moved = ids.removeFirst()
        ids.append(moved)

        try repository.reorder(ids)

        let names = try repository.categories().map(\.name)
        #expect(names == ["Home", "Documents", "Finance", "Personal", "Other", "Emergency"])
    }
}
