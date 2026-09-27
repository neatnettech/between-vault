import Foundation
import SwiftData

@MainActor
final class ExchangeLogRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func hasImported(_ exchangeID: String) throws -> Bool {
        let matches = try context.fetch(
            FetchDescriptor<ExchangeLogRecord>(predicate: #Predicate { $0.exchangeID == exchangeID })
        )
        return !matches.isEmpty
    }

    func record(_ exchangeID: String, direction: ExchangeDirection) throws {
        guard try !hasImported(exchangeID) else { return }
        context.insert(ExchangeLogRecord(exchangeID: exchangeID, directionRaw: direction.rawValue))
        try context.save()
    }
}

enum ExchangeDirection: String {
    case sent
    case received
}
