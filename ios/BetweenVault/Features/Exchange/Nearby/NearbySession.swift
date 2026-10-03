import Foundation
import Observation

/// What travels over an exchange nearby, inside the encrypted link (part C). JSON, one message per
/// frame. The package is the same .nvlt bytes a file would carry, so import, review and conflicts
/// stay one code path.
enum NearbyMessage: Codable, Equatable {
    /// First message each way. The device ID is checked against the paired partner.
    case hello(protocolVersion: Int, deviceID: String)
    /// Board F2: the exchange IDs this phone imported, IDs only, so the other phone can confirm
    /// its "Sent · not confirmed" notes. Only inside a session someone opened.
    case confirmations([String])
    /// Board N3: a package for the partner to accept or decline.
    case offer(Data)
    case accepted(exchangeID: String)
    case declined(exchangeID: String)
    /// The package is in the partner's vault: the only thing that makes items Shared (N5).
    case imported(exchangeID: String)
    case bye

    static let protocolVersion = 1
}

/// The link under a session: part C's Network framework connection, or an in-memory pair in tests.
@MainActor
protocol NearbyTransport: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func send(_ data: Data)
    func close()
}

/// Boards N2 to N5: one connected session between the paired phones, either side sending and
/// receiving. Items become Shared only when the partner's phone reports them imported.
@MainActor
@Observable
final class NearbySession {
    enum State: Equatable {
        /// Waiting for the partner's hello.
        case greeting
        /// N2: choose what to send; the partner can send too.
        case connected
        /// After Send: the partner reviews (N3 on their phone).
        case waitingForAnswer(count: Int)
        /// N4: the partner accepted; their phone is importing.
        case partnerAccepted(count: Int)
        /// N3 on this phone: the partner wants to send these.
        case incoming(ImportService.Incoming)
        /// N5 for what this phone sent.
        case delivered(count: Int)
        case partnerDeclined
        case ended(Ending)
    }

    enum Ending: Equatable {
        case byPartner
        case linkLost
        /// The hello came from a phone that is not the paired partner, or an unknown version.
        case notYourPartner
        case newerVersion
    }

    private(set) var state = State.greeting
    /// N5's summary card.
    private(set) var sentCount = 0
    private(set) var receivedCount = 0
    private(set) var conflictsCount = 0
    /// File sends this session confirmed (F2).
    private(set) var confirmedCount = 0
    /// Why the last offer from the partner could not be shown (9a to 9d).
    private(set) var incomingFailure: ImportService.ImportFailure?

    @ObservationIgnored private let transport: NearbyTransport
    @ObservationIgnored private let exchange: ExchangeService
    @ObservationIgnored private let importer: ImportService
    @ObservationIgnored private let log: ExchangeLogRepository
    @ObservationIgnored private let me: String
    @ObservationIgnored private let partner: String
    @ObservationIgnored private var outgoing: ExchangeService.Prepared?
    @ObservationIgnored private var greeted = false
    @ObservationIgnored private var saidHello = false

    init(
        transport: NearbyTransport,
        exchange: ExchangeService,
        importer: ImportService,
        log: ExchangeLogRepository,
        me: String,
        partner: String
    ) {
        self.transport = transport
        self.exchange = exchange
        self.importer = importer
        self.log = log
        self.me = me
        self.partner = partner
        transport.onReceive = { [weak self] data in self?.receive(data) }
        transport.onClose = { [weak self] in self?.linkClosed() }
    }

    /// Says hello once. Also called on the partner's hello, so this phone's hello always comes
    /// before anything else it sends: the partner trusts nothing before it.
    func start() {
        guard !saidHello else { return }
        saidHello = true
        send(.hello(protocolVersion: NearbyMessage.protocolVersion, deviceID: me))
    }

    // MARK: Sending (N2, N4, N5)

    /// N2 Send: the ticked notes as one package.
    func send(_ noteIDs: Set<UUID>) throws {
        guard state == .connected || isAfterAnswer, !noteIDs.isEmpty else { return }
        let prepared = try exchange.prepare(only: noteIDs)
        let data = try Data(contentsOf: prepared.file)
        exchange.discard(prepared)
        outgoing = prepared
        send(.offer(data))
        state = .waitingForAnswer(count: prepared.versions.count)
    }

    private var isAfterAnswer: Bool {
        switch state {
        case .delivered, .partnerDeclined: true
        default: false
        }
    }

    // MARK: Receiving (N3)

    /// N3 Accept. Conflicts need an answer each, as for a file (board 10).
    func accept(resolutions: [UUID: ImportService.Resolution] = [:]) throws {
        guard case let .incoming(incoming) = state else { return }
        send(.accepted(exchangeID: incoming.exchangeID))
        do {
            try importer.accept(incoming, resolutions: resolutions)
        } catch {
            // Nothing was imported (all or nothing): the partner's items stay unsent.
            send(.declined(exchangeID: incoming.exchangeID))
            throw error
        }
        receivedCount += incoming.items.count
        conflictsCount += incoming.conflicts.count
        send(.imported(exchangeID: incoming.exchangeID))
        state = .connected
    }

    /// N3 Decline: nothing is added; the partner sees it was declined.
    func decline() {
        guard case let .incoming(incoming) = state else { return }
        try? importer.decline(incoming)
        send(.declined(exchangeID: incoming.exchangeID))
        state = .connected
    }

    /// N5 "Stay connected to receive", or OK after a decline: back to N2.
    func resume() {
        switch state {
        case .delivered, .partnerDeclined: state = .connected
        default: break
        }
    }

    /// Done on N5, End on N2: the session ends on both phones.
    func end() {
        send(.bye)
        transport.close()
        state = .ended(.byPartner)
    }

    // MARK: Messages

    private func receive(_ data: Data) {
        guard let message = try? JSONDecoder().decode(NearbyMessage.self, from: data) else { return }
        // Nothing but a hello is trusted before the hello checked out.
        if !greeted {
            guard case let .hello(version, deviceID) = message else { return }
            guard version <= NearbyMessage.protocolVersion else { return finish(.newerVersion) }
            guard deviceID == partner else { return finish(.notYourPartner) }
            greeted = true
            state = .connected
            start()
            send(.confirmations(Array((try? log.receivedExchangeIDs()) ?? [])))
            return
        }
        switch message {
        case .hello:
            break
        case let .confirmations(ids):
            confirmedCount += (try? exchange.confirm(importedExchangeIDs: Set(ids))) ?? 0
        case let .offer(package):
            do {
                state = .incoming(try importer.inspect(package))
                incomingFailure = nil
            } catch let failure as ImportService.ImportFailure {
                incomingFailure = failure
            } catch {
                incomingFailure = .damaged
            }
        case let .accepted(exchangeID):
            if exchangeID == outgoing?.exchangeID, case let .waitingForAnswer(count) = state {
                state = .partnerAccepted(count: count)
            }
        case let .imported(exchangeID):
            guard let outgoing, outgoing.exchangeID == exchangeID else { return }
            try? exchange.markSent(outgoing)
            sentCount += outgoing.versions.count
            self.outgoing = nil
            state = .delivered(count: outgoing.versions.count)
        case let .declined(exchangeID):
            // Declined before or after accepting (a failed import): nothing landed there.
            guard outgoing?.exchangeID == exchangeID else { return }
            outgoing = nil
            state = .partnerDeclined
        case .bye:
            transport.close()
            state = .ended(.byPartner)
        }
    }

    private func send(_ message: NearbyMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        transport.send(data)
    }

    private func finish(_ ending: Ending) {
        transport.close()
        state = .ended(ending)
    }

    private func linkClosed() {
        if case .ended = state { return }
        state = .ended(.linkLost)
    }
}
