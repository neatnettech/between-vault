import CryptoKit
import Foundation

/// Row 3.1. Pairing as amended from spec 13: the QRs carry one time X25519 public keys, never a
/// secret, so a photo of any of them is useless. Each phone derives the same pair key, and the six
/// digit code is a real check that no one sits in the middle. Each phone saves only when its own
/// person confirms the code, so neither waits for a signal the other cannot send offline.
///
/// Three scans, commit first, as in Bluetooth numeric comparison: A shows a hash of its key (1);
/// B scans it and shows its key (2); A scans that and reveals its key (3); B scans the reveal and
/// checks it against the hash. A's key is hidden until B's is fixed, and anyone in the middle has
/// to fix theirs before seeing A's, so no one can try keys until both codes match: the odds of a
/// matching code stay one in a million.
enum Pairing {
    enum PairingError: Error, Equatable {
        case notAPairingCode
        case unsupportedVersion
        /// A pairing QR, but not the one this step expects, e.g. the first QR scanned twice.
        case wrongStep
        case ownCode
        /// The reveal does not match the hash shown first: a different phone, or someone between.
        case commitmentMismatch
        /// A already showed QR 3 in this attempt; starting again needs a new attempt.
        case alreadyRevealed
        case alreadyPaired
    }

    /// The pairing payload's own version, apart from the exchange package's (spec 33).
    static let version: UInt8 = 1
    private static let prefix = "betweenvault:pair:"

    /// A phone's half: a one time public key and the device ID. Nothing secret.
    struct Offer: Equatable, Sendable {
        let publicKey: Data
        let deviceID: UUID
    }

    /// What one QR carries. `betweenvault:pair:` then base64url of version, step, payload.
    enum Message: Equatable, Sendable {
        /// Step 1, A: SHA256 over A's offer and a nonce.
        case commitment(Data)
        /// Step 2, B: B's offer.
        case offer(Offer)
        /// Step 3, A: A's offer and the nonce that opens the commitment.
        case reveal(Offer, nonce: Data)

        var qrString: String {
            var bytes = Data([Pairing.version])
            switch self {
            case let .commitment(hash):
                bytes.append(1)
                bytes.append(hash)
            case let .offer(offer):
                bytes.append(2)
                bytes.append(offer.bytes)
            case let .reveal(offer, nonce):
                bytes.append(3)
                bytes.append(offer.bytes)
                bytes.append(nonce)
            }
            return Pairing.prefix + bytes.base64URLEncoded
        }

        /// Anything the camera reads comes through here, so everything is checked.
        init(qrString: String) throws {
            guard qrString.hasPrefix(Pairing.prefix),
                  let bytes = Data(base64URLEncoded: String(qrString.dropFirst(Pairing.prefix.count))),
                  bytes.count >= 2
            else { throw PairingError.notAPairingCode }
            guard bytes[bytes.startIndex] == Pairing.version else { throw PairingError.unsupportedVersion }
            let body = Data(bytes.dropFirst(2))
            switch (bytes[bytes.startIndex + 1], body.count) {
            case (1, 32): self = .commitment(body)
            case (2, 48): self = try .offer(Offer(body))
            case (3, 64): self = try .reveal(Offer(body.prefix(48)), nonce: Data(body.suffix(16)))
            default: throw PairingError.notAPairingCode
            }
        }
    }

    /// What both phones hold after the scans, before anyone confirms.
    struct Agreement: Equatable, Sendable {
        let pairKey: Data
        let partnerDeviceID: String
        /// Spec 13: the six digits both people compare.
        let code: String
        /// Board 14: 32 hex characters, the same on both phones.
        let fingerprint: String
    }

    /// A, who starts. The private key and the nonce live only here and die with the attempt, so an
    /// abandoned or mismatched pairing leaves nothing behind. Single use, and a class so no copy
    /// escapes that: once A's key is revealed, a second QR 2 could be chosen against it to force
    /// A's code, so the commitment holds only if A reveals once. A retry is a new Initiator.
    final class Initiator {
        private let privateKey = Curve25519.KeyAgreement.PrivateKey()
        private let nonce = Data(CryptoEngine.randomKey().prefix(16))
        private let own: Offer
        private var revealed = false

        init(deviceID: String) {
            own = Offer(publicKey: privateKey.publicKey.rawRepresentation, deviceID: Pairing.uuid(deviceID))
        }

        /// QR 1.
        var commitment: Message { .commitment(Pairing.commit(own, nonce: nonce)) }

        /// After scanning QR 2: the agreement to show, and QR 3 for B.
        func agree(with scanned: Message) throws -> (agreement: Agreement, reveal: Message) {
            guard !revealed else { throw PairingError.alreadyRevealed }
            guard case let .offer(theirs) = scanned else { throw PairingError.wrongStep }
            // A bad scan above reveals nothing, so it does not use up the attempt.
            let agreement = try Pairing.agree(privateKey, own: own, theirs: theirs)
            revealed = true
            return (agreement, .reveal(own, nonce: nonce))
        }
    }

    /// B, who scans first. Holds A's hash until A reveals.
    struct Joiner {
        private let privateKey = Curve25519.KeyAgreement.PrivateKey()
        private let own: Offer
        private let commitment: Data

        /// From QR 1.
        init(deviceID: String, scanned: Message) throws {
            guard case let .commitment(hash) = scanned else { throw PairingError.wrongStep }
            commitment = hash
            own = Offer(publicKey: privateKey.publicKey.rawRepresentation, deviceID: Pairing.uuid(deviceID))
        }

        /// QR 2.
        var offer: Message { .offer(own) }

        /// After scanning QR 3.
        func agree(with scanned: Message) throws -> Agreement {
            guard case let .reveal(theirs, nonce) = scanned else { throw PairingError.wrongStep }
            guard Pairing.commit(theirs, nonce: nonce) == commitment else { throw PairingError.commitmentMismatch }
            return try Pairing.agree(privateKey, own: own, theirs: theirs)
        }
    }

    /// `deviceID` is Identity's, always a UUID string; anything else is a bug, not input.
    private static func uuid(_ deviceID: String) -> UUID {
        guard let id = UUID(uuidString: deviceID) else { preconditionFailure("device ID is not a UUID") }
        return id
    }

    private static func commit(_ offer: Offer, nonce: Data) -> Data {
        var hash = SHA256()
        hash.update(data: Data("betweenvault.commit.v1".utf8))
        hash.update(data: offer.bytes)
        hash.update(data: nonce)
        return Data(hash.finalize())
    }

    private static func agree(_ privateKey: Curve25519.KeyAgreement.PrivateKey, own: Offer, theirs: Offer) throws -> Agreement {
        guard theirs.deviceID != own.deviceID, theirs.publicKey != own.publicKey else { throw PairingError.ownCode }
        let shared = try privateKey.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs.publicKey)
        )
        // Order independent, so both phones derive the same key; both public keys and both IDs are
        // bound in, so swapping either changes the key and with it the code.
        let keys = [own.publicKey, theirs.publicKey].sorted { $0.lexicographicallyPrecedes($1) }
        let ids = [own.deviceID, theirs.deviceID].map { $0.uuidString.lowercased() }.sorted()
        let pairKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: keys[0] + keys[1],
            sharedInfo: Data("betweenvault.pairKey.v1|\(ids[0])|\(ids[1])".utf8),
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
        let fingerprint = CryptoEngine.derive(pairKey: pairKey, info: "betweenvault.fingerprint.v1", outputByteCount: 16)
        return Agreement(
            pairKey: pairKey,
            partnerDeviceID: theirs.deviceID.uuidString.lowercased(),
            code: CryptoEngine.pairingCode(pairKey: pairKey, deviceIDs: ids),
            fingerprint: fingerprint.map { String(format: "%02X", $0) }.joined()
        )
    }

    /// Keychain account for the pair key. Frozen from the first TestFlight build onward.
    static let pairKeyAccount = "betweenvault.pairKey"

    /// "Codes match": the only place pairing writes anything. Key first; if the partner record
    /// then fails, the key goes again, so a failure leaves the phone unpaired, not half paired.
    @MainActor
    static func commit(
        _ agreement: Agreement,
        partners: PartnerRepository,
        saveKey: (Data) throws -> Void = { try KeyManager.delete(pairKeyAccount); try KeyManager.save($0, account: pairKeyAccount) },
        deleteKey: () throws -> Void = { try KeyManager.delete(pairKeyAccount) },
        now: Date = .now
    ) throws {
        guard try partners.partner() == nil else { throw PairingError.alreadyPaired }
        try saveKey(agreement.pairKey)
        do {
            try partners.save(Partner(id: UUID(), deviceID: agreement.partnerDeviceID, fingerprint: agreement.fingerprint, pairedAt: now))
        } catch {
            try? deleteKey()
            throw error
        }
    }

    // MARK: Recovery blob (spec 20)

    /// The owner's vault key, encrypted for the partner to hold. Under a key of its own derived
    /// from the pair key, bound to the owner's device ID, so it opens only as that owner's blob.
    static func wrapRecovery(vaultKey: Data, pairKey: Data, ownerDeviceID: String) throws -> Data {
        try CryptoEngine.encrypt(vaultKey, key: recoveryKey(pairKey), aad: Data("recovery|\(ownerDeviceID)".utf8))
    }

    static func unwrapRecovery(_ blob: Data, pairKey: Data, ownerDeviceID: String) throws -> Data {
        try CryptoEngine.decrypt(blob, key: recoveryKey(pairKey), aad: Data("recovery|\(ownerDeviceID)".utf8))
    }

    private static func recoveryKey(_ pairKey: Data) -> Data {
        CryptoEngine.derive(pairKey: pairKey, info: "betweenvault.recovery.v1")
    }
}

private extension Pairing.Offer {
    /// Public key (32) then device ID (16).
    var bytes: Data {
        publicKey + withUnsafeBytes(of: deviceID.uuid) { Data($0) }
    }

    init(_ bytes: Data) throws {
        let bytes = Data(bytes)
        let key = bytes.prefix(32)
        guard bytes.count == 48, (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: key)) != nil else {
            throw Pairing.PairingError.notAPairingCode
        }
        let id = [UInt8](bytes.suffix(16))
        self.init(
            publicKey: Data(key),
            deviceID: UUID(uuid: (id[0], id[1], id[2], id[3], id[4], id[5], id[6], id[7],
                                  id[8], id[9], id[10], id[11], id[12], id[13], id[14], id[15]))
        )
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

// MARK: - Recovery file (row 3.7, spec 20)

extension Pairing {
    /// Keychain account holding the partner's recovery blob on this phone. Frozen like the others.
    static let partnerRecoveryAccount = "betweenvault.partnerRecovery"

    /// What "Send recovery file to partner" hands over: the owner's blob, addressed to the holder.
    /// The blob is already encrypted under a key only the two phones derive, so the file can go by
    /// AirDrop, Messages or Files like an exchange package.
    struct RecoveryFile: Codable, Equatable {
        static let format = "betweenvault.recovery"
        static let fileExtension = "nvrec"

        let format: String
        let version: Int
        let ownerDeviceID: String
        let holderDeviceID: String
        let blob: Data

        enum Problem: Error, Equatable {
            case unreadable
            case notForThisPairing
        }

        static func make(vaultKey: Data, pairKey: Data, owner: String, holder: String) throws -> Data {
            let file = RecoveryFile(
                format: format,
                version: 1,
                ownerDeviceID: owner,
                holderDeviceID: holder,
                blob: try wrapRecovery(vaultKey: vaultKey, pairKey: pairKey, ownerDeviceID: owner)
            )
            return try JSONEncoder().encode(file)
        }

        /// The holder's side: only a file from the paired partner, made for this phone, whose blob
        /// opens under the pair key, is kept. Returns the blob to store, never the unwrapped key.
        static func accept(_ data: Data, pairKey: Data, me: String, partner: String) throws -> Data {
            guard let file = try? JSONDecoder().decode(RecoveryFile.self, from: data),
                  file.format == format, file.version == 1
            else { throw Problem.unreadable }
            guard file.ownerDeviceID == partner, file.holderDeviceID == me,
                  (try? unwrapRecovery(file.blob, pairKey: pairKey, ownerDeviceID: partner)) != nil
            else { throw Problem.notForThisPairing }
            return file.blob
        }
    }
}
