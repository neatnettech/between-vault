import Foundation
import Observation

/// Rows 3.2 to 3.6: the pairing screens' state, apart from the views so it can be tested.
///
/// A (starter): show QR 1, scan QR 2, show QR 3, compare.
/// B (joiner):  scan QR 1, show QR 2, scan QR 3, compare.
/// Each phone times out on its own after 5 minutes (board 12c), and saves only on its own
/// "Codes match". Nothing is written before that, whatever happens.
@MainActor
@Observable
final class PairingFlow {
    enum Role: Identifiable {
        case starter, joiner
        var id: Self { self }
    }

    enum Step: Equatable {
        /// Boards 11 and the reused 11 on B: a QR to hold up. `index` is 1 to 3.
        case show(Pairing.Message, index: Int)
        /// Board 12: the camera.
        case scan(index: Int)
        /// Board 13.
        case compare(code: String)
        case paired
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Board 13a, also a reveal that does not match the first QR.
        case codesDidNotMatch
        /// Board 12c.
        case timedOut
        /// The store or Keychain refused; nothing was saved.
        case notSaved
        case alreadyPaired
    }

    /// Board 11 footnote: "only works for the next 5 minutes".
    static let lifetime: TimeInterval = 5 * 60
    /// Three QR steps, then the compare.
    static let stepCount = 4

    let role: Role
    private(set) var step: Step
    /// A scan the step could not use, said inline under the camera; the camera keeps going.
    private(set) var scanProblem: Pairing.PairingError?
    let deadline: Date

    @ObservationIgnored private var starter: Pairing.Initiator?
    @ObservationIgnored private var joiner: Pairing.Joiner?
    @ObservationIgnored private var agreement: Pairing.Agreement?
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let commit: (Pairing.Agreement) throws -> Void
    @ObservationIgnored private let now: () -> Date

    init(
        role: Role,
        deviceID: String,
        commit: @escaping (Pairing.Agreement) throws -> Void,
        now: @escaping () -> Date = Date.init
    ) {
        self.role = role
        self.deviceID = deviceID
        self.commit = commit
        self.now = now
        deadline = now().addingTimeInterval(Self.lifetime)
        switch role {
        case .starter:
            let starter = Pairing.Initiator(deviceID: deviceID)
            self.starter = starter
            step = .show(starter.commitment, index: 1)
        case .joiner:
            step = .scan(index: 1)
        }
    }

    /// "Next" under a shown QR, once the partner has scanned it.
    func next() {
        guard !expire() else { return }
        switch step {
        case .show(_, index: 1): step = .scan(index: 2)
        case .show(_, index: 2): step = .scan(index: 3)
        case .show(_, index: 3): if let agreement { step = .compare(code: agreement.code) }
        default: break
        }
    }

    /// Whatever the camera read. Unusable input keeps the camera up with a reason.
    func scanned(_ text: String) {
        guard !expire(), case let .scan(index) = step else { return }
        do {
            let message = try Pairing.Message(qrString: text)
            switch (role, index) {
            case (.joiner, 1):
                let joiner = try Pairing.Joiner(deviceID: deviceID, scanned: message)
                self.joiner = joiner
                step = .show(joiner.offer, index: 2)
            case (.starter, 2):
                guard let starter else { return }
                let (agreement, reveal) = try starter.agree(with: message)
                self.agreement = agreement
                step = .show(reveal, index: 3)
            case (.joiner, 3):
                guard let joiner else { return }
                let agreement = try joiner.agree(with: message)
                self.agreement = agreement
                step = .compare(code: agreement.code)
            default:
                return
            }
            scanProblem = nil
        } catch Pairing.PairingError.commitmentMismatch {
            // The reveal is not the phone that showed QR 1: stop, as for different codes.
            fail(.codesDidNotMatch)
        } catch let error as Pairing.PairingError {
            scanProblem = error
        } catch {
            scanProblem = .notAPairingCode
        }
    }

    /// Board 13 "Codes match": the only write.
    func confirm() {
        guard !expire(), case .compare = step, let agreement else { return }
        do {
            try commit(agreement)
            forget()
            step = .paired
        } catch Pairing.PairingError.alreadyPaired {
            fail(.alreadyPaired)
        } catch {
            fail(.notSaved)
        }
    }

    /// Board 13 "They don't match".
    func reject() {
        fail(.codesDidNotMatch)
    }

    /// Board 12c, also checked on every action so a late tap cannot finish an expired attempt.
    @discardableResult
    func expire() -> Bool {
        switch step {
        case .paired, .failed: return false
        default: break
        }
        guard now() >= deadline else { return false }
        fail(.timedOut)
        return true
    }

    private func fail(_ failure: Failure) {
        forget()
        step = .failed(failure)
    }

    /// The one time keys and the agreement die with the attempt.
    private func forget() {
        starter = nil
        joiner = nil
        agreement = nil
        scanProblem = nil
    }
}
