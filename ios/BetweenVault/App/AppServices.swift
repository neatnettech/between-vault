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
        guard let partner = try partnerRepository.partner() else { throw PartnerError.notPaired }
        guard let vaultKey = try KeyManager.load(Self.vaultKeyAccount),
              let pairKey = try KeyManager.load(Pairing.pairKeyAccount)
        else { throw PartnerError.keyMissing }
        let data = try Pairing.RecoveryFile.make(vaultKey: vaultKey, pairKey: pairKey, owner: deviceID, holder: partner.deviceID)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Between Vault recovery.\(Pairing.RecoveryFile.fileExtension)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// The partner's recovery file, opened on this phone: checked, then only its blob is kept.
    func receiveRecoveryFile(_ data: Data) throws {
        guard let partner = try partnerRepository.partner() else { throw PartnerError.notPaired }
        guard let pairKey = try KeyManager.load(Pairing.pairKeyAccount) else { throw PartnerError.keyMissing }
        let blob = try Pairing.RecoveryFile.accept(data, pairKey: pairKey, me: deviceID, partner: partner.deviceID)
        try KeyManager.delete(Pairing.partnerRecoveryAccount)
        try KeyManager.save(blob, account: Pairing.partnerRecoveryAccount)
    }

    /// Spec 13: unpairing stops future exchanges here. Keys first, record last: while any step
    /// fails the partner still shows, so Unpair stays on screen and a retry finishes the job.
    /// Offline, the partner's phone cannot be told; a recovery file already sent stays with them.
    func unpair() throws {
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
