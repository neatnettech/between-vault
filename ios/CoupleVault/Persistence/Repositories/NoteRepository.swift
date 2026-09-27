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

    func notes(in categoryID: UUID?) throws -> [Note] {
        let key = try vaultKey()
        let records = try context.fetch(FetchDescriptor<NoteRecord>())
        let filtered = categoryID == nil ? records : records.filter { $0.categoryID == categoryID }
        return filtered.compactMap { record in
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
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        }
    }

    func save(_ note: Note) throws {
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
            existing.ciphertext = ciphertext
            existing.updatedAt = note.updatedAt
        } else {
            context.insert(
                NoteRecord(
                    id: note.id,
                    categoryID: note.categoryID,
                    stateRaw: note.state.rawValue,
                    version: note.version,
                    baseVersion: note.baseVersion,
                    ciphertext: ciphertext,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt
                )
            )
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let matches = try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id }))
        for record in matches {
            context.delete(record)
        }
        try context.save()
    }
}
