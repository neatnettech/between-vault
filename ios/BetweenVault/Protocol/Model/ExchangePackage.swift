import Foundation

/// Wire format of an exchange package (.nvlt file). Everything except the header fields
/// travels inside the ciphertext, so the transport never sees content.
struct SealedPackage: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let senderDeviceID: String
    let recipientDeviceID: String
    let exchangeID: String
    let createdAt: Date
    let ciphertext: Data
}

/// One note's full snapshot (spec 17). The category travels by name and, for the two that always
/// exist, by key: category IDs are random per phone and mean nothing to the partner. A category
/// name is not sensitive, and it is inside the ciphertext anyway.
struct ExchangeItem: Codable, Equatable, Sendable {
    let objectID: UUID
    let category: ExchangeCategory?
    let baseVersion: Int
    let version: Int
    let updatedAt: Date
    let title: String
    let body: String
}

struct ExchangeCategory: Codable, Equatable, Sendable {
    let name: String
    /// `BuiltInCategory` raw value for Emergency and Other, so a renamed one still maps across.
    let builtInKey: String?
    let symbol: String
}

/// A package that has been decrypted and authenticated. `SealedPackage.items` is never
/// written to disk: items exist only after the AEAD check passes.
struct OpenedPackage: Equatable, Sendable {
    let protocolVersion: Int
    let senderDeviceID: String
    let recipientDeviceID: String
    let exchangeID: String
    let createdAt: Date
    let items: [ExchangeItem]
}
