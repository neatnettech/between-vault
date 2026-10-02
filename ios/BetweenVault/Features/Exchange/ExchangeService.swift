import Foundation

/// Rows 4.4 to 4.6: from sealed notes to one .nvlt file, and what sending changes.
///
/// "Shared means sent, not delivered." The phones never talk, so the app records what its owner
/// did and never claims to know what happened on the other phone. Notes become Shared when the
/// share sheet reports the handoff done (AirDrop sent, message sent, file saved); a cancelled
/// sheet changes nothing. Whether it arrived is for the two people to say to each other. If it did
/// not, Send again seals it once more, and importing a version twice changes nothing.
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

    /// Board 7: sealed notes, newest first.
    func outbox() throws -> [OutboxItem] {
        let names = Dictionary(uniqueKeysWithValues: try categories.categories().map { ($0.id, $0.name) })
        return try notes.notes(in: nil)
            .filter { $0.state == .sealed }
            .map { OutboxItem(note: $0, categoryName: $0.categoryID.flatMap { names[$0] }) }
    }

    /// Board 8, Encrypt & Share: every sealed note in one package, written to a temporary file for
    /// the share sheet. Nothing about the notes changes yet.
    func prepare(now: Date = .now) throws -> Prepared {
        guard let partner = try partners.partner(), let key = try pairKey() else { throw ExchangeError.notPaired }
        let sealed = try notes.notes(in: nil).filter { $0.state == .sealed }
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

    /// The share sheet reported the handoff done. Each note that is still sealed becomes Shared at
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

    /// Cancelled, or done: the file does not linger.
    func discard(_ prepared: Prepared) {
        try? FileManager.default.removeItem(at: prepared.file)
    }
}
