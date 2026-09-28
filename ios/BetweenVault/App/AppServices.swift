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
    let deviceID: String

    init() throws {
        let schema = Schema([CategoryRecord.self, NoteRecord.self, PartnerRecord.self, ExchangeLogRecord.self])
        let configuration = ModelConfiguration(schema: schema)
        container = try ModelContainer(for: schema, configurations: [configuration])

        let context = container.mainContext
        // Keychain account name. Renaming it makes every existing record undecryptable, because the
        // old key becomes unreachable, so it is frozen from the first TestFlight build onward.
        let vaultKey: () throws -> Data = { try KeyManager.loadOrCreate("betweenvault.vaultKey") }

        noteRepository = NoteRepository(context: context, vaultKey: vaultKey)
        categoryRepository = CategoryRepository(context: context)
        partnerRepository = PartnerRepository(context: context)
        exchangeLogRepository = ExchangeLogRepository(context: context)
        deviceID = Identity.deviceID()

        try categoryRepository.seedIfNeeded()
    }
}
