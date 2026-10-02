import Foundation
import SwiftData

/// Cycle 5: from a .nvlt file to notes, all or nothing.
///
/// `inspect` checks everything and decides what each item would do, writing nothing; the owner
/// reviews (board 9, U4) and resolves conflicts (board 10); `accept` applies it in one save.
@MainActor
final class ImportService {
    /// Boards 9a to 9d, and the cases they do not draw.
    enum ImportFailure: Error, Equatable {
        /// 9a: not a package, cut short, or altered.
        case damaged
        /// 9b: made for another iPhone, or by someone other than the paired partner.
        case wrongDevice
        /// 9c.
        case newerVersion
        /// 9d, with when it was imported.
        case alreadyImported(Date?)
        case notPaired
        case empty
    }

    /// What one item would do to this vault.
    enum Change: Equatable {
        case new
        /// The partner changed it and this phone did not since the last exchange: fast forward.
        case update(local: Note)
        /// Changed on both phones (board 10).
        case conflict(local: Note)
        /// Nothing to do: the same content, or a version this phone already moved past.
        case unchanged(local: Note)
    }

    struct Item: Identifiable, Equatable {
        let incoming: ExchangeItem
        let change: Change
        var id: UUID { incoming.objectID }
    }

    struct Incoming: Equatable {
        let exchangeID: String
        let createdAt: Date
        let items: [Item]

        var conflicts: [Item] { items.filter { if case .conflict = $0.change { true } else { false } } }
        /// Board U4 / toast: what will actually change.
        var changingCount: Int { items.filter { if case .unchanged = $0.change { false } else { true } }.count }
    }

    /// Board 10's three answers.
    enum Resolution: Equatable {
        case keepMine
        case keepPartners
        case keepBoth
    }

    private let context: ModelContext
    private let notes: NoteRepository
    private let categories: CategoryRepository
    private let partners: PartnerRepository
    private let log: ExchangeLogRepository
    private let pairKey: () throws -> Data?
    private let deviceID: () -> String

    init(
        context: ModelContext,
        notes: NoteRepository,
        categories: CategoryRepository,
        partners: PartnerRepository,
        log: ExchangeLogRepository,
        pairKey: @escaping () throws -> Data?,
        deviceID: @escaping () -> String
    ) {
        self.context = context
        self.notes = notes
        self.categories = categories
        self.partners = partners
        self.log = log
        self.pairKey = pairKey
        self.deviceID = deviceID
    }

    // MARK: Inspect (rows 5.3, 5.5)

    /// Spec 17.2, in order: format and version, recipient, sender, authenticity, duplicate, then
    /// each item against this vault. Writes nothing.
    func inspect(_ fileData: Data) throws -> Incoming {
        let package: SealedPackage
        do { package = try PackageSerializer.package(fromFile: fileData) } catch { throw ImportFailure.damaged }
        guard let partner = try partners.partner(), let key = try pairKey() else { throw ImportFailure.notPaired }
        do {
            try PackageValidator.validate(package, localDeviceID: deviceID(), importedExchangeIDs: [])
        } catch ImportError.unsupportedVersion {
            throw ImportFailure.newerVersion
        } catch ImportError.wrongRecipient {
            throw ImportFailure.wrongDevice
        } catch {
            throw ImportFailure.damaged
        }
        // The sender is bound into the AAD, but a package from someone else under the same key
        // cannot exist; checked anyway, so 9b is said before decryption is even tried.
        guard package.senderDeviceID == partner.deviceID else { throw ImportFailure.wrongDevice }
        let opened: OpenedPackage
        do { opened = try PackageSerializer.open(package, pairKey: key) } catch { throw ImportFailure.damaged }
        if let when = try log.receivedDate(opened.exchangeID) { throw ImportFailure.alreadyImported(when) }
        guard !opened.items.isEmpty else { throw ImportFailure.empty }

        let names = Dictionary(uniqueKeysWithValues: try categories.categories().map { ($0.id, $0) })
        let items = try opened.items.map { incoming in
            Item(incoming: incoming, change: try classify(incoming, names: names))
        }
        return Incoming(exchangeID: opened.exchangeID, createdAt: opened.createdAt, items: items)
    }

    /// Spec 18, with one amendment: equal version numbers are not proof of equal content, since
    /// both phones count from the same ancestor. Two edits of v3 are both v4; taking that as
    /// "nothing to do" would silently drop the partner's. So content decides "unchanged".
    private func classify(_ incoming: ExchangeItem, names: [UUID: Category]) throws -> Change {
        guard let local = try notes.note(id: incoming.objectID) else { return .new }
        let localCategory = local.categoryID.flatMap { names[$0] }
        let sameContent = local.title == incoming.title && local.body == incoming.body
            && Self.sameCategory(localCategory, incoming.category)
        if sameContent { return .unchanged(local: local) }
        // A resend of something this phone already moved past.
        if incoming.version <= local.baseVersion { return .unchanged(local: local) }
        // The partner built on exactly what this phone has: fast forward. Anything else means both
        // sides moved, or the partner built on an older version than this phone sent: a conflict,
        // never a silent overwrite.
        return incoming.baseVersion == local.version ? .update(local: local) : .conflict(local: local)
    }

    private static func sameCategory(_ local: Category?, _ incoming: ExchangeCategory?) -> Bool {
        switch (local, incoming) {
        case (nil, nil): true
        case let (local?, incoming?):
            if let key = incoming.builtInKey { local.builtInKey?.rawValue == key } else { local.name == incoming.name }
        default: false
        }
    }

    // MARK: Accept (rows 5.4, 5.6)

    /// All items land or none do (row 5.4): every write is staged and one save commits them with
    /// the history entry. Conflicts need a resolution each; nothing is silently discarded.
    func accept(_ incoming: Incoming, resolutions: [UUID: Resolution] = [:], now: Date = .now) throws {
        var conflictsKeptBoth = 0
        var categoryCache: [Category] = try categories.categories()
        for item in incoming.items {
            let categoryID = try category(for: item.incoming.category, cache: &categoryCache)
            switch item.change {
            case .unchanged:
                continue
            case .new:
                try notes.save(partnersNote(item.incoming, categoryID: categoryID, origin: .partner), commit: false)
            case let .update(local):
                var note = partnersNote(item.incoming, categoryID: categoryID, origin: local.origin)
                note.state = .shared
                try notes.save(note, commit: false)
            case let .conflict(local):
                switch resolutions[item.id] {
                case .keepPartners:
                    try notes.save(partnersNote(item.incoming, categoryID: categoryID, origin: local.origin), commit: false)
                case .keepMine:
                    try notes.save(keptMine(local, over: item.incoming, now: now), commit: false)
                case .keepBoth:
                    try notes.save(keptMine(local, over: item.incoming, now: now), commit: false)
                    var copy = partnersNote(item.incoming, categoryID: categoryID, origin: .partner)
                    copy = Note(
                        id: UUID(), title: Copy.partnersCopy(item.incoming.title), body: copy.body, state: .private,
                        categoryID: copy.categoryID, version: 1, baseVersion: 0, partnerKnownVersion: 0,
                        createdAt: now, updatedAt: now, origin: .partner
                    )
                    try notes.save(copy, commit: false)
                    conflictsKeptBoth += 1
                case nil:
                    context.rollback()
                    throw ImportFailure.damaged
                }
            }
        }
        // Saves the shared context, every note above included, or rolls all of it back.
        try log.record(
            incoming.exchangeID, direction: .received, itemCount: incoming.items.count, at: now,
            conflictsKeptBoth: conflictsKeptBoth
        )
    }

    /// Board 18 "Declined 1 file": the file is not imported, and opening it again asks again.
    func decline(_ incoming: Incoming, now: Date = .now) throws {
        try log.record("declined-\(incoming.exchangeID)", direction: .declined, itemCount: incoming.items.count, at: now)
    }

    /// The partner's version as this phone's: Shared, and both version marks at the version that
    /// arrived, since the partner holds exactly it.
    private func partnersNote(_ item: ExchangeItem, categoryID: UUID?, origin: NoteOrigin) -> Note {
        Note(
            id: item.objectID, title: item.title, body: item.body, state: .shared, categoryID: categoryID,
            version: item.version, baseVersion: item.version, partnerKnownVersion: item.version,
            createdAt: item.updatedAt, updatedAt: item.updatedAt, origin: origin
        )
    }

    /// Keep mine: this phone's text stays and now builds on the partner's version, ahead of it, so
    /// "Changed since sent" shows and the next send fast forwards on their phone.
    private func keptMine(_ local: Note, over incoming: ExchangeItem, now: Date) -> Note {
        var note = local
        note.version = max(local.version, incoming.version) + 1
        note.baseVersion = incoming.version
        note.partnerKnownVersion = incoming.version
        if note.state == .private { note.state = .shared }
        note.updatedAt = now
        return note
    }

    /// Emergency and Other by key, others by name, else a new category with the sender's name and
    /// icon. Created categories are staged in the same save as the notes.
    private func category(for incoming: ExchangeCategory?, cache: inout [Category]) throws -> UUID? {
        guard let incoming else { return nil }
        if let key = incoming.builtInKey, let match = cache.first(where: { $0.builtInKey?.rawValue == key }) {
            return match.id
        }
        if let match = cache.first(where: { $0.name.compare(incoming.name, options: .caseInsensitive) == .orderedSame }) {
            return match.id
        }
        let created = try categories.add(name: incoming.name, symbol: incoming.symbol, commit: false)
        cache.append(created)
        return created.id
    }
}
