import Foundation
import SwiftData

@MainActor
final class NoteRepository {
    private struct Payload: Codable {
        let title: String
        let body: String
    }

    private let context: ModelContext
    private let vaultKey: () throws -> Data

    init(context: ModelContext, vaultKey: @escaping () throws -> Data) {
        self.context = context
        self.vaultKey = vaultKey
    }

    /// Newest first, as board 4 lists them. `updatedAt` is a plain column, so the store sorts.
    func notes(in categoryID: UUID?) throws -> [Note] {
        let key = try vaultKey()
        var descriptor = FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        if let categoryID {
            descriptor.predicate = #Predicate { $0.categoryID == categoryID }
        }
        let records = try context.fetch(descriptor)
        return records.compactMap { map($0, key: key) }
    }

    func note(id: UUID) throws -> Note? {
        let key = try vaultKey()
        let records = try context.fetch(
            FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        )
        return records.first.flatMap { map($0, key: key) }
    }

    private func map(_ record: NoteRecord, key: Data) -> Note? {
        guard let plaintext = try? CryptoEngine.decrypt(record.ciphertext, key: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: plaintext) else {
            return nil
        }
        return Note(
            id: record.id,
            title: payload.title,
            body: payload.body,
            state: NoteState(rawValue: record.stateRaw) ?? .private,
            categoryID: record.categoryID,
            version: record.version,
            baseVersion: record.baseVersion,
            partnerKnownVersion: record.partnerKnownVersion,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            origin: NoteOrigin(rawValue: record.originRaw) ?? .local
        )
    }

    /// Counts per category, optionally filtered by state. Filters in the store and fetches only the
    /// two columns it needs, so the ciphertext blobs never leave SQLite and nothing is decrypted.
    func countsByCategory(state: NoteState? = nil) throws -> [UUID: Int] {
        var descriptor = FetchDescriptor<NoteRecord>()
        if let state {
            let raw = state.rawValue
            descriptor.predicate = #Predicate { $0.stateRaw == raw }
        }
        descriptor.propertiesToFetch = [\.categoryID, \.stateRaw]

        var result: [UUID: Int] = [:]
        for record in try context.fetch(descriptor) {
            guard let categoryID = record.categoryID else { continue }
            result[categoryID, default: 0] += 1
        }
        return result
    }

    /// Every note in the vault, ignoring any state filter. The vault home needs this separately from
    /// `countsByCategory`: a filter matching nothing must not read as an empty vault.
    func noteCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<NoteRecord>())
    }

    /// `commit: false` stages the change in the shared context for a caller that saves several
    /// writes as one, like sending (row 4.6): the next save commits or rolls back all of them.
    func save(_ note: Note, commit: Bool = true) throws {
        let key = try vaultKey()
        let payload = Payload(title: note.title, body: note.body)
        let plaintext = try JSONEncoder().encode(payload)
        let ciphertext = try CryptoEngine.encrypt(plaintext, key: key)

        let id = note.id
        if let existing = try context.fetch(
            FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            existing.categoryID = note.categoryID
            existing.stateRaw = note.state.rawValue
            existing.version = note.version
            existing.baseVersion = note.baseVersion
            existing.partnerKnownVersion = note.partnerKnownVersion
            existing.originRaw = note.origin.rawValue
            existing.ciphertext = ciphertext
            existing.updatedAt = note.updatedAt
        } else {
            let record = NoteRecord(
                    id: note.id,
                    categoryID: note.categoryID,
                    stateRaw: note.state.rawValue,
                    version: note.version,
                    baseVersion: note.baseVersion,
                    partnerKnownVersion: note.partnerKnownVersion,
                    ciphertext: ciphertext,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt
                )
            record.originRaw = note.origin.rawValue
            context.insert(record)
        }
        if commit { try context.saveOrRollback() }
    }

    func delete(id: UUID) throws {
        let matches = try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id }))
        for record in matches {
            context.delete(record)
        }
        try context.saveOrRollback()
    }
}
