import Foundation

enum PackageSerializer {
    enum SerializationError: Error {
        case tampered
        case malformedItems
    }

    /// Encrypts items under the pair key, binding the header fields as additional
    /// authenticated data. The output is the exact .nvlt file content.
    ///
    /// The AAD encoding is canonical: JSON with sorted keys. JSONEncoder alone does
    /// not guarantee stable key ordering, and an unstable AAD breaks verification.
    static func seal(
        items: [ExchangeItem],
        pairKey: Data,
        sender: String,
        recipient: String,
        exchangeID: String = UUID().uuidString,
        createdAt: Date = Date()
    ) throws -> SealedPackage {
        let aad = try canonicalJSON(
            HeaderAD(protocolVersion: SealedPackage.currentVersion, senderDeviceID: sender, recipientDeviceID: recipient, exchangeID: exchangeID, createdAt: createdAt)
        )
        let itemsData = try canonicalJSON(items)
        let ciphertext = try CryptoEngine.encrypt(itemsData, key: pairKey, aad: aad)
        return SealedPackage(
            protocolVersion: SealedPackage.currentVersion,
            senderDeviceID: sender,
            recipientDeviceID: recipient,
            exchangeID: exchangeID,
            createdAt: createdAt,
            ciphertext: ciphertext
        )
    }

    /// Authenticates and decrypts. Throws `.tampered` when the AEAD check fails,
    /// `.malformedItems` when the payload is not valid JSON items.
    static func open(_ package: SealedPackage, pairKey: Data) throws -> OpenedPackage {
        let aad = try canonicalJSON(
            HeaderAD(protocolVersion: package.protocolVersion, senderDeviceID: package.senderDeviceID, recipientDeviceID: package.recipientDeviceID, exchangeID: package.exchangeID, createdAt: package.createdAt)
        )
        let plaintext: Data
        do {
            plaintext = try CryptoEngine.decrypt(package.ciphertext, key: pairKey, aad: aad)
        } catch {
            throw SerializationError.tampered
        }
        guard let items = try? JSONDecoder().decode([ExchangeItem].self, from: plaintext) else {
            throw SerializationError.malformedItems
        }
        return OpenedPackage(
            protocolVersion: package.protocolVersion,
            senderDeviceID: package.senderDeviceID,
            recipientDeviceID: package.recipientDeviceID,
            exchangeID: package.exchangeID,
            createdAt: package.createdAt,
            items: items
        )
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

extension SealedPackage {
    static let currentVersion = 1
}

private struct HeaderAD: Codable {
    let protocolVersion: Int
    let senderDeviceID: String
    let recipientDeviceID: String
    let exchangeID: String
    let createdAt: Date
}
