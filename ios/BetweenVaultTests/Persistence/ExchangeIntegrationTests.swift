import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Row 5.9: two in-memory vaults exchanging real .nvlt files, both directions.
@MainActor
struct ExchangeIntegrationTests {
    /// One phone: its own store, vault key and device ID, sharing the couple's pair key.
    @MainActor
    private final class Phone {
        let id: String
        let container: ModelContainer
        let notes: NoteRepository
        let categories: CategoryRepository
        let log: ExchangeLogRepository
        let send: ExchangeService
        let receive: ImportService
        let pending: PendingPackageRepository

        init(id: String, partner: String, pairKey: Data) throws {
            self.id = id
            container = try ModelContainer(
                for: CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self, PendingPackageRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            pending = PendingPackageRepository(context: context)
            let vaultKey = CryptoEngine.randomKey()
            notes = NoteRepository(context: context, vaultKey: { vaultKey })
            categories = CategoryRepository(context: context)
            try categories.seedIfNeeded()
            let partners = PartnerRepository(context: context)
            try partners.save(Partner(id: UUID(), deviceID: partner, fingerprint: "F", pairedAt: .now))
            log = ExchangeLogRepository(context: context)
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            send = ExchangeService(notes: notes, categories: categories, partners: partners, log: log,
                                   pairKey: { pairKey }, deviceID: { id }, directory: directory)
            receive = ImportService(context: context, notes: notes, categories: categories, partners: partners, log: log,
                                    pairKey: { pairKey }, deviceID: { id })
        }

        @discardableResult
        func write(_ title: String, body: String = "text", state: NoteState = .sealed, category: BuiltInCategory? = nil) throws -> Note {
            let categoryID = try category.flatMap { key in try categories.categories().first { $0.builtInKey == key }?.id }
            let note = Note(id: UUID(), title: title, body: body, state: state, categoryID: categoryID, version: 1,
                            baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now)
            try notes.save(note)
            return note
        }

        func edit(_ id: UUID, body: String, seal: Bool = true) throws {
            let note = try #require(try notes.note(id: id))
            var edited = note.edited(title: note.title, body: body, categoryID: note.categoryID)
            if seal { edited.state = .sealed }
            try notes.save(edited)
        }

        func seal(_ id: UUID) throws {
            var note = try #require(try notes.note(id: id))
            note.state = .sealed
            try notes.save(note)
        }

        /// Seals and "AirDrops": the share sheet completes, the file's bytes go to the other phone.
        func sendAll() throws -> Data {
            let prepared = try send.prepare()
            let data = try Data(contentsOf: prepared.file)
            try send.markSent(prepared)
            return data
        }
    }

    private let idA = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let idB = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private func makePhones() throws -> (a: Phone, b: Phone) {
        let key = CryptoEngine.randomKey()
        return (try Phone(id: idA, partner: idB, pairKey: key), try Phone(id: idB, partner: idA, pairKey: key))
    }

    @Test func aCleanExchangeLandsAsSharedPartnerNotesInTheRightCategory() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Doctor", body: "Dr Smith", category: .emergency)
        let incoming = try b.receive.inspect(try a.sendAll())
        #expect(incoming.items.map(\.change) == [.new])
        try b.receive.accept(incoming)

        let received = try #require(try b.notes.note(id: note.id))
        #expect(received.body == "Dr Smith")
        #expect(received.state == .shared)
        #expect(received.origin == .partner)
        #expect(!received.hasChangedSinceSent)
        let emergency = try b.categories.categories().first { $0.builtInKey == .emergency }
        #expect(received.categoryID == emergency?.id)
        #expect(try b.log.history().first?.direction == .received)
    }

    /// Board 9d: the same file twice is "already imported", not a second import.
    @Test func theSameFileTwiceIsAlreadyImported() throws {
        let (a, b) = try makePhones()
        try a.write("Doctor")
        let file = try a.sendAll()
        try b.receive.accept(try b.receive.inspect(file))
        #expect {
            _ = try b.receive.inspect(file)
        } throws: { error in
            if case ImportService.ImportFailure.alreadyImported = error { true } else { false }
        }
    }

    /// Send again: a second package with the same version changes nothing on the receiving phone.
    @Test func sendingTheSameVersionAgainChangesNothing() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Doctor")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.seal(note.id)
        let again = try b.receive.inspect(try a.sendAll())
        #expect(again.items.map(\.change) == [.unchanged(local: try #require(try b.notes.note(id: note.id)))])
    }

    /// U4: the partner changed it, this phone did not: it is replaced.
    @Test func anUpdateFastForwards() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.edit(note.id, body: "v2")
        let incoming = try b.receive.inspect(try a.sendAll())
        guard case .update = incoming.items.first?.change else { Issue.record("\(incoming.items)"); return }
        try b.receive.accept(incoming)
        #expect(try b.notes.note(id: note.id)?.body == "v2")
    }

    /// The partner's edit comes back the other way and fast forwards there too.
    @Test func anEditGoesBackTheOtherWay() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try b.edit(note.id, body: "b's edit")
        let incoming = try a.receive.inspect(try b.sendAll())
        guard case .update = incoming.items.first?.change else { Issue.record("\(incoming.items)"); return }
        try a.receive.accept(incoming)
        #expect(try a.notes.note(id: note.id)?.body == "b's edit")
        #expect(try a.notes.note(id: note.id)?.origin == .local, "still A's note")
    }

    /// Both edited the same version: a conflict, even though both are now v2. Spec 18 alone would
    /// call equal versions a no-op and drop B's edit.
    @Test func twoEditsOfTheSameVersionConflict() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.edit(note.id, body: "a's edit")
        try b.edit(note.id, body: "b's edit", seal: false)
        let incoming = try b.receive.inspect(try a.sendAll())
        #expect(incoming.conflicts.count == 1)
    }

    @Test(arguments: [ImportService.Resolution.keepMine, .keepPartners, .keepBoth])
    func everyResolutionKeepsWhatItSays(_ resolution: ImportService.Resolution) throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.edit(note.id, body: "a's edit")
        try b.edit(note.id, body: "b's edit", seal: false)
        let incoming = try b.receive.inspect(try a.sendAll())
        try b.receive.accept(incoming, resolutions: [note.id: resolution])

        let all = try b.notes.notes(in: nil)
        switch resolution {
        case .keepMine:
            #expect(try b.notes.note(id: note.id)?.body == "b's edit")
            #expect(try b.notes.note(id: note.id)?.hasChangedSinceSent == true, "mine is ahead of what A has")
        case .keepPartners:
            #expect(try b.notes.note(id: note.id)?.body == "a's edit")
        case .keepBoth:
            #expect(try b.notes.note(id: note.id)?.body == "b's edit")
            #expect(all.contains { $0.title == "Boiler (partner's copy)" && $0.body == "a's edit" })
            #expect(try b.log.history().first?.conflictsKeptBoth == 1)
        }
    }

    /// Keep mine, then send: A fast forwards to B's text, no second conflict.
    @Test func keepMineThenSendingBackFastForwards() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.edit(note.id, body: "a's edit")
        try b.edit(note.id, body: "b's edit", seal: false)
        try b.receive.accept(try b.receive.inspect(try a.sendAll()), resolutions: [note.id: .keepMine])
        try b.seal(note.id)
        let back = try a.receive.inspect(try b.sendAll())
        guard case .update = back.items.first?.change else { Issue.record("\(back.items)"); return }
    }

    /// A conflict without an answer imports nothing at all.
    @Test func anUnresolvedConflictImportsNothing() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        try a.edit(note.id, body: "a's edit")
        try a.write("New one")
        try b.edit(note.id, body: "b's edit", seal: false)
        let incoming = try b.receive.inspect(try a.sendAll())
        #expect(throws: (any Error).self) { try b.receive.accept(incoming) }
        #expect(!b.container.mainContext.hasChanges)
        #expect(try b.notes.notes(in: nil).count == 1)
    }

    /// 9b: a package made for another phone.
    @Test func aPackageForAnotherPhoneIsRefused() throws {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let c = try Phone(id: "11111111-2222-3333-4444-555555555555", partner: idA, pairKey: key)
        try a.write("Doctor")
        #expect(throws: ImportService.ImportFailure.wrongDevice) { try c.receive.inspect(try a.sendAll()) }
    }

    /// 9a: a flipped byte, or not a package at all.
    @Test func aDamagedFileIsRefused() throws {
        let (a, b) = try makePhones()
        try a.write("Doctor")
        var file = try a.sendAll()
        let package = try PackageSerializer.package(fromFile: file)
        var bytes = package.ciphertext
        bytes[bytes.count - 1] ^= 1
        file = try PackageSerializer.fileData(SealedPackage(
            protocolVersion: package.protocolVersion, senderDeviceID: package.senderDeviceID,
            recipientDeviceID: package.recipientDeviceID, exchangeID: package.exchangeID,
            createdAt: package.createdAt, ciphertext: bytes))
        #expect(throws: ImportService.ImportFailure.damaged) { try b.receive.inspect(file) }
        #expect(throws: ImportService.ImportFailure.damaged) { try b.receive.inspect(Data("hello".utf8)) }
    }

    /// Board 18: a declined file is logged, and opening it again asks again.
    @Test func declineIsLoggedAndAsksAgain() throws {
        let (a, b) = try makePhones()
        try a.write("Doctor")
        let file = try a.sendAll()
        try b.receive.decline(try b.receive.inspect(file))
        #expect(try b.log.history().first?.direction == .declined)
        #expect(try b.receive.inspect(file).items.count == 1)
    }

    /// A category the receiver does not have arrives with the sender's name and icon.
    @Test func aMissingCategoryIsCreated() throws {
        let (a, b) = try makePhones()
        let garden = try a.categories.add(name: "Garden", symbol: "leaf")
        let note = Note(id: UUID(), title: "Roses", body: "b", state: .sealed, categoryID: garden.id, version: 1,
                        baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now)
        try a.notes.save(note)
        try b.receive.accept(try b.receive.inspect(try a.sendAll()))
        let created = try #require(try b.categories.categories().first { $0.name == "Garden" })
        #expect(created.symbol == "leaf")
        #expect(try b.notes.note(id: note.id)?.categoryID == created.id)
    }

    /// Board F2 end to end: A hands a file over, B imports it, and B's imported exchange IDs (sent
    /// during an exchange nearby) confirm A's notes as Shared. B's later edit then fast forwards
    /// on A, since the ancestor was only set once B really had it.
    @Test func aFileSendIsConfirmedByThePartnersImportedIDs() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler", body: "v1")
        let prepared = try a.send.prepare()
        let file = try Data(contentsOf: prepared.file)
        try a.send.markHandedOver(prepared)
        #expect(try a.notes.note(id: note.id)?.isSentNotConfirmed == true)

        try b.receive.accept(try b.receive.inspect(file))
        #expect(try a.send.confirm(importedExchangeIDs: try b.log.receivedExchangeIDs()) == 1)
        #expect(try a.notes.note(id: note.id)?.state == .shared)

        try b.edit(note.id, body: "b's edit")
        let back = try a.receive.inspect(try b.sendAll())
        guard case .update = back.items.first?.change else { Issue.record("\(back.items)"); return }
    }

    /// Lost on the way: the file never reached B. A's notes stay "Sent · not confirmed", and a
    /// second file still lands on B as new.
    @Test func aLostFileStaysUnconfirmedAndCanBeSentAgain() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Boiler")
        try a.send.markHandedOver(try a.send.prepare())
        #expect(try a.send.confirm(importedExchangeIDs: try b.log.receivedExchangeIDs()) == 0)
        #expect(try a.notes.note(id: note.id)?.isSentNotConfirmed == true)

        let again = try a.send.prepare(resend: true)
        let file = try Data(contentsOf: again.file)
        try a.send.markHandedOver(again)
        let incoming = try b.receive.inspect(file)
        #expect(incoming.items.map(\.change) == [.new])
        try b.receive.accept(incoming)
        #expect(try a.send.confirm(importedExchangeIDs: try b.log.receivedExchangeIDs()) == 1)
    }

    /// R2 Decide later: the file waits encrypted, opens to the same review later, and stops
    /// waiting once accepted. Nothing lands before that.
    @Test func decideLaterKeepsTheFileUntilAccepted() throws {
        let (a, b) = try makePhones()
        let note = try a.write("Doctor", body: "Dr Smith")
        let file = try a.sendAll()
        let incoming = try b.receive.inspect(file)
        try b.pending.keep(exchangeID: incoming.exchangeID, data: file, itemCount: incoming.items.count)

        let waiting = try b.pending.all()
        #expect(waiting.map(\.itemCount) == [1])
        #expect(!waiting[0].data.contains(Data("Dr Smith".utf8)), "kept as it arrived, encrypted")
        #expect(try b.notes.note(id: note.id) == nil, "nothing lands before Accept")

        let again = try b.receive.inspect(waiting[0].data)
        try b.receive.accept(again)
        try b.pending.remove(again.exchangeID)
        #expect(try b.pending.all().isEmpty)
        #expect(try b.notes.note(id: note.id)?.body == "Dr Smith")
    }

    /// Keeping the same file twice keeps it once.
    @Test func theSameFileWaitsOnce() throws {
        let (a, b) = try makePhones()
        try a.write("Doctor")
        let file = try a.sendAll()
        let incoming = try b.receive.inspect(file)
        try b.pending.keep(exchangeID: incoming.exchangeID, data: file, itemCount: 1)
        try b.pending.keep(exchangeID: incoming.exchangeID, data: file, itemCount: 1)
        #expect(try b.pending.all().count == 1)
    }
}
