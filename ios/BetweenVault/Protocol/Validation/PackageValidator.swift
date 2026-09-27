import Foundation

enum ImportError: Error, Equatable {
    case malformed
    case unsupportedVersion(actual: Int, supported: Int)
    case wrongRecipient
    case duplicate
    case empty
}

enum PackageValidator {
    /// Structural checks that run before decryption. Content authenticity is the
    /// serializer's job (AEAD), not this layer's.
    static func validate(
        _ package: SealedPackage,
        localDeviceID: String,
        importedExchangeIDs: Set<String>
    ) throws {
        guard !package.exchangeID.isEmpty,
              !package.senderDeviceID.isEmpty,
              !package.recipientDeviceID.isEmpty else {
            throw ImportError.malformed
        }
        guard package.protocolVersion <= SealedPackage.currentVersion,
              package.protocolVersion >= 1 else {
            throw ImportError.unsupportedVersion(actual: package.protocolVersion, supported: SealedPackage.currentVersion)
        }
        guard package.recipientDeviceID == localDeviceID else {
            throw ImportError.wrongRecipient
        }
        guard !importedExchangeIDs.contains(package.exchangeID) else {
            throw ImportError.duplicate
        }
    }

    static func validateItems(_ items: [ExchangeItem]) throws {
        guard !items.isEmpty else { throw ImportError.empty }
    }
}
