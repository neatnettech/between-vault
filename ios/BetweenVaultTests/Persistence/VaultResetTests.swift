import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Row 2.4, the store half of a reset. The Keychain half needs a signed run and is two deletes.
@MainActor
struct VaultResetTests {
    private func makeStore() throws -> (context: ModelContext, container: ModelContainer, notes: NoteRepository) {
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        try CategoryRepository(context: context).seedIfNeeded()
        let notes = NoteRepository(context: context, vaultKey: { Data(repeating: 7, count: 32) })
        try notes.save(Note(
            id: UUID(), title: "Boiler", body: "Engineer", state: .private, categoryID: nil,
            version: 1, baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now
        ))
        try CategoryRepository(context: context).add(name: "Garden")
        context.insert(ExchangeLogRecord(exchangeID: "x1", directionRaw: "sent"))
        try context.save()
        return (context, container, notes)
    }

    /// Not paired: nothing could ever open the notes again, so they go, with every category the
    /// owner made, and the six starters come back for the fresh vault.
    @Test func notPairedErasesTheNotesAndStartsTheCategoriesOver() throws {
        let store = try makeStore()
        try AppServices.eraseRecords(in: store.context)

        #expect(try store.notes.noteCount() == 0)
        #expect(try CategoryRepository(context: store.context).categories().map(\.name)
            == ["Emergency", "Home", "Documents", "Finance", "Personal", "Other"])
        #expect(try store.context.fetchCount(FetchDescriptor<ExchangeLogRecord>()) == 0)
    }

    /// Paired: the notes stay, encrypted, for the partner's recovery file; the pairing and the
    /// exchange history go with the old identity.
    @Test func pairedKeepsTheNotesForRestore() throws {
        let store = try makeStore()
        try PartnerRepository(context: store.context).save(Partner(id: UUID(), deviceID: "b", fingerprint: "f", pairedAt: .now))
        try AppServices.eraseRecords(in: store.context)

        #expect(try store.notes.noteCount() == 1)
        #expect(try CategoryRepository(context: store.context).categories().contains { $0.name == "Garden" })
        #expect(try PartnerRepository(context: store.context).partner() == nil)
        #expect(try store.context.fetchCount(FetchDescriptor<ExchangeLogRecord>()) == 0)
    }
}
