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

    func record(
        _ exchangeID: String, direction: ExchangeDirection, itemCount: Int = 0, at date: Date = .now,
        conflictsKeptBoth: Int = 0
    ) throws {
        guard try !hasImported(exchangeID) else { return }
        context.insert(ExchangeLogRecord(
            exchangeID: exchangeID, directionRaw: direction.rawValue, importedAt: date, itemCount: itemCount,
            outcomeRaw: conflictsKeptBoth > 0 ? "keptBoth:\(conflictsKeptBoth)" : ""
        ))
        try context.saveOrRollback()
    }

    /// Board 9d: when this exchange was imported, or nil. Declines do not count.
    func receivedDate(_ exchangeID: String) throws -> Date? {
        let received = ExchangeDirection.received.rawValue
        return try context.fetch(FetchDescriptor<ExchangeLogRecord>(
            predicate: #Predicate { $0.exchangeID == exchangeID && $0.directionRaw == received }
        )).first?.importedAt
    }

    /// Board 18, newest first.
    func history() throws -> [ExchangeLogEntry] {
        try context.fetch(FetchDescriptor<ExchangeLogRecord>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)]))
            .compactMap { record in
                ExchangeDirection(rawValue: record.directionRaw).map {
                    ExchangeLogEntry(
                        id: record.exchangeID, direction: $0, date: record.importedAt, itemCount: record.itemCount,
                        conflictsKeptBoth: record.outcomeRaw.hasPrefix("keptBoth:") ? Int(record.outcomeRaw.dropFirst(9)) ?? 0 : 0
                    )
                }
            }
    }
}

struct ExchangeLogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let direction: ExchangeDirection
    let date: Date
    let itemCount: Int
    var conflictsKeptBoth = 0
}

enum ExchangeDirection: String, Sendable {
    case sent
    case received
    /// Board 18 "Declined 1 file".
    case declined
}
