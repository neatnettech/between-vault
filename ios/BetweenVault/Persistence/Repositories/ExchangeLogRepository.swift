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

    func record(_ exchangeID: String, direction: ExchangeDirection, itemCount: Int = 0, at date: Date = .now) throws {
        guard try !hasImported(exchangeID) else { return }
        context.insert(ExchangeLogRecord(exchangeID: exchangeID, directionRaw: direction.rawValue, importedAt: date, itemCount: itemCount))
        try context.saveOrRollback()
    }

    /// Board 18, newest first.
    func history() throws -> [ExchangeLogEntry] {
        try context.fetch(FetchDescriptor<ExchangeLogRecord>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)]))
            .compactMap { record in
                ExchangeDirection(rawValue: record.directionRaw).map {
                    ExchangeLogEntry(id: record.exchangeID, direction: $0, date: record.importedAt, itemCount: record.itemCount)
                }
            }
    }
}

struct ExchangeLogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let direction: ExchangeDirection
    let date: Date
    let itemCount: Int
}

enum ExchangeDirection: String, Sendable {
    case sent
    case received
}
