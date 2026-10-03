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
        conflictsKeptBoth: Int = 0, unconfirmed: Bool = false
    ) throws {
        guard try !hasImported(exchangeID) else { return }
        let outcome = unconfirmed ? Self.unconfirmed : conflictsKeptBoth > 0 ? "keptBoth:\(conflictsKeptBoth)" : ""
        context.insert(ExchangeLogRecord(
            exchangeID: exchangeID, directionRaw: direction.rawValue, importedAt: date, itemCount: itemCount,
            outcomeRaw: outcome
        ))
        try context.saveOrRollback()
    }

    private static let unconfirmed = "unconfirmed"

    /// Exchange IDs this phone imported, for the partner's phone to confirm its file sends
    /// (board F2) during an exchange nearby. IDs only, never content.
    func receivedExchangeIDs() throws -> Set<String> {
        let received = ExchangeDirection.received.rawValue
        return Set(try context.fetch(FetchDescriptor<ExchangeLogRecord>(
            predicate: #Predicate { $0.directionRaw == received }
        )).map(\.exchangeID))
    }

    /// A file send the partner's phone confirmed: no longer "not confirmed". Staged; the caller saves.
    func stageConfirmed(_ exchangeID: String) throws {
        let unconfirmed = Self.unconfirmed
        for record in try context.fetch(FetchDescriptor<ExchangeLogRecord>(
            predicate: #Predicate { $0.exchangeID == exchangeID && $0.outcomeRaw == unconfirmed }
        )) {
            record.outcomeRaw = ""
        }
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
                        conflictsKeptBoth: record.outcomeRaw.hasPrefix("keptBoth:") ? Int(record.outcomeRaw.dropFirst(9)) ?? 0 : 0,
                        unconfirmed: record.outcomeRaw == Self.unconfirmed
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
    /// A file send no phone has confirmed yet (board F2).
    var unconfirmed = false
}

enum ExchangeDirection: String, Sendable {
    case sent
    case received
    /// Board 18 "Declined 1 file".
    case declined
}
