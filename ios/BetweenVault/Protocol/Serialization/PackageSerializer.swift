import Foundation

enum PackageSerializer {
    enum SerializationError: Error {
        case tampered
        case malformedItems
        case notAPackage
    }

    /// Format marker inside every .nvlt file, apart from the protocol version.
    static let format = "betweenvault.exchange"
    static let fileExtension = "nvlt"

    /// Each package has a key of its own: HKDF of the pair key, salted with the exchange ID. The
    /// pair key itself never encrypts anything, like the recovery file's, and no two packages
    /// share a key, so AES-GCM's random nonces never meet under the same key.
    static func packageKey(pairKey: Data, exchangeID: String) -> Data {
        CryptoEngine.derive(pairKey: pairKey, info: "betweenvault.exchange.v1", salt: Data(exchangeID.utf8))
    }

    /// Encrypts items under the package key, binding the header fields as additional
    /// authenticated data.
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
        let ciphertext = try CryptoEngine.encrypt(itemsData, key: packageKey(pairKey: pairKey, exchangeID: exchangeID), aad: aad)
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
            plaintext = try CryptoEngine.decrypt(
                package.ciphertext, key: packageKey(pairKey: pairKey, exchangeID: package.exchangeID), aad: aad
            )
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

    /// The .nvlt file bytes: the format marker and the sealed package, as JSON.
    static func fileData(_ package: SealedPackage) throws -> Data {
        try canonicalJSON(PackageFile(format: format, package: package))
    }

    /// Reads a .nvlt file. Anything without the marker is not ours, before any decryption.
    static func package(fromFile data: Data) throws -> SealedPackage {
        guard let file = try? JSONDecoder().decode(PackageFile.self, from: data), file.format == format else {
            throw SerializationError.notAPackage
        }
        return file.package
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

private struct PackageFile: Codable {
    let format: String
    let package: SealedPackage
}

private struct HeaderAD: Codable {
    let protocolVersion: Int
    let senderDeviceID: String
    let recipientDeviceID: String
    let exchangeID: String
    let createdAt: Date
}
