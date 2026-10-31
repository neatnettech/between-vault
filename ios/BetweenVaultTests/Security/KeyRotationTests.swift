import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Unpair gives the vault a new key, so the recovery copy left on the former partner's phone opens
/// nothing. The Keychain is a dictionary here: CI's simulator has none.
@MainActor
struct KeyRotationTests {
    private final class Keychain {
        var items: [String: Data] = [:]
        /// Set to make writes of one account fail, as a rotation cut short there would.
        var refusing: String?

        func load(_ account: String) throws -> Data? { items[account] }

        func replace(_ data: Data?, _ account: String) throws {
            if account == refusing { throw CocoaError(.fileWriteUnknown) }
            items[account] = data
        }
    }

    private let oldKey = CryptoEngine.randomKey()

    private func makeStore(notes titles: [String]) throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(for: NoteRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let notes = NoteRepository(context: container.mainContext, vaultKey: { [oldKey] in oldKey })
        for title in titles {
            try notes.save(Note(
                id: UUID(), title: title, body: "Body", state: .private, categoryID: nil,
                version: 1, baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now
            ))
        }
        return (container, container.mainContext)
    }

    private func titles(under key: Data, in context: ModelContext) throws -> Set<String> {
        Set(try NoteRepository(context: context, vaultKey: { key }).notes(in: nil).map(\.title))
    }

    /// Every note moves to the new key in one go; the old key, which the former partner's copy
    /// holds, opens none of them.
    @Test func aRotationLeavesEveryNoteUnderTheNewKeyOnly() throws {
        let store = try makeStore(notes: ["Boiler", "Wifi"])
        let keychain = Keychain()
        keychain.items[AppServices.vaultKeyAccount] = oldKey

        try AppServices.rotateVaultKey(in: store.context, load: keychain.load, replace: keychain.replace)

        let newKey = try #require(keychain.items[AppServices.vaultKeyAccount])
        #expect(newKey != oldKey)
        #expect(keychain.items[AppServices.stagedVaultKeyAccount] == nil)
        #expect(try titles(under: newKey, in: store.context) == ["Boiler", "Wifi"])
        #expect(try titles(under: oldKey, in: store.context).isEmpty)
    }

    /// Stopped after the notes were saved under the new key but before it took over: the next
    /// read finishes the job instead of stranding them.
    @Test func aRotationCutShortAfterTheSaveFinishesOnTheNextRead() throws {
        let store = try makeStore(notes: ["Boiler"])
        let keychain = Keychain()
        keychain.items[AppServices.vaultKeyAccount] = oldKey
        keychain.refusing = AppServices.vaultKeyAccount

        #expect(throws: (any Error).self) {
            try AppServices.rotateVaultKey(in: store.context, load: keychain.load, replace: keychain.replace)
        }
        let staged = try #require(keychain.items[AppServices.stagedVaultKeyAccount])
        #expect(keychain.items[AppServices.vaultKeyAccount] == oldKey, "the old key is still in place")

        keychain.refusing = nil
        try AppServices.finishRotation(in: store.context, load: keychain.load, replace: keychain.replace)

        #expect(keychain.items[AppServices.vaultKeyAccount] == staged)
        #expect(keychain.items[AppServices.stagedVaultKeyAccount] == nil)
        #expect(try titles(under: staged, in: store.context) == ["Boiler"])
    }

    /// Stopped before the notes moved: the staged key opens nothing and goes; the old key stays.
    @Test func aRotationCutShortBeforeTheSaveKeepsTheOldKey() throws {
        let store = try makeStore(notes: ["Boiler"])
        let keychain = Keychain()
        keychain.items[AppServices.vaultKeyAccount] = oldKey
        keychain.items[AppServices.stagedVaultKeyAccount] = CryptoEngine.randomKey()

        try AppServices.finishRotation(in: store.context, load: keychain.load, replace: keychain.replace)

        #expect(keychain.items[AppServices.vaultKeyAccount] == oldKey)
        #expect(keychain.items[AppServices.stagedVaultKeyAccount] == nil)
        #expect(try titles(under: oldKey, in: store.context) == ["Boiler"])
    }

    /// No notes, nothing to move: the key just goes, and the next note makes a new one.
    @Test func aVaultWithNoNotesDropsItsKey() throws {
        let store = try makeStore(notes: [])
        let keychain = Keychain()
        keychain.items[AppServices.vaultKeyAccount] = oldKey

        try AppServices.rotateVaultKey(in: store.context, load: keychain.load, replace: keychain.replace)

        #expect(keychain.items.isEmpty)
    }

    /// Restore tries every note, so one damaged note does not make the right key read as "not
    /// this vault's key".
    @Test func aDamagedNoteDoesNotRefuseTheRightKey() throws {
        let store = try makeStore(notes: [])
        store.context.insert(NoteRecord(categoryID: nil, stateRaw: "private", version: 1, baseVersion: 0, ciphertext: Data(repeating: 1, count: 40)))
        try store.context.save()
        try NoteRepository(context: store.context, vaultKey: { [oldKey] in oldKey }).save(Note(
            id: UUID(), title: "Boiler", body: "Body", state: .private, categoryID: nil,
            version: 1, baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now
        ))

        var saved: [Data] = []
        #expect(try AppServices.restore(oldKey, in: store.context) { saved.append($0) })
        #expect(saved == [oldKey])
    }
}
