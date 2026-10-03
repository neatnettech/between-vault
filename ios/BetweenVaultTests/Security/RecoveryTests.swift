import Foundation
import SwiftData
import Testing

@testable import BetweenVault

/// Row 6.9: restore from the partner (6.1, 6.3) and the re-wrap on their phone (6.2), with the
/// Keychain left out: these are the pure halves the Keychain calls wrap.
@MainActor
struct RecoveryTests {
    private let vaultKeyA = CryptoEngine.randomKey()
    private let oldA = UUID().uuidString.lowercased()
    private let newA = UUID().uuidString.lowercased()
    private let idB = UUID().uuidString.lowercased()
    private let pairKeyV1 = CryptoEngine.randomKey()
    private let pairKeyV2 = CryptoEngine.randomKey()

    /// B holds A's copy from pairing v1, retires it, pairs with A's new phone (v2) and sends its
    /// recovery file: A's new phone gets its original vault key back.
    @Test func aNewPhoneGetsItsOriginalVaultKeyBack() throws {
        let fromOldA = try Pairing.RecoveryFile.make(vaultKey: vaultKeyA, pairKey: pairKeyV1, owner: oldA, holder: idB)
        let held = try Pairing.RecoveryFile.accept(fromOldA, pairKey: pairKeyV1, me: idB, partner: oldA)
        #expect(held.returnedVaultKey == nil)

        let retired = Pairing.RetiredCopy(blob: held.blob, pairKey: pairKeyV1, ownerDeviceID: oldA)
        let returned = try Pairing.rewrap(retired, pairKey: pairKeyV2, newOwnerDeviceID: newA)
        let fromB = try Pairing.RecoveryFile.make(
            vaultKey: CryptoEngine.randomKey(), pairKey: pairKeyV2, owner: idB, holder: newA, returned: returned
        )
        let accepted = try Pairing.RecoveryFile.accept(fromB, pairKey: pairKeyV2, me: newA, partner: idB)
        #expect(accepted.returnedVaultKey == vaultKeyA)
    }

    /// The re-wrapped copy is bound to the new pairing and the new device: the old pair key, or
    /// the old device ID, opens nothing.
    @Test func theRewrappedCopyOpensOnlyUnderTheNewPairing() throws {
        let blob = try Pairing.wrapRecovery(vaultKey: vaultKeyA, pairKey: pairKeyV1, ownerDeviceID: oldA)
        let returned = try Pairing.rewrap(Pairing.RetiredCopy(blob: blob, pairKey: pairKeyV1, ownerDeviceID: oldA), pairKey: pairKeyV2, newOwnerDeviceID: newA)
        #expect(throws: (any Error).self) { try Pairing.unwrapRecovery(returned, pairKey: pairKeyV1, ownerDeviceID: newA) }
        #expect(throws: (any Error).self) { try Pairing.unwrapRecovery(returned, pairKey: pairKeyV2, ownerDeviceID: oldA) }
        #expect(try Pairing.unwrapRecovery(returned, pairKey: pairKeyV2, ownerDeviceID: newA) == vaultKeyA)
    }

    /// A retired copy whose pair key does not open it is refused, not passed on.
    @Test func aRetiredCopyUnderTheWrongKeyIsNotRewrapped() throws {
        let blob = try Pairing.wrapRecovery(vaultKey: vaultKeyA, pairKey: pairKeyV1, ownerDeviceID: oldA)
        #expect(throws: (any Error).self) {
            try Pairing.rewrap(Pairing.RetiredCopy(blob: blob, pairKey: pairKeyV2, ownerDeviceID: oldA), pairKey: pairKeyV2, newOwnerDeviceID: newA)
        }
    }

    /// A returned key that is not wrapped for this phone refuses the whole file: nothing is kept.
    @Test func aReturnedKeyForAnotherPhoneRefusesTheFile() throws {
        let returned = try Pairing.wrapRecovery(vaultKey: vaultKeyA, pairKey: pairKeyV2, ownerDeviceID: oldA)
        let file = try Pairing.RecoveryFile.make(vaultKey: CryptoEngine.randomKey(), pairKey: pairKeyV2, owner: idB, holder: newA, returned: returned)
        #expect(throws: Pairing.RecoveryFile.Problem.notForThisPairing) {
            try Pairing.RecoveryFile.accept(file, pairKey: pairKeyV2, me: newA, partner: idB)
        }
    }

    /// Files from before row 6.2 have no `returned` field and still open.
    @Test func aFileWithoutAReturnedKeyStillOpens() throws {
        let blob = try Pairing.wrapRecovery(vaultKey: vaultKeyA, pairKey: pairKeyV1, ownerDeviceID: idB)
        let json = """
        {"format":"betweenvault.recovery","version":1,"ownerDeviceID":"\(idB)","holderDeviceID":"\(newA)","blob":"\(blob.base64EncodedString())"}
        """
        let accepted = try Pairing.RecoveryFile.accept(Data(json.utf8), pairKey: pairKeyV1, me: newA, partner: idB)
        #expect(accepted.blob == blob)
        #expect(accepted.returnedVaultKey == nil)
    }

    /// Row 6.1: the key is saved only if it opens the notes waiting for it.
    @Test func restoreSavesOnlyAKeyThatOpensTheWaitingNotes() throws {
        let container = try ModelContainer(for: NoteRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        try NoteRepository(context: context, vaultKey: { vaultKeyA }).save(Note(
            id: UUID(), title: "Boiler", body: "Engineer", state: .private, categoryID: nil,
            version: 1, baseVersion: 0, partnerKnownVersion: 0, createdAt: .now, updatedAt: .now
        ))
        var saved: [Data] = []

        #expect(try AppServices.restore(CryptoEngine.randomKey(), in: context) { saved.append($0) } == false)
        #expect(saved.isEmpty)
        #expect(try AppServices.restore(vaultKeyA, in: context) { saved.append($0) })
        #expect(saved == [vaultKeyA])
        #expect(try NoteRepository(context: context, vaultKey: { saved[0] }).notes(in: nil).map(\.title) == ["Boiler"])
    }
}
