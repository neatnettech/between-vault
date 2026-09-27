import Foundation
import Testing

@testable import BetweenVault

struct PackageTests {
    private let pairKey = CryptoEngine.randomKey()
    private let sender = "device-a"
    private let recipient = "device-b"

    private func sealedPackage() throws -> SealedPackage {
        try PackageSerializer.seal(
            items: [
                ExchangeItem(
                    objectID: UUID(),
                    categoryID: nil,
                    baseVersion: 0,
                    version: 1,
                    updatedAt: Date(),
                    title: "Boiler service",
                    body: "Engineer's number"
                )
            ],
            pairKey: pairKey,
            sender: sender,
            recipient: recipient,
            exchangeID: "exchange-1"
        )
    }

    @Test func sealAndOpenRoundTrip() throws {
        let sealed = try sealedPackage()
        let opened = try PackageSerializer.open(sealed, pairKey: pairKey)

        #expect(opened.exchangeID == "exchange-1")
        #expect(opened.items.count == 1)
        #expect(opened.items[0].title == "Boiler service")
    }

    @Test func sealAndOpenIsStableAcrossManyRoundTrips() throws {
        for _ in 0..<25 {
            let sealed = try PackageSerializer.seal(
                items: [
                    ExchangeItem(
                        objectID: UUID(),
                        categoryID: nil,
                        baseVersion: 0,
                        version: 1,
                        updatedAt: Date(),
                        title: "Boiler service",
                        body: "Engineer's number"
                    )
                ],
                pairKey: pairKey,
                sender: sender,
                recipient: recipient
            )
            let opened = try PackageSerializer.open(sealed, pairKey: pairKey)
            #expect(opened.items.count == 1)
        }
    }

    @Test func tamperedPackageFailsToOpen() throws {
        let sealed = try sealedPackage()
        var altered = sealed
        altered = SealedPackage(
            protocolVersion: altered.protocolVersion,
            senderDeviceID: altered.senderDeviceID,
            recipientDeviceID: altered.recipientDeviceID,
            exchangeID: altered.exchangeID,
            createdAt: altered.createdAt,
            ciphertext: altered.ciphertext + Data([0x00])
        )
        #expect(throws: PackageSerializer.SerializationError.tampered) {
            _ = try PackageSerializer.open(altered, pairKey: pairKey)
        }
    }

    @Test func wrongRecipientIsRejected() throws {
        let sealed = try sealedPackage()
        #expect(throws: ImportError.wrongRecipient) {
            try PackageValidator.validate(sealed, localDeviceID: "someone-else", importedExchangeIDs: [])
        }
    }

    @Test func duplicateImportIsRejected() throws {
        let sealed = try sealedPackage()
        #expect(throws: ImportError.duplicate) {
            try PackageValidator.validate(sealed, localDeviceID: recipient, importedExchangeIDs: ["exchange-1"])
        }
    }

    @Test func unsupportedVersionIsRejected() throws {
        let sealed = try sealedPackage()
        let future = SealedPackage(
            protocolVersion: SealedPackage.currentVersion + 1,
            senderDeviceID: sealed.senderDeviceID,
            recipientDeviceID: sealed.recipientDeviceID,
            exchangeID: sealed.exchangeID,
            createdAt: sealed.createdAt,
            ciphertext: sealed.ciphertext
        )
        #expect(throws: ImportError.unsupportedVersion(actual: SealedPackage.currentVersion + 1, supported: SealedPackage.currentVersion)) {
            try PackageValidator.validate(future, localDeviceID: recipient, importedExchangeIDs: [])
        }
    }
}
