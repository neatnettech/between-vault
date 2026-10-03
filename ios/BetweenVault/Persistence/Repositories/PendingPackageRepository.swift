import Foundation
import SwiftData

/// Board X1 "Waiting for you": files from the partner the owner chose to decide on later (R2,
/// Decide later). Only the package as it arrived is kept: still encrypted under the package key,
/// never decrypted titles. Accepting or declining removes it.
@Model
final class PendingPackageRecord {
    @Attribute(.unique) var exchangeID: String
    /// The .nvlt bytes, encrypted as received.
    var data: Data
    var receivedAt: Date
    var itemCount: Int

    init(exchangeID: String, data: Data, receivedAt: Date, itemCount: Int) {
        self.exchangeID = exchangeID
        self.data = data
        self.receivedAt = receivedAt
        self.itemCount = itemCount
    }
}

struct PendingPackage: Identifiable, Equatable, Sendable {
    let exchangeID: String
    let data: Data
    let receivedAt: Date
    let itemCount: Int
    var id: String { exchangeID }
}

@MainActor
final class PendingPackageRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Newest first.
    func all() throws -> [PendingPackage] {
        try context.fetch(FetchDescriptor<PendingPackageRecord>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))
            .map { PendingPackage(exchangeID: $0.exchangeID, data: $0.data, receivedAt: $0.receivedAt, itemCount: $0.itemCount) }
    }

    /// Decide later. Keeping the same file twice keeps it once.
    func keep(exchangeID: String, data: Data, itemCount: Int, at date: Date = .now) throws {
        try remove(exchangeID, commit: false)
        context.insert(PendingPackageRecord(exchangeID: exchangeID, data: data, receivedAt: date, itemCount: itemCount))
        try context.saveOrRollback()
    }

    /// Accepted, declined, or found already imported: it no longer waits.
    func remove(_ exchangeID: String, commit: Bool = true) throws {
        for record in try context.fetch(FetchDescriptor<PendingPackageRecord>(predicate: #Predicate { $0.exchangeID == exchangeID })) {
            context.delete(record)
        }
        if commit { try context.saveOrRollback() }
    }
}
