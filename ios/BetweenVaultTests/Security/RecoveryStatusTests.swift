import Foundation
import Testing

@testable import BetweenVault

/// Boards P1, P2: the recovery copy is the vault key only, so its state is about whether the
/// partner holds the current one, never how old the notes are.
struct RecoveryStatusTests {
    private func store() -> RecoveryStatus { RecoveryStatus(defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    private let paired = Date(timeIntervalSince1970: 1_000_000)

    @Test func notSentUntilSomethingHappens() {
        let status = store()
        #expect(status.yours(pairedAt: paired) == .notSent)
        #expect(status.theirs(pairedAt: paired) == .notReceived)
    }

    /// A file send stays unconfirmed until the phones meet and the partner says it holds it.
    @Test func aFileSendIsConfirmedWhenThePhonesMeet() {
        let status = store()
        let sent = paired.addingTimeInterval(60)
        status.markSentAsFile(at: sent)
        #expect(status.yours(pairedAt: paired) == .sentAsFile(sent))
        status.partnerHolds(true, at: sent.addingTimeInterval(3600))
        #expect(status.yours(pairedAt: paired) == .upToDate(sent))
    }

    /// The partner reset or unpaired since: they no longer hold it, so it needs sending again.
    @Test func thePartnerNoLongerHoldingItMeansSendAgain() {
        let status = store()
        status.markDelivered(at: paired.addingTimeInterval(60))
        status.partnerHolds(false)
        #expect(status.yours(pairedAt: paired) == .notSent)
    }

    /// Paired again since the copy was delivered: it belongs to the old pairing.
    @Test func aNewerPairingNeedsAnUpdate() {
        let status = store()
        status.markDelivered(at: paired.addingTimeInterval(60))
        #expect(status.yours(pairedAt: paired.addingTimeInterval(120)) == .needsUpdate)
        status.markReceived(at: paired.addingTimeInterval(60))
        #expect(status.theirs(pairedAt: paired.addingTimeInterval(120)) == .notReceived)
    }

    @Test func forgetClearsBoth() {
        let status = store()
        status.markDelivered(at: paired.addingTimeInterval(1))
        status.markReceived(at: paired.addingTimeInterval(1))
        status.forget()
        #expect(status.yours(pairedAt: paired) == .notSent)
        #expect(status.theirs(pairedAt: paired) == .notReceived)
    }
}
