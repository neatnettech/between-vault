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

struct ExchangeItem: Codable, Equatable, Sendable {
    let objectID: UUID
    let categoryID: UUID?
    let baseVersion: Int
    let version: Int
    let updatedAt: Date
    let title: String
    let body: String
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
