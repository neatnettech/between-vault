import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Rows 3.1 and 3.8: the pairing payload, the key agreement, the code and the recovery blob.
@MainActor
struct PairingTests {
    private let idA = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let idB = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    /// The three scans, each through the QR string, as a camera would read them.
    private func scan(_ message: Pairing.Message) throws -> Pairing.Message {
        try Pairing.Message(qrString: message.qrString)
    }

    private func pair() throws -> (onA: Pairing.Agreement, onB: Pairing.Agreement) {
        let a = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: scan(a.commitment))
        let (onA, reveal) = try a.agree(with: scan(b.offer))
        let onB = try b.agree(with: scan(reveal))
        return (onA, onB)
    }

    /// After the three scans both phones hold the same key, code and fingerprint.
    @Test func bothPhonesAgreeAfterTheThreeScans() throws {
        let (onA, onB) = try pair()
        #expect(onA.pairKey == onB.pairKey)
        #expect(onA.code == onB.code)
        #expect(onA.fingerprint == onB.fingerprint)
        #expect(onA.partnerDeviceID == idB)
        #expect(onB.partnerDeviceID == idA)
        #expect(onA.code.count == 6 && onA.code.allSatisfy(\.isNumber))
        #expect(onA.fingerprint.count == 32 && onA.fingerprint.allSatisfy(\.isHexDigit))
    }

    /// No secret is in any QR: what the camera reads is a hash, public keys and IDs.
    @Test func noQRCarriesTheKey() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        let (onA, reveal) = try a.agree(with: b.offer)
        for qr in [a.commitment, b.offer, reveal].map(\.qrString) {
            let decoded = try #require(Data(base64URLEncoded: String(qr.dropFirst("betweenvault:pair:".count))))
            #expect(decoded.count > 30, "decoded for real, not an empty fallback")
            #expect(!decoded.contains(onA.pairKey))
        }
    }

    /// The review's attack: someone in the middle shows B their own commitment and A their own
    /// offer. B's check of A's reveal fails, so B stops before any code is shown.
    @Test func aRevealThatDoesNotMatchTheHashIsRefused() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let mallory = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: mallory.commitment)
        let (_, revealFromA) = try a.agree(with: b.offer)
        #expect(throws: Pairing.PairingError.commitmentMismatch) { try b.agree(with: revealFromA) }
    }

    /// Mallory relays honestly to B with her own key, and swaps her key in towards A: the keys
    /// differ, so the two screens show different codes and the people stop.
    @Test func aSwappedKeyGivesDifferentCodes() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let mallory = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: mallory.commitment)
        let malloryToA = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        let (onA, _) = try a.agree(with: malloryToA.offer)
        let (_, malloryReveal) = try mallory.agree(with: b.offer)
        let onB = try b.agree(with: malloryReveal)
        #expect(onA.pairKey != onB.pairKey)
    }

    /// Once A revealed its key, a second QR 2 could be chosen against it to force A's code, so A
    /// reveals once per attempt. A bad scan before that does not use the attempt up.
    @Test func theInitiatorRevealsOnlyOnce() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        #expect(throws: Pairing.PairingError.wrongStep) { try a.agree(with: a.commitment) }
        _ = try a.agree(with: b.offer)
        let mallory = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        #expect(throws: Pairing.PairingError.alreadyRevealed) { try a.agree(with: mallory.offer) }
    }

    @Test func eachStepTakesOnlyItsOwnQR() throws {
        let a = Pairing.Initiator(deviceID: idA)
        #expect(throws: Pairing.PairingError.wrongStep) { try Pairing.Joiner(deviceID: idB, scanned: .offer(Pairing.Offer(publicKey: Data(), deviceID: UUID()))) }
        let b = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        #expect(throws: Pairing.PairingError.wrongStep) { try a.agree(with: a.commitment) }
        #expect(throws: Pairing.PairingError.wrongStep) { try b.agree(with: b.offer) }
    }

    @Test func messagesRoundTripAndAnythingElseIsRejected() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let b = try Pairing.Joiner(deviceID: idB, scanned: a.commitment)
        let (_, reveal) = try a.agree(with: b.offer)
        for message in [a.commitment, b.offer, reveal] {
            #expect(try scan(message) == message)
        }

        #expect(throws: Pairing.PairingError.notAPairingCode) { try Pairing.Message(qrString: "https://example.com") }
        #expect(throws: Pairing.PairingError.notAPairingCode) { try Pairing.Message(qrString: "betweenvault:pair:") }
        #expect(throws: Pairing.PairingError.notAPairingCode) { try Pairing.Message(qrString: String(b.offer.qrString.dropLast(4))) }
        // Version 2 at the front: base64 "Ag" instead of "AQ".
        var future = Array(a.commitment.qrString)
        future["betweenvault:pair:".count + 1] = "g"
        #expect(throws: Pairing.PairingError.unsupportedVersion) { try Pairing.Message(qrString: String(future)) }
    }

    @Test func aPhoneCannotPairWithItself() throws {
        let a = Pairing.Initiator(deviceID: idA)
        let selfJoin = try Pairing.Joiner(deviceID: idA, scanned: a.commitment)
        #expect(throws: Pairing.PairingError.ownCode) { try a.agree(with: selfJoin.offer) }
    }

    // MARK: Commit

    private func makePartners() throws -> (PartnerRepository, ModelContainer) {
        let container = try ModelContainer(for: PartnerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (PartnerRepository(context: container.mainContext), container)
    }

    private func agreement() throws -> Pairing.Agreement {
        try pair().onA
    }

    /// "Codes match" stores the key and the partner; nothing is written before it.
    @Test func confirmingStoresTheKeyAndThePartner() throws {
        let (partners, container) = try makePartners()
        _ = container
        let agreed = try agreement()
        var stored: Data?
        try Pairing.commit(agreed, partners: partners, saveKey: { stored = $0 }, deleteKey: { stored = nil })

        #expect(stored == agreed.pairKey)
        let partner = try #require(try partners.partner())
        #expect(partner.deviceID == idB)
        #expect(partner.fingerprint == agreed.fingerprint)
    }

    /// Single partner per install (spec 1).
    @Test func aSecondPairingIsRefused() throws {
        let (partners, container) = try makePartners()
        _ = container
        try Pairing.commit(try agreement(), partners: partners, saveKey: { _ in }, deleteKey: {})
        var saved = false
        #expect(throws: Pairing.PairingError.alreadyPaired) {
            try Pairing.commit(try agreement(), partners: partners, saveKey: { _ in saved = true }, deleteKey: {})
        }
        #expect(!saved)
    }

    // MARK: Recovery blob

    @Test func theRecoveryBlobOpensOnlyWithItsPairKeyAndOwner() throws {
        let vaultKey = CryptoEngine.randomKey()
        let pairKey = try agreement().pairKey
        let blob = try Pairing.wrapRecovery(vaultKey: vaultKey, pairKey: pairKey, ownerDeviceID: idA)

        #expect(try Pairing.unwrapRecovery(blob, pairKey: pairKey, ownerDeviceID: idA) == vaultKey)
        #expect(!blob.contains(vaultKey))
        #expect(throws: CryptoEngine.CryptoError.self) {
            try Pairing.unwrapRecovery(blob, pairKey: CryptoEngine.randomKey(), ownerDeviceID: idA)
        }
        #expect(throws: CryptoEngine.CryptoError.self) {
            try Pairing.unwrapRecovery(blob, pairKey: pairKey, ownerDeviceID: idB)
        }
    }
}
