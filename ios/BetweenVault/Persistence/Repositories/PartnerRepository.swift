import Foundation
import SwiftData

@MainActor
final class PartnerRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func partner() throws -> Partner? {
        let records = try context.fetch(FetchDescriptor<PartnerRecord>())
        return records.first.map {
            Partner(id: $0.id, deviceID: $0.deviceID, fingerprint: $0.fingerprint, pairedAt: $0.pairedAt)
        }
    }

    func save(_ partner: Partner) throws {
        let id = partner.id
        if let existing = try context.fetch(
            FetchDescriptor<PartnerRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            existing.deviceID = partner.deviceID
            existing.fingerprint = partner.fingerprint
        } else {
            context.insert(PartnerRecord(id: partner.id, deviceID: partner.deviceID, fingerprint: partner.fingerprint, pairedAt: partner.pairedAt))
        }
        try context.saveOrRollback()
    }

    func removeAll() throws {
        for record in try context.fetch(FetchDescriptor<PartnerRecord>()) {
            context.delete(record)
        }
        try context.saveOrRollback()
    }
}
