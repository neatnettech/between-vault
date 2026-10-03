import Foundation
import Observation
import SwiftData

/// Composition root. Every service and repository is built here and passed down
/// through the environment. No singletons beyond this.
@MainActor
@Observable
final class AppServices {
    let container: ModelContainer
    let noteRepository: NoteRepository
    let categoryRepository: CategoryRepository
    let partnerRepository: PartnerRepository
    let exchangeLogRepository: ExchangeLogRepository
    let pendingPackages: PendingPackageRepository
    let exchangeService: ExchangeService
    let importService: ImportService
    /// Read each time: a reset hands the installation a new one.
    var deviceID: String { Identity.deviceID() }
    /// Row 2.4. True while the store holds notes from before onboarding (rc.1, a lost flag), so
    /// onboarding stays behind the lock. A reset clears it: what is left is unreadable.
    private(set) var guardsOnboarding: Bool

    /// Keychain account name. Renaming it makes every existing record undecryptable, because the
    /// old key becomes unreachable, so it is frozen from the first TestFlight build onward.
    static let vaultKeyAccount = "betweenvault.vaultKey"

    init() throws {
        let schema = Schema([CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self, PendingPackageRecord.self])
        let configuration = ModelConfiguration(schema: schema)
        container = try ModelContainer(for: schema, configurations: [configuration])

        let context = container.mainContext
        let vaultKey: () throws -> Data = {
            if let key = try KeyManager.load(Self.vaultKeyAccount) { return key }
            // Notes without their key were kept by a reset for restore from the partner. A new
            // key here would strand them for good, so none is made until they are restored.
            guard try context.fetchCount(FetchDescriptor<NoteRecord>()) == 0 else { throw VaultKeyError.awaitingRestore }
            return try KeyManager.loadOrCreate(Self.vaultKeyAccount)
        }

        noteRepository = NoteRepository(context: context, vaultKey: vaultKey)
        categoryRepository = CategoryRepository(context: context)
        partnerRepository = PartnerRepository(context: context)
        exchangeLogRepository = ExchangeLogRepository(context: context)
        pendingPackages = PendingPackageRepository(context: context)
        exchangeService = ExchangeService(
            notes: noteRepository,
            categories: categoryRepository,
            partners: partnerRepository,
            log: exchangeLogRepository,
            pairKey: { try KeyManager.load(Pairing.pairKeyAccount) },
            deviceID: { Identity.deviceID() }
        )
        importService = ImportService(
            context: context,
            notes: noteRepository,
            categories: categoryRepository,
            partners: partnerRepository,
            log: exchangeLogRepository,
            pairKey: { try KeyManager.load(Pairing.pairKeyAccount) },
            deviceID: { Identity.deviceID() }
        )
        _ = Identity.deviceID()
        guardsOnboarding = (try? context.fetchCount(FetchDescriptor<NoteRecord>())) != 0

        try categoryRepository.seedIfNeeded()
    }

    /// Row 2.4, the forgotten passcode. Erases everything that opens or identifies this vault: the
    /// vault key, the passcode, the device ID and the pairing with its pair key, so the phone starts over like a new
    /// one. Paired, the encrypted notes stay for restore from the partner, which returns the
    /// original key (spec 20). Not paired, nothing can ever open them, so they go too, as board
    /// 1b warns. Keys first, store last: the pairing decides what the store keeps, so it goes in
    /// the final step and a retry after any failure still decides the same way. Notes left without
    /// their key meanwhile are safe, because no new key is made over them.
    func resetVault() throws {
        try KeyManager.delete(Self.vaultKeyAccount)
        try KeyManager.delete(Passcode.account)
        try KeyManager.delete(Pairing.pairKeyAccount)
        try KeyManager.delete(Pairing.partnerRecoveryAccount)
        try KeyManager.delete(Pairing.retiredRecoveryAccount)
        RecoveryStatus().forget()
        Identity.reset()
        try Self.eraseRecords(in: container.mainContext)
        guardsOnboarding = false
    }
}

// MARK: - Partner (row 3.7)

extension AppServices {
    enum PartnerError: Error {
        case notPaired
        case keyMissing
    }

    /// "Send recovery file to partner": this phone's vault key, wrapped for the partner, as a file
    /// in a temporary folder for the share sheet. The caller deletes it once shared.
    func recoveryFile() throws -> URL {
        let data = try recoveryFileData()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Between Vault recovery.\(Pairing.RecoveryFile.fileExtension)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// The recovery file's bytes, for the file route above or the nearby connection.
    func recoveryFileData() throws -> Data {
        guard let partner = try partnerRepository.partner() else { throw PartnerError.notPaired }
        guard let vaultKey = try KeyManager.load(Self.vaultKeyAccount),
              let pairKey = try KeyManager.load(Pairing.pairKeyAccount)
        else { throw PartnerError.keyMissing }
        // Row 6.2: a copy kept from their old iPhone goes back to them, wrapped for this pairing.
        // One that no longer opens is dropped, so it never stops this phone sending its own.
        var returned: Data?
        if let data = try KeyManager.load(Pairing.retiredRecoveryAccount) {
            returned = try? Pairing.rewrap(JSONDecoder().decode(Pairing.RetiredCopy.self, from: data), pairKey: pairKey, newOwnerDeviceID: partner.deviceID)
            if returned == nil { try? dropRetiredRecovery() }
        }
        return try Pairing.RecoveryFile.make(vaultKey: vaultKey, pairKey: pairKey, owner: deviceID, holder: partner.deviceID, returned: returned)
    }

    /// The partner's recovery file, opened on this phone: checked, then only its blob is kept. If it
    /// brings this phone's own vault key back while notes wait for it, the vault opens again
    /// (rows 6.1, 6.3).
    enum RecoveryReceipt: Equatable {
        case kept
        case restored
        /// Their copy is kept, but the key it returned does not open the waiting notes: a copy
        /// from an older vault.
        case notThisVaultsKey
        /// Notes wait, but the file brought no key back: their phone kept no copy to return.
        case noKeyReturned
    }

    @discardableResult
    func receiveRecoveryFile(_ data: Data) throws -> RecoveryReceipt {
        guard let partner = try partnerRepository.partner() else { throw PartnerError.notPaired }
        guard let pairKey = try KeyManager.load(Pairing.pairKeyAccount) else { throw PartnerError.keyMissing }
        let accepted = try Pairing.RecoveryFile.accept(data, pairKey: pairKey, me: deviceID, partner: partner.deviceID)
        try KeyManager.delete(Pairing.partnerRecoveryAccount)
        try KeyManager.save(accepted.blob, account: Pairing.partnerRecoveryAccount)
        RecoveryStatus().markReceived()
        // Their own copy arrived, so their phone works under this pairing: a retired copy is done
        // with. Single use: it must not travel on to whoever this phone pairs with next.
        try dropRetiredRecovery()
        guard awaitsRestore else { return .kept }
        // Nothing waiting: a fresh phone with no backup has no notes this key opens, and a vault
        // that has its key keeps it.
        guard let key = accepted.returnedVaultKey else { return .noKeyReturned }
        return try Self.restore(key, in: container.mainContext) ? .restored : .notThisVaultsKey
    }

    /// Onboarded, yet neither the passcode nor the vault key is in the Keychain: only a device
    /// backup leaves that. Definite absence only, as in `awaitsRestore`.
    func cameFromDeviceBackup(onboarded: Bool) -> Bool {
        guard onboarded,
              case .some(.none) = try? KeyManager.load(Passcode.account),
              case .some(.none) = try? KeyManager.load(Self.vaultKeyAccount)
        else { return false }
        return true
    }

    /// Notes kept without their key: after a reset (2.4) or a device backup (keys never travel in
    /// one). Only a definite "no key" counts; a Keychain error is not a missing key.
    var awaitsRestore: Bool {
        guard case .some(.none) = try? KeyManager.load(Self.vaultKeyAccount) else { return false }
        return ((try? container.mainContext.fetchCount(FetchDescriptor<NoteRecord>())) ?? 0) > 0
    }

    /// Saves the returned key only if it opens a waiting note: a copy from an older vault would
    /// otherwise become the key and strand them.
    static func restore(_ key: Data, in context: ModelContext, save: (Data) throws -> Void = { try KeyManager.save($0, account: vaultKeyAccount) }) throws -> Bool {
        var one = FetchDescriptor<NoteRecord>()
        one.fetchLimit = 1
        guard let note = try context.fetch(one).first, (try? CryptoEngine.decrypt(note.ciphertext, key: key)) != nil else { return false }
        try save(key)
        return true
    }

    /// Whether this phone holds the partner's recovery copy, told to them when the phones meet.
    var holdsPartnerRecovery: Bool {
        ((try? KeyManager.load(Pairing.partnerRecoveryAccount)) ?? nil) != nil
    }

    /// Spec 13: unpairing stops future exchanges here. Keys first, record last: while any step
    /// fails the partner still shows, so Unpair stays on screen and a retry finishes the job.
    /// Offline, the partner's phone cannot be told; a recovery file already sent stays with them.
    func unpair() throws {
        try KeyManager.delete(Pairing.retiredRecoveryAccount)
        try endPairing()
    }

    /// Row 6.2, "Partner has a new iPhone": this pairing ends like Unpair, but their recovery copy
    /// is kept with the old pair key, to go back to their new iPhone once paired. With no copy
    /// held, an earlier retired one stays.
    func retirePairing() throws {
        guard let partner = try partnerRepository.partner() else { throw PartnerError.notPaired }
        if let blob = try KeyManager.load(Pairing.partnerRecoveryAccount),
           let pairKey = try KeyManager.load(Pairing.pairKeyAccount) {
            let retired = try JSONEncoder().encode(Pairing.RetiredCopy(blob: blob, pairKey: pairKey, ownerDeviceID: partner.deviceID))
            try KeyManager.delete(Pairing.retiredRecoveryAccount)
            try KeyManager.save(retired, account: Pairing.retiredRecoveryAccount)
        }
        try endPairing()
    }

    /// The retired copy reached the partner's new iPhone, or is no longer needed.
    func dropRetiredRecovery() throws {
        try KeyManager.delete(Pairing.retiredRecoveryAccount)
    }

    /// Whether this phone keeps a copy for a partner's new iPhone.
    var holdsRetiredRecovery: Bool {
        ((try? KeyManager.load(Pairing.retiredRecoveryAccount)) ?? nil) != nil
    }

    private func endPairing() throws {
        RecoveryStatus().forget()
        try KeyManager.delete(Pairing.partnerRecoveryAccount)
        try KeyManager.delete(Pairing.pairKeyAccount)
        try partnerRepository.removeAll()
    }
}

extension AppServices {
    /// The store half of `resetVault`, on its own so a test can run it in memory.
    static func eraseRecords(in context: ModelContext) throws {
        let keepNotes = try PartnerRepository(context: context).partner() != nil
        try context.delete(model: PartnerRecord.self)
        try context.delete(model: ExchangeLogRecord.self)
        try context.delete(model: PendingPackageRecord.self)
        if !keepNotes {
            try context.delete(model: NoteRecord.self)
            try context.delete(model: CategoryRecord.self)
        }
        try context.save()
        try CategoryRepository(context: context).seedIfNeeded()
    }
}

enum VaultKeyError: Error {
    /// Notes kept by a reset wait for their key from the partner (rows 6.1, 6.3).
    case awaitingRestore
}
