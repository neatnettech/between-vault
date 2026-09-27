import Foundation
import SwiftData

@Model
final class CategoryRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var sort: Int

    init(id: UUID = UUID(), name: String, sort: Int) {
        self.id = id
        self.name = name
        self.sort = sort
    }
}

@Model
final class NoteRecord {
    @Attribute(.unique) var id: UUID
    var categoryID: UUID?
    var stateRaw: String
    var version: Int
    var baseVersion: Int
    /// AES-GCM(nonce + ciphertext + tag) under the vault key. Title and body live inside.
    var ciphertext: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        categoryID: UUID?,
        stateRaw: String,
        version: Int,
        baseVersion: Int,
        ciphertext: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryID = categoryID
        self.stateRaw = stateRaw
        self.version = version
        self.baseVersion = baseVersion
        self.ciphertext = ciphertext
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PartnerRecord {
    @Attribute(.unique) var id: UUID
    var deviceID: String
    var fingerprint: String
    var pairedAt: Date

    init(id: UUID = UUID(), deviceID: String, fingerprint: String, pairedAt: Date = Date()) {
        self.id = id
        self.deviceID = deviceID
        self.fingerprint = fingerprint
        self.pairedAt = pairedAt
    }
}

@Model
final class ExchangeLogRecord {
    @Attribute(.unique) var exchangeID: String
    var directionRaw: String
    var importedAt: Date

    init(exchangeID: String, directionRaw: String, importedAt: Date = Date()) {
        self.exchangeID = exchangeID
        self.directionRaw = directionRaw
        self.importedAt = importedAt
    }
}
