import Foundation
import SwiftData
import Testing

@testable import BetweenVault

@MainActor
struct NoteRepositoryTests {
    /// One stable key for the whole test: save and load must agree on it.
    private func makeRepository() throws -> (repository: NoteRepository, container: ModelContainer, key: Data) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self,
            configurations: configuration
        )
        let key = CryptoEngine.randomKey()
        let repository = NoteRepository(context: container.mainContext, vaultKey: { key })
        return (repository, container, key)
    }

    private func makeNote(
        id: UUID = UUID(),
        title: String = "Boiler service",
        body: String = "Engineer's number",
        state: NoteState = .private,
        categoryID: UUID? = nil,
        version: Int = 4,
        updatedAt: Date = .now
    ) -> Note {
        // Distinct nonzero history fields, so a round trip that drops or swaps them fails.
        Note(
            id: id,
            title: title,
            body: body,
            state: state,
            categoryID: categoryID,
            version: version,
            baseVersion: 2,
            partnerKnownVersion: 3,
            createdAt: .now,
            updatedAt: updatedAt
        )
    }

    // MARK: - Round trip

    @Test func saveAndLoadRoundTrip() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let note = makeNote(state: .sealed, categoryID: UUID())

        try repository.save(note)

        let reloaded = try repository.note(id: note.id)
        #expect(reloaded?.title == note.title)
        #expect(reloaded?.body == note.body)
        #expect(reloaded?.state == .sealed)
        #expect(reloaded?.categoryID == note.categoryID)
        #expect(reloaded?.version == 4)
        #expect(reloaded?.baseVersion == 2)
        #expect(reloaded?.partnerKnownVersion == 3)
    }

    /// Board 4 lists the most recently edited note first. Creation order, edit order and the
    /// expected order all differ, so neither insertion order nor createdAt can pass for updatedAt.
    @Test func notesComeBackMostRecentlyEditedFirst() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let home = UUID()
        try repository.save(makeNote(title: "Edited last", categoryID: home))
        try repository.save(makeNote(title: "Untouched", categoryID: home, updatedAt: .now.addingTimeInterval(-7_200)))
        try repository.save(makeNote(title: "Edited earlier", categoryID: home, updatedAt: .now.addingTimeInterval(-3_600)))

        #expect(try repository.notes(in: home).map(\.title) == ["Edited last", "Edited earlier", "Untouched"])
    }

    /// A store that refuses the write must leave nothing pending for a later save or autosave to
    /// commit. Without the rollback in saveOrRollback the insert stays pending.
    @Test func aRefusedSaveLeavesNothingPending() throws {
        // A store file reopened read only refuses every save.
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ModelContainer(for: CategoryRecord.self, NoteRecord.self, configurations: ModelConfiguration(url: url))
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self,
            configurations: ModelConfiguration(url: url, allowsSave: false)
        )
        let key = CryptoEngine.randomKey()
        let repository = NoteRepository(context: container.mainContext, vaultKey: { key })

        #expect(throws: (any Error).self) {
            try repository.save(makeNote())
        }
        #expect(!container.mainContext.hasChanges)
        #expect(container.mainContext.insertedModelsArray.isEmpty)
    }

    /// The store holds ciphertext, never the plaintext title or body.
    @Test func plaintextNeverReachesTheStore() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.save(makeNote(title: "Boiler service", body: "Engineer's number"))

        let record = try setup.container.mainContext.fetch(FetchDescriptor<NoteRecord>()).first
        let stored = try #require(record?.ciphertext)
        #expect(!stored.isEmpty)
        #expect(stored.range(of: Data("Boiler service".utf8)) == nil)
        #expect(stored.range(of: Data("Engineer".utf8)) == nil)
    }

    @Test func aRecordEncryptedUnderAnotherKeyDoesNotLoad() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        try repository.save(makeNote())

        // The same repository reads with its own key. A fresh key stands in for a
        // foreign vault: the AEAD check must fail, and the row must be skipped.
        let foreign = NoteRepository(context: setup.container.mainContext, vaultKey: { CryptoEngine.randomKey() })
        #expect(try foreign.notes(in: nil).isEmpty)
        #expect(try foreign.noteCount() == 1)
    }

    // MARK: - Updates

    /// Every field the update branch writes changes to a value distinct from the others, so a
    /// dropped write or a swapped pair (Seal and Move go through this branch) fails.
    @Test func updatingWritesEveryEditableField() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let original = makeNote()
        try repository.save(original)

        var updated = original
        updated.title = "Boiler service, updated"
        updated.state = .sealed
        updated.categoryID = UUID()
        updated.version = 7
        updated.baseVersion = 5
        updated.partnerKnownVersion = 6
        updated.updatedAt = original.updatedAt.addingTimeInterval(60)
        try repository.save(updated)

        let reloaded = try repository.note(id: original.id)
        #expect(reloaded?.title == "Boiler service, updated")
        #expect(reloaded?.state == .sealed)
        #expect(reloaded?.categoryID == updated.categoryID)
        #expect(reloaded?.version == 7)
        #expect(reloaded?.baseVersion == 5)
        #expect(reloaded?.partnerKnownVersion == 6)
        #expect(reloaded?.createdAt == original.createdAt)
        #expect(reloaded?.updatedAt == updated.updatedAt)
    }

    // MARK: - Delete

    @Test func deleteRemovesTheNote() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let note = makeNote()
        try repository.save(note)

        try repository.delete(id: note.id)

        #expect(try repository.note(id: note.id) == nil)
        #expect(try repository.noteCount() == 0)
    }

    @Test func noteLookupReturnsNilForAnUnknownId() throws {
        let setup = try makeRepository()
        #expect(try setup.repository.note(id: UUID()) == nil)
    }

    // MARK: - Counts

    /// Counts read state metadata only, so they work even on ciphertext that would
    /// never decrypt. This is what keeps the vault home fast.
    @Test func countsWorkOnCiphertextThatNeverDecrypts() throws {
        let setup = try makeRepository()
        let context = setup.container.mainContext
        let home = UUID()
        let finance = UUID()
        context.insert(NoteRecord(id: UUID(), categoryID: home, stateRaw: "private", version: 1, baseVersion: 0, ciphertext: Data([0x01])))
        context.insert(NoteRecord(id: UUID(), categoryID: home, stateRaw: "sealed", version: 1, baseVersion: 0, ciphertext: Data([0x01])))
        context.insert(NoteRecord(id: UUID(), categoryID: finance, stateRaw: "sealed", version: 1, baseVersion: 0, ciphertext: Data([0x01])))
        try context.save()

        let repository = setup.repository
        #expect(try repository.countsByCategory() == [home: 2, finance: 1])
        #expect(try repository.countsByCategory(state: .sealed) == [home: 1, finance: 1])
        #expect(try repository.countsByCategory(state: .shared) == [:])
        #expect(try repository.noteCount() == 3)
    }

    @Test func notesInACategoryOnlyReturnThatCategory() throws {
        let setup = try makeRepository()
        let repository = setup.repository
        let home = UUID()
        let finance = UUID()
        try repository.save(makeNote(title: "Boiler", categoryID: home))
        try repository.save(makeNote(title: "Tax", categoryID: finance))

        let homeNotes = try repository.notes(in: home)
        #expect(homeNotes.map(\.title) == ["Boiler"])
        #expect(try repository.notes(in: nil).count == 2)
    }
}
