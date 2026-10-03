import Foundation

/// Boards P1, P2: where each recovery copy stands. The recovery copy is the vault key only, so it
/// never goes stale as notes change; what can be out of date is whether the partner holds the
/// current one (never sent, sent as a file and not confirmed, or a pairing made since).
/// Metadata only, no key material: dates in UserDefaults.
struct RecoveryStatus {
    enum Yours: Equatable {
        case notSent
        /// Sent as a file; nothing has confirmed it arrived.
        case sentAsFile(Date)
        case upToDate(Date)
        /// Paired again since: the copy on their phone belongs to the old pairing.
        case needsUpdate
    }

    enum Theirs: Equatable {
        case notReceived
        case upToDate(Date)
    }

    /// Persisted keys; renaming one forgets that date.
    private enum Keys {
        static let deliveredAt = "betweenvault.recovery.deliveredAt"
        static let fileSentAt = "betweenvault.recovery.fileSentAt"
        static let receivedAt = "betweenvault.recovery.receivedAt"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func yours(pairedAt: Date) -> Yours {
        if let delivered = defaults.object(forKey: Keys.deliveredAt) as? Date {
            return delivered >= pairedAt ? .upToDate(delivered) : .needsUpdate
        }
        if let sent = defaults.object(forKey: Keys.fileSentAt) as? Date, sent >= pairedAt {
            return .sentAsFile(sent)
        }
        return .notSent
    }

    func theirs(pairedAt: Date) -> Theirs {
        guard let received = defaults.object(forKey: Keys.receivedAt) as? Date, received >= pairedAt else { return .notReceived }
        return .upToDate(received)
    }

    /// The partner's phone said it kept the copy (nearby).
    func markDelivered(at date: Date = .now) {
        defaults.set(date, forKey: Keys.deliveredAt)
        defaults.removeObject(forKey: Keys.fileSentAt)
    }

    /// Handed over as a file; unconfirmed until the phones next meet.
    func markSentAsFile(at date: Date = .now) {
        defaults.set(date, forKey: Keys.fileSentAt)
    }

    /// Meeting nearby: the partner's phone says whether it holds this phone's copy. Holding it
    /// confirms a file send; not holding it (they reset or unpaired since) means sending again.
    func partnerHolds(_ holds: Bool, at date: Date = .now) {
        if holds {
            if defaults.object(forKey: Keys.deliveredAt) == nil {
                markDelivered(at: (defaults.object(forKey: Keys.fileSentAt) as? Date) ?? date)
            }
        } else {
            defaults.removeObject(forKey: Keys.deliveredAt)
            defaults.removeObject(forKey: Keys.fileSentAt)
        }
    }

    /// The partner's copy was checked and kept on this phone, by nearby or as a file.
    func markReceived(at date: Date = .now) {
        defaults.set(date, forKey: Keys.receivedAt)
    }

    /// Unpairing or a reset: both copies belong to a pairing that is gone.
    func forget() {
        for key in [Keys.deliveredAt, Keys.fileSentAt, Keys.receivedAt] { defaults.removeObject(forKey: key) }
    }
}
