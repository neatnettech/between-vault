import Foundation
import SwiftData

@Model
final class CategoryRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var sort: Int
    /// SF Symbol for the tile. Stored so a rename keeps the icon.
    /// Defaulted, so adding it stays a lightweight migration.
    var symbol: String = CategoryRecord.defaultSymbol
    /// Raw `BuiltInCategory` for the two categories that cannot be deleted, `nil` otherwise.
    /// Built in categories can be renamed and reordered, never deleted.
    var builtInKey: String?

    static let defaultSymbol = "folder"

    init(
        id: UUID = UUID(),
        name: String,
        sort: Int,
        symbol: String = CategoryRecord.defaultSymbol,
        builtInKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sort = sort
        self.symbol = symbol
        self.builtInKey = builtInKey
    }
}

@Model
final class NoteRecord {
    @Attribute(.unique) var id: UUID
    var categoryID: UUID?
    var stateRaw: String
    var version: Int
    /// The common ancestor the partner's copy was based on at the last exchange (spec section 16).
    var baseVersion: Int
    /// The version last sent to the partner. Defaulted, so adding it stays a lightweight migration.
    var partnerKnownVersion: Int = 0
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
        partnerKnownVersion: Int = 0,
        ciphertext: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryID = categoryID
        self.stateRaw = stateRaw
        self.version = version
        self.baseVersion = baseVersion
        self.partnerKnownVersion = partnerKnownVersion
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
