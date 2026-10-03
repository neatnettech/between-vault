import Foundation

/// Rows 4.4 to 4.6: from sealed notes to one .nvlt file, and what sending changes.
///
/// "Shared means sent, on the owner's word." The phones never talk, so the app never claims to know
/// what happened on the other phone, and iOS cannot tell either: on two real phones an interrupted
/// AirDrop still reported done. So after the handoff the owner says whether it arrived, and only
/// that makes notes Shared; a cancelled sheet or "No" changes nothing. If it later turns out not
/// to have arrived, Send again seals it once more, and importing a version twice changes nothing.
@MainActor
final class ExchangeService {
    enum ExchangeError: Error, Equatable {
        case notPaired
        case nothingSealed
    }

    /// Board 7 and U3: a sealed note, its category name, and whether the partner has a version.
    struct OutboxItem: Identifiable, Equatable {
        let note: Note
        let categoryName: String?
        var id: UUID { note.id }
        /// U3 "Update": replaces the copy the partner already has.
        var isUpdate: Bool { note.partnerHasCopy }
    }

    /// One prepared exchange: the file to hand over and what it holds, until the sheet ends.
    struct Prepared: Equatable {
        let exchangeID: String
        let file: URL
        /// Note ID to the version placed in the package.
        let versions: [UUID: Int]
    }

    private let notes: NoteRepository
    private let categories: CategoryRepository
    private let partners: PartnerRepository
    private let log: ExchangeLogRepository
    private let pairKey: () throws -> Data?
    private let deviceID: () -> String
    private let directory: URL

    init(
        notes: NoteRepository,
        categories: CategoryRepository,
        partners: PartnerRepository,
        log: ExchangeLogRepository,
        pairKey: @escaping () throws -> Data?,
        deviceID: @escaping () -> String,
        directory: URL = FileManager.default.temporaryDirectory
    ) {
        self.notes = notes
        self.categories = categories
        self.partners = partners
        self.log = log
        self.pairKey = pairKey
        self.deviceID = deviceID
        self.directory = directory
    }

    /// Board 7: sealed notes waiting to be sent, newest first. Notes already sent as a file and
    /// waiting for confirmation are not in it; they are in `unconfirmed()`.
    func outbox() throws -> [OutboxItem] {
        try items { $0.state == .sealed && $0.pendingExchangeID == nil }
    }

    /// Board F2: sent as a file, not yet confirmed by the partner's phone.
    func unconfirmed() throws -> [OutboxItem] {
        try items(where: \.isSentNotConfirmed)
    }

    private func items(where include: (Note) -> Bool) throws -> [OutboxItem] {
        let names = Dictionary(uniqueKeysWithValues: try categories.categories().map { ($0.id, $0.name) })
        return try notes.notes(in: nil)
            .filter(include)
            .map { OutboxItem(note: $0, categoryName: $0.categoryID.flatMap { names[$0] }) }
    }

    /// Board F1, Create encrypted file: the outbox in one package, written to a temporary file for
    /// the share sheet. `resend` packs the notes still waiting for confirmation instead (F2, Send
    /// the file again). Nothing about the notes changes yet.
    func prepare(resend: Bool = false, now: Date = .now) throws -> Prepared {
        guard let partner = try partners.partner(), let key = try pairKey() else { throw ExchangeError.notPaired }
        let sealed = try notes.notes(in: nil).filter { resend ? $0.isSentNotConfirmed : $0.state == .sealed && $0.pendingExchangeID == nil }
        guard !sealed.isEmpty else { throw ExchangeError.nothingSealed }
        let byID = Dictionary(uniqueKeysWithValues: try categories.categories().map { ($0.id, $0) })
        let items = sealed.map { note in
            ExchangeItem(
                objectID: note.id,
                category: note.categoryID.flatMap { byID[$0] }.map {
                    ExchangeCategory(name: $0.name, builtInKey: $0.builtInKey?.rawValue, symbol: $0.symbol)
                },
                // Spec 16 and 18: the version the partner's copy was based on, for their fast
                // forward check.
                baseVersion: note.baseVersion,
                version: note.version,
                updatedAt: note.updatedAt,
                title: note.title,
                body: note.body
            )
        }
        let exchangeID = UUID().uuidString.lowercased()
        let package = try PackageSerializer.seal(
            items: items, pairKey: key, sender: deviceID(), recipient: partner.deviceID,
            exchangeID: exchangeID, createdAt: now
        )
        // A dated, human name: it is what the partner sees in Messages or Files.
        let stamp = now.formatted(.iso8601.year().month().day())
        let file = directory.appending(path: "Between Vault \(stamp) \(exchangeID.prefix(4)).\(PackageSerializer.fileExtension)")
        try PackageSerializer.fileData(package).write(to: file, options: [.atomic, .completeFileProtection])
        return Prepared(exchangeID: exchangeID, file: file, versions: Dictionary(uniqueKeysWithValues: sealed.map { ($0.id, $0.version) }))
    }

    /// Exchange nearby (row C): the partner's phone accepted and imported it. Each note that is
    /// still sealed becomes Shared at
    /// the version that left; the partner is now taken to hold it, so it is also the common
    /// ancestor for their fast forward check (spec 16, 18). If it never arrived, a later package
    /// shows them a conflict, never a silent overwrite. An edit made while the sheet was up stays
    /// as "Changed since sent". One save for every note and the log entry, so a failure rolls all
    /// of it back and the notes stay Sealed.
    func markSent(_ prepared: Prepared, now: Date = .now) throws {
        defer { discard(prepared) }
        for (id, sentVersion) in prepared.versions {
            guard var note = try notes.note(id: id), note.state == .sealed else { continue }
            note.state = .shared
            note.partnerKnownVersion = sentVersion
            note.baseVersion = sentVersion
            try notes.save(note, commit: false)
        }
        // Saves the shared context, notes included.
        try log.record(prepared.exchangeID, direction: .sent, itemCount: prepared.versions.count, at: now)
    }

    /// Board F2: the share sheet handed the file over. Nobody can see whether it arrived, so the
    /// notes stay Sealed, marked "Sent · not confirmed" with this exchange and the version that
    /// left, until the partner's phone confirms it (`confirm`). They leave the outbox. Found on two
    /// phones: an interrupted AirDrop still reports done, so this is all a handover proves.
    func markHandedOver(_ prepared: Prepared, now: Date = .now) throws {
        defer { discard(prepared) }
        for (id, sentVersion) in prepared.versions {
            guard var note = try notes.note(id: id), note.state == .sealed else { continue }
            note.pendingExchangeID = prepared.exchangeID
            note.pendingVersion = sentVersion
            try notes.save(note, commit: false)
        }
        try log.record(prepared.exchangeID, direction: .sent, itemCount: prepared.versions.count, at: now, unconfirmed: true)
    }

    /// The partner's phone reports which exchanges it imported (during an exchange nearby). Every
    /// note waiting on one of them becomes Shared at the version that left, which the partner now
    /// holds: also the common ancestor for their fast forward check (spec 16, 18). An edit made
    /// since stays as "Changed since sent". One save. Returns how many notes were confirmed.
    @discardableResult
    func confirm(importedExchangeIDs: Set<String>) throws -> Int {
        var confirmed = 0
        var exchanges = Set<String>()
        for var note in try notes.notes(in: nil) {
            guard let pending = note.pendingExchangeID, importedExchangeIDs.contains(pending) else { continue }
            note.state = .shared
            note.partnerKnownVersion = note.pendingVersion
            note.baseVersion = note.pendingVersion
            note.pendingExchangeID = nil
            note.pendingVersion = 0
            try notes.save(note, commit: false)
            exchanges.insert(pending)
            confirmed += 1
        }
        guard confirmed > 0 else { return 0 }
        for id in exchanges { try log.stageConfirmed(id) }
        try notes.commit()
        return confirmed
    }

    /// Cancelled, or done: the file does not linger.
    func discard(_ prepared: Prepared) {
        try? FileManager.default.removeItem(at: prepared.file)
    }
}
