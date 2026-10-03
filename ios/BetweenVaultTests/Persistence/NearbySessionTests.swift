import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Part B: two phones in one exchange nearby, over an in-memory link that delivers in order, as a
/// TCP stream would, without re-entering a session mid message.
@MainActor
struct NearbySessionTests {
    private final class Link: NearbyTransport {
        var onReceive: ((Data) -> Void)?
        var onClose: (() -> Void)?
        weak var peer: Link?
        private var inbox: [Data] = []
        private var delivering = false
        private(set) var closed = false

        func send(_ data: Data) {
            guard !closed, let peer else { return }
            peer.inbox.append(data)
            peer.drain()
        }

        private func drain() {
            guard !delivering else { return }
            delivering = true
            while !inbox.isEmpty { onReceive?(inbox.removeFirst()) }
            delivering = false
        }

        func close() {
            guard !closed else { return }
            closed = true
            peer?.closeFromPeer()
        }

        private func closeFromPeer() {
            guard !closed else { return }
            closed = true
            onClose?()
        }

        static func pair() -> (Link, Link) {
            let a = Link(), b = Link()
            a.peer = b
            b.peer = a
            return (a, b)
        }
    }

    @MainActor
    private final class Phone {
        let id: String
        let container: ModelContainer
        let notes: NoteRepository
        let log: ExchangeLogRepository
        let send: ExchangeService
        let receive: ImportService

        init(id: String, partner: String, pairKey: Data) throws {
            self.id = id
            container = try ModelContainer(
                for: CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            let vaultKey = CryptoEngine.randomKey()
            notes = NoteRepository(context: context, vaultKey: { vaultKey })
            let categories = CategoryRepository(context: context)
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
        func write(_ title: String) throws -> Note {
            let note = Note(id: UUID(), title: title, body: "text", state: .sealed, categoryID: nil, version: 1,
                            baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now)
            try notes.save(note)
            return note
        }

        func session(over link: Link, partner: String) -> NearbySession {
            NearbySession(transport: link, exchange: send, importer: receive, log: log, me: id, partner: partner)
        }
    }

    private let idA = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let idB = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private func connect() throws -> (a: Phone, b: Phone, sa: NearbySession, sb: NearbySession, la: Link) {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let b = try Phone(id: idB, partner: idA, pairKey: key)
        let (la, lb) = Link.pair()
        let sa = a.session(over: la, partner: idB)
        let sb = b.session(over: lb, partner: idA)
        sa.start()
        sb.start()
        return (a, b, sa, sb, la)
    }

    @Test func bothPhonesGreetAndConnect() throws {
        let (_, _, sa, sb, _) = try connect()
        #expect(sa.state == .connected)
        #expect(sb.state == .connected)
    }

    /// N2 to N5: send, the partner accepts, the items land, and only then are they Shared.
    @Test func sentItemsBecomeSharedOnlyOnceImported() throws {
        let (a, b, sa, sb, _) = try connect()
        let note = try a.write("Doctor")
        try sa.send([note.id])
        #expect(sa.state == .waitingForAnswer(count: 1))
        #expect(try a.notes.note(id: note.id)?.state == .sealed, "not Shared before the partner accepts")
        guard case let .incoming(incoming) = sb.state else { Issue.record("\(sb.state)"); return }
        #expect(incoming.items.map(\.incoming.title) == ["Doctor"])

        try sb.accept()
        #expect(sa.state == .delivered(count: 1))
        #expect(try a.notes.note(id: note.id)?.state == .shared)
        #expect(try b.notes.note(id: note.id)?.body == "text")
        #expect(sa.sentCount == 1)
        #expect(sb.receivedCount == 1)
    }

    /// N3 Decline: nothing lands, the sender's notes stay Sealed and can be sent again.
    @Test func declineLeavesEverythingSealed() throws {
        let (a, b, sa, sb, _) = try connect()
        let note = try a.write("Doctor")
        try sa.send([note.id])
        sb.decline()
        #expect(sa.state == .partnerDeclined)
        #expect(try a.notes.note(id: note.id)?.state == .sealed)
        #expect(try b.notes.note(id: note.id) == nil)
        try sa.send([note.id])
        #expect(sa.state == .waitingForAnswer(count: 1))
    }

    /// N2: only the ticked notes leave.
    @Test func onlyTheTickedNotesLeave() throws {
        let (a, b, sa, sb, _) = try connect()
        let kept = try a.write("Diary")
        let sent = try a.write("Doctor")
        try sa.send([sent.id])
        try sb.accept()
        #expect(try b.notes.note(id: kept.id) == nil)
        #expect(try a.notes.note(id: kept.id)?.state == .sealed)
    }

    /// Board F2: meeting confirms an earlier file send, from the partner's imported IDs.
    @Test func meetingConfirmsAnEarlierFileSend() throws {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let b = try Phone(id: idB, partner: idA, pairKey: key)
        let note = try a.write("Boiler")
        let prepared = try a.send.prepare()
        let file = try Data(contentsOf: prepared.file)
        try a.send.markHandedOver(prepared)
        try b.receive.accept(try b.receive.inspect(file))

        let (la, lb) = Link.pair()
        let sa = a.session(over: la, partner: idB)
        let sb = b.session(over: lb, partner: idA)
        sa.start()
        sb.start()
        #expect(sa.confirmedCount == 1)
        #expect(try a.notes.note(id: note.id)?.state == .shared)
    }

    /// Only the paired partner: a phone saying hello with another device ID ends the session, and
    /// nothing it sends before or after is acted on.
    @Test func aStrangerIsTurnedAway() throws {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let c = try Phone(id: "11111111-2222-3333-4444-555555555555", partner: idA, pairKey: key)
        let (la, lc) = Link.pair()
        let sa = a.session(over: la, partner: idB)
        let sc = c.session(over: lc, partner: idA)
        sa.start()
        sc.start()
        #expect(sa.state == .ended(.notYourPartner))
    }

    /// Either side can end; the other sees it, and a dropped link is said as such.
    @Test func endingAndLosingTheLink() throws {
        let (_, _, sa, sb, la) = try connect()
        sa.end()
        #expect(sb.state == .ended(.byPartner))
        let (_, _, sa2, sb2, la2) = try connect()
        la2.close()
        #expect(sb2.state == .ended(.linkLost))
        _ = (sa2, la)
    }

    /// The partner can send in the same session (N2 card): both directions in turn.
    @Test func bothDirectionsInOneSession() throws {
        let (a, b, sa, sb, _) = try connect()
        let fromA = try a.write("From A")
        try sa.send([fromA.id])
        try sb.accept()
        let fromB = try b.write("From B")
        try sb.send([fromB.id])
        try sa.accept()
        #expect(try a.notes.note(id: fromB.id)?.origin == .partner)
        #expect(sb.state == .delivered(count: 1))
    }

    /// A file the partner never got: meeting leaves it unconfirmed and lists it as not received;
    /// sending it nearby then delivers it and clears the mark.
    @Test func aFileNeverReceivedComesBackAsNotReceived() throws {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let b = try Phone(id: idB, partner: idA, pairKey: key)
        let note = try a.write("Boiler")
        try a.send.markHandedOver(try a.send.prepare())

        let (la, lb) = Link.pair()
        let sa = a.session(over: la, partner: idB)
        let sb = b.session(over: lb, partner: idA)
        sa.start()
        sb.start()
        #expect(sa.confirmedCount == 0)
        #expect(sa.notReceived == [note.id])

        try sa.send([note.id])
        try sb.accept()
        #expect(sa.notReceived.isEmpty)
        #expect(try a.notes.note(id: note.id)?.state == .shared)
        #expect(try a.notes.note(id: note.id)?.isSentNotConfirmed == false)
    }

    /// Found on two phones: a note sent as a file and imported by the partner is confirmed as the
    /// session opens, so it is Shared and no longer offered to send; sending it anyway packs nothing.
    @Test func aConfirmedFileSendIsNoLongerOffered() throws {
        let key = CryptoEngine.randomKey()
        let a = try Phone(id: idA, partner: idB, pairKey: key)
        let b = try Phone(id: idB, partner: idA, pairKey: key)
        let note = try a.write("Hxghb")
        let prepared = try a.send.prepare()
        let file = try Data(contentsOf: prepared.file)
        try a.send.markHandedOver(prepared)
        try b.receive.accept(try b.receive.inspect(file))
        #expect(try a.send.sealedForNearby().map(\.id) == [note.id], "offered before the session")

        let (la, lb) = Link.pair()
        let sa = a.session(over: la, partner: idB)
        let sb = b.session(over: lb, partner: idA)
        sa.start()
        sb.start()
        #expect(sa.confirmedCount == 1)
        #expect(try a.send.sealedForNearby().isEmpty, "Shared now, so no longer offered")
        #expect(throws: ExchangeService.ExchangeError.nothingSealed) { try sa.send([note.id]) }
        #expect(sa.state == .connected)
    }
}
