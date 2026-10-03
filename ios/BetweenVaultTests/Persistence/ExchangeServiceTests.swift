import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Rows 4.4 to 4.6 and 4.8: from sealed notes to a package the partner can open, and what sending
/// changes. "Shared means sent, not delivered."
@MainActor
struct ExchangeServiceTests {
    private let me = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let partner = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private let pairKey = CryptoEngine.randomKey()

    private struct Setup {
        let service: ExchangeService
        let notes: NoteRepository
        let categories: CategoryRepository
        let log: ExchangeLogRepository
        let container: ModelContainer
    }

    private func makeSetup(paired: Bool = true) throws -> Setup {
        let container = try ModelContainer(
            for: CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let notes = NoteRepository(context: context, vaultKey: { Data(repeating: 7, count: 32) })
        let categories = CategoryRepository(context: context)
        try categories.seedIfNeeded()
        let partners = PartnerRepository(context: context)
        if paired {
            try partners.save(Partner(id: UUID(), deviceID: partner, fingerprint: "F", pairedAt: .now))
        }
        let log = ExchangeLogRepository(context: context)
        let key = pairKey
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = ExchangeService(
            notes: notes, categories: categories, partners: partners, log: log,
            pairKey: { paired ? key : nil }, deviceID: { [me] in me }, directory: directory
        )
        return Setup(service: service, notes: notes, categories: categories, log: log, container: container)
    }

    @discardableResult
    private func addNote(_ setup: Setup, title: String, state: NoteState, version: Int = 1, partnerKnown: Int = 0, category: BetweenVault.Category? = nil) throws -> Note {
        let note = Note(
            id: UUID(), title: title, body: "\(title) body", state: state, categoryID: category?.id,
            version: version, baseVersion: partnerKnown, partnerKnownVersion: partnerKnown,
            createdAt: .now, updatedAt: .now
        )
        try setup.notes.save(note)
        return note
    }

    @Test func onlySealedNotesAreInTheOutboxAndAnUpdateIsMarked() throws {
        let setup = try makeSetup()
        try addNote(setup, title: "Private", state: .private)
        try addNote(setup, title: "New", state: .sealed)
        try addNote(setup, title: "Update", state: .sealed, version: 3, partnerKnown: 2)
        try addNote(setup, title: "Shared", state: .shared, partnerKnown: 1)

        let outbox = try setup.service.outbox()
        #expect(Set(outbox.map(\.note.title)) == ["New", "Update"])
        #expect(outbox.first { $0.note.title == "Update" }?.isUpdate == true)
        #expect(outbox.first { $0.note.title == "New" }?.isUpdate == false)
    }

    /// The file the partner gets opens with the pair key, carries the sealed notes with their
    /// category by name and key, and nothing else from the vault.
    @Test func thePackageCarriesExactlyTheSealedNotes() throws {
        let setup = try makeSetup()
        let emergency = try #require(try setup.categories.categories().first { $0.builtInKey == .emergency })
        try addNote(setup, title: "Doctor", state: .sealed, category: emergency)
        try addNote(setup, title: "Diary", state: .private)

        let prepared = try setup.service.prepare()
        let data = try Data(contentsOf: prepared.file)
        #expect(!data.contains(Data("Doctor".utf8)), "nothing readable in the file")
        let package = try PackageSerializer.package(fromFile: data)
        #expect(package.recipientDeviceID == partner)
        #expect(package.senderDeviceID == me)
        let opened = try PackageSerializer.open(package, pairKey: pairKey)
        #expect(opened.items.map(\.title) == ["Doctor"])
        #expect(opened.items[0].category == ExchangeCategory(name: emergency.name, builtInKey: "emergency", symbol: emergency.symbol))
    }

    /// Nothing changes until the share sheet reports the handoff done; then the notes are Shared at
    /// the version that left, the flag is clear, and the log has a count.
    @Test func sendingMarksSharedAndLogsTheCount() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed, version: 4, partnerKnown: 2)

        let prepared = try setup.service.prepare()
        #expect(try setup.notes.note(id: note.id)?.state == .sealed, "prepare changes nothing")

        try setup.service.markSent(prepared)
        let sent = try #require(try setup.notes.note(id: note.id))
        #expect(sent.state == .shared)
        #expect(sent.partnerKnownVersion == 4)
        #expect(sent.baseVersion == 4)
        #expect(!sent.hasChangedSinceSent)
        #expect(try setup.log.history().map(\.itemCount) == [1])
        #expect(!FileManager.default.fileExists(atPath: prepared.file.path), "the file does not linger")
    }

    /// The package claims the base the partner's copy was built on, for their fast forward check.
    @Test func anUpdateClaimsTheLastSentBase() throws {
        let setup = try makeSetup()
        try addNote(setup, title: "Boiler", state: .sealed, version: 5, partnerKnown: 3)
        let package = try PackageSerializer.package(fromFile: Data(contentsOf: setup.service.prepare().file))
        let item = try PackageSerializer.open(package, pairKey: pairKey).items[0]
        #expect(item.baseVersion == 3)
        #expect(item.version == 5)
    }

    /// An edit made while the share sheet was up stays as "Changed since sent".
    @Test func anEditDuringTheShareStaysFlagged() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed, version: 2)
        let prepared = try setup.service.prepare()
        var edited = note.edited(title: "Boiler v3", body: note.body, categoryID: nil)
        edited.state = .sealed
        try setup.notes.save(edited)

        try setup.service.markSent(prepared)
        let after = try #require(try setup.notes.note(id: note.id))
        #expect(after.partnerKnownVersion == 2)
        #expect(after.hasChangedSinceSent)
    }

    /// A cancelled share changes nothing and leaves no file behind.
    @Test func aCancelledShareChangesNothing() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed)
        let prepared = try setup.service.prepare()
        setup.service.discard(prepared)
        #expect(try setup.notes.note(id: note.id)?.state == .sealed)
        #expect(try setup.log.history().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: prepared.file.path))
    }

    @Test func notPairedOrNothingSealedMakesNoFile() throws {
        let unpaired = try makeSetup(paired: false)
        try addNote(unpaired, title: "Boiler", state: .sealed)
        #expect(throws: ExchangeService.ExchangeError.notPaired) { try unpaired.service.prepare() }

        let empty = try makeSetup()
        #expect(throws: ExchangeService.ExchangeError.nothingSealed) { try empty.service.prepare() }
    }

    /// Each package has its own key: the pair key alone, used directly, does not open it.
    @Test func eachPackageHasItsOwnKey() throws {
        let setup = try makeSetup()
        try addNote(setup, title: "Boiler", state: .sealed)
        let package = try PackageSerializer.package(fromFile: Data(contentsOf: setup.service.prepare().file))
        #expect(throws: CryptoEngine.CryptoError.self) {
            try CryptoEngine.decrypt(package.ciphertext, key: pairKey)
        }
        #expect(PackageSerializer.packageKey(pairKey: pairKey, exchangeID: "a") != PackageSerializer.packageKey(pairKey: pairKey, exchangeID: "b"))
    }

    /// Every note and the log entry are one save: when the store refuses it, nothing is marked
    /// sent. The store is opened read only (as NoteRepositoryTests does) after the notes exist.
    @Test func aRefusedSaveMarksNothingSent() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        let schema = Schema([CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self])
        let key = Data(repeating: 7, count: 32)
        let noteID: UUID
        let prepared: ExchangeService.Prepared
        do {
            let writable = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
            let context = writable.mainContext
            let notes = NoteRepository(context: context, vaultKey: { key })
            let note = Note(id: UUID(), title: "One", body: "b", state: .sealed, categoryID: nil, version: 1,
                            baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now)
            try notes.save(note)
            noteID = note.id
            try PartnerRepository(context: context).save(Partner(id: UUID(), deviceID: partner, fingerprint: "F", pairedAt: .now))
            prepared = try service(context: context, key: key).prepare()
        }
        let readOnly = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url, allowsSave: false))
        let context = readOnly.mainContext
        #expect(throws: (any Error).self) { try service(context: context, key: key).markSent(prepared) }
        // Nothing pending to be committed by a later save. Not read back: see the iOS 26.2 note on
        // saveOrRollback, where the first fetch after a rollback can return the dropped change.
        #expect(!context.hasChanges)
        _ = noteID
    }

    // MARK: Send as a file (boards F1, F2)

    /// A handover proves only that the file left: Sealed, "Sent · not confirmed", out of the outbox.
    @Test func aHandoverLeavesNotesSentNotConfirmed() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed, version: 3)
        let prepared = try setup.service.prepare()
        try setup.service.markHandedOver(prepared)

        let after = try #require(try setup.notes.note(id: note.id))
        #expect(after.state == .sealed)
        #expect(after.isSentNotConfirmed)
        #expect(after.pendingVersion == 3)
        #expect(after.partnerKnownVersion == 0, "nothing is assumed about the partner yet")
        #expect(try setup.service.outbox().isEmpty)
        #expect(try setup.service.unconfirmed().map(\.note.id) == [note.id])
        #expect(try setup.log.history().first?.unconfirmed == true)
        #expect(!FileManager.default.fileExists(atPath: prepared.file.path))
    }

    /// The partner's phone reports the exchange imported: Shared at the version that left.
    @Test func aConfirmationMakesThemShared() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed, version: 3)
        let other = try addNote(setup, title: "Other", state: .sealed)
        let prepared = try setup.service.prepare()
        try setup.service.markHandedOver(prepared)

        #expect(try setup.service.confirm(importedExchangeIDs: ["someone-else"]) == 0)
        #expect(try setup.service.confirm(importedExchangeIDs: [prepared.exchangeID]) == 2)
        let after = try #require(try setup.notes.note(id: note.id))
        #expect(after.state == .shared)
        #expect(after.partnerKnownVersion == 3)
        #expect(after.baseVersion == 3)
        #expect(!after.isSentNotConfirmed)
        #expect(try setup.notes.note(id: other.id)?.state == .shared)
        #expect(try setup.log.history().first?.unconfirmed == false)
    }

    /// An edit after the handover stays as "Changed since sent" once confirmed.
    @Test func anEditAfterTheHandoverStaysFlagged() throws {
        let setup = try makeSetup()
        let note = try addNote(setup, title: "Boiler", state: .sealed, version: 2)
        let prepared = try setup.service.prepare()
        try setup.service.markHandedOver(prepared)
        var edited = try #require(try setup.notes.note(id: note.id)).edited(title: "Boiler v3", body: "b", categoryID: nil)
        edited.state = .sealed
        try setup.notes.save(edited)

        try setup.service.confirm(importedExchangeIDs: [prepared.exchangeID])
        let after = try #require(try setup.notes.note(id: note.id))
        #expect(after.partnerKnownVersion == 2)
        #expect(after.hasChangedSinceSent)
    }

    /// F2 Send the file again packs exactly the notes still waiting.
    @Test func sendingTheFileAgainPacksTheWaitingNotes() throws {
        let setup = try makeSetup()
        try addNote(setup, title: "Waiting", state: .sealed)
        try setup.service.markHandedOver(try setup.service.prepare())
        try addNote(setup, title: "Fresh", state: .sealed)

        let again = try setup.service.prepare(resend: true)
        let package = try PackageSerializer.package(fromFile: Data(contentsOf: again.file))
        #expect(try PackageSerializer.open(package, pairKey: pairKey).items.map(\.title) == ["Waiting"])
        let fresh = try setup.service.prepare()
        let freshPackage = try PackageSerializer.package(fromFile: Data(contentsOf: fresh.file))
        #expect(try PackageSerializer.open(freshPackage, pairKey: pairKey).items.map(\.title) == ["Fresh"])
    }

    private func service(context: ModelContext, key: Data) -> ExchangeService {
        let pair = pairKey
        return ExchangeService(
            notes: NoteRepository(context: context, vaultKey: { key }),
            categories: CategoryRepository(context: context),
            partners: PartnerRepository(context: context),
            log: ExchangeLogRepository(context: context),
            pairKey: { pair }, deviceID: { [me] in me }
        )
    }
}
