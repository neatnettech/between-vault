import Foundation
import SwiftData
import Testing

@testable import BetweenVault

@MainActor
struct NoteRepositoryTests {
    private func makeRepository() throws -> (repository: NoteRepository, container: ModelContainer, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self,
            configurations: configuration
        )
        let key = CryptoEngine.randomKey()
        let context = container.mainContext
        return (NoteRepository(context: context, vaultKey: { key }), container, context)
    }

    private func note(
        category: UUID?,
        title: String = "Boiler service",
        body: String = "Engineer visits every March.",
        state: NoteState = .private
    ) -> Note {
        Note(
            id: UUID(),
            title: title,
            body: body,
            state: state,
            categoryID: category,
            version: 1,
            baseVersion: 0,
            partnerKnownVersion: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func savingANoteEncryptsItAndItComesBackIntact() throws {
        let setup = try makeRepository()
        let home = UUID()
        let original = note(category: home)

        try setup.repository.save(original)

        let stored = try setup.context.fetch(FetchDescriptor<NoteRecord>())
        #expect(stored.count == 1)
        // The title must not be recoverable from the row itself.
        #expect(!String(decoding: stored[0].ciphertext, as: UTF8.self).contains("Boiler"))

        #expect(try setup.repository.notes(in: home) == [original])
    }

    @Test func notesAreScopedToTheirCategory() throws {
        let setup = try makeRepository()
        let home = UUID()
        let finance = UUID()
        try setup.repository.save(note(category: home, title: "Boiler"))
        try setup.repository.save(note(category: finance, title: "Mortgage"))

        #expect(try setup.repository.notes(in: home).map(\.title) == ["Boiler"])
        #expect(try setup.repository.notes(in: nil).count == 2)
    }

    @Test func countsAreGroupedByCategory() throws {
        let setup = try makeRepository()
        let home = UUID()
        let finance = UUID()
        try setup.repository.save(note(category: home))
        try setup.repository.save(note(category: home))
        try setup.repository.save(note(category: finance))

        let counts = try setup.repository.countsByCategory()
        #expect(counts == [home: 2, finance: 1])
    }

    @Test func countsHonourTheStateFilter() throws {
        let setup = try makeRepository()
        let home = UUID()
        try setup.repository.save(note(category: home, state: .private))
        try setup.repository.save(note(category: home, state: .private))
        try setup.repository.save(note(category: home, state: .sealed))

        #expect(try setup.repository.countsByCategory(state: .private) == [home: 2])
        #expect(try setup.repository.countsByCategory(state: .sealed) == [home: 1])
    }

    /// The vault home gates its first run prompt on this. A filter matching nothing must come back
    /// as an empty count map while the vault itself is still known to be non empty.
    @Test func aFilterMatchingNothingIsNotAnEmptyVault() throws {
        let setup = try makeRepository()
        let home = UUID()
        try setup.repository.save(note(category: home, state: .private))

        #expect(try setup.repository.countsByCategory(state: .shared).isEmpty)
        #expect(try setup.repository.noteCount() == 1)
    }

    @Test func noteCountIgnoresCategoryAndState() throws {
        let setup = try makeRepository()
        try setup.repository.save(note(category: UUID(), state: .private))
        try setup.repository.save(note(category: UUID(), state: .sealed))
        try setup.repository.save(note(category: nil, state: .shared))

        #expect(try setup.repository.noteCount() == 3)
    }

    @Test func deletingRemovesOnlyThatNote() throws {
        let setup = try makeRepository()
        let home = UUID()
        let doomed = note(category: home, title: "Doomed")
        try setup.repository.save(doomed)
        try setup.repository.save(note(category: home, title: "Kept"))

        try setup.repository.delete(id: doomed.id)

        #expect(try setup.repository.notes(in: home).map(\.title) == ["Kept"])
    }
}
