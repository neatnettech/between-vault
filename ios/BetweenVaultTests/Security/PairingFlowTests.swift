import Foundation
import Testing

@testable import BetweenVault

/// Rows 3.2 to 3.6: two flows driven against each other, as two phones would be.
@MainActor
struct PairingFlowTests {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
    private final class Store { var saved: [Pairing.Agreement] = [] }

    private func makePair(_ clock: Clock = Clock(), store: Store = Store()) -> (a: PairingFlow, b: PairingFlow) {
        let a = PairingFlow(role: .starter, deviceID: "0f8fad5b-d9cb-469f-a165-70867728950e",
                            commit: { store.saved.append($0) }, now: { clock.now })
        let b = PairingFlow(role: .joiner, deviceID: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
                            commit: { store.saved.append($0) }, now: { clock.now })
        return (a, b)
    }

    private func shown(_ flow: PairingFlow) throws -> String {
        guard case let .show(message, _) = flow.step else { throw Pairing.PairingError.wrongStep }
        return message.qrString
    }

    /// Walks both phones to the compare screen.
    private func walk(_ a: PairingFlow, _ b: PairingFlow) throws {
        b.scanned(try shown(a))          // B scans QR 1
        a.next()                         // A: partner scanned it
        a.scanned(try shown(b))          // A scans QR 2
        b.next()
        b.scanned(try shown(a))          // B scans QR 3
        a.next()
    }

    @Test func bothPhonesReachTheSameCodeAndEachSavesOnItsOwnConfirm() throws {
        let store = Store()
        let (a, b) = makePair(store: store)
        try walk(a, b)

        guard case let .compare(codeA) = a.step, case let .compare(codeB) = b.step else {
            Issue.record("not at compare: \(a.step) \(b.step)"); return
        }
        #expect(codeA == codeB)
        #expect(store.saved.isEmpty, "nothing is written before Codes match")

        a.confirm()
        #expect(a.step == .paired)
        #expect(store.saved.count == 1)
        b.confirm()
        #expect(b.step == .paired)
        #expect(store.saved.map(\.pairKey) == [store.saved[0].pairKey, store.saved[0].pairKey])
    }

    @Test func theStepsGoInTheBoardOrder() throws {
        let (a, b) = makePair()
        guard case .show(_, index: 1) = a.step else { Issue.record("\(a.step)"); return }
        #expect(b.step == .scan(index: 1))
        b.scanned(try shown(a))
        guard case .show(_, index: 2) = b.step else { Issue.record("\(b.step)"); return }
        a.next()
        #expect(a.step == .scan(index: 2))
        a.scanned(try shown(b))
        guard case .show(_, index: 3) = a.step else { Issue.record("\(a.step)"); return }
        b.next()
        #expect(b.step == .scan(index: 3))
    }

    /// Board 13a: "They don't match" stops and stores nothing.
    @Test func theyDontMatchStoresNothing() throws {
        let store = Store()
        let (a, b) = makePair(store: store)
        try walk(a, b)
        a.reject()
        #expect(a.step == .failed(.codesDidNotMatch))
        a.confirm()
        #expect(store.saved.isEmpty)
        _ = b
    }

    /// A reveal from a phone other than the one that showed QR 1 stops B like different codes.
    @Test func aRevealFromAnotherPhoneStops() throws {
        let (a, b) = makePair()
        let (other, _) = makePair()
        b.scanned(try shown(other))     // B scanned someone else's QR 1
        a.next()
        a.scanned(try shown(b))
        b.next()
        b.scanned(try shown(a))         // A's reveal does not open other's hash
        #expect(b.step == .failed(.codesDidNotMatch))
    }

    /// Anything else in front of the camera keeps it up with a reason.
    @Test func anUnusableScanKeepsTheCameraUp() throws {
        let (a, b) = makePair()
        b.scanned("https://example.com")
        #expect(b.step == .scan(index: 1))
        #expect(b.scanProblem == .notAPairingCode)
        b.scanned(try shown(a))
        #expect(b.scanProblem == nil)
        // QR 2 scanned where QR 3 belongs: the wrong step, not a failure.
        a.next()
        a.scanned(try shown(b))
        b.next()
        b.scanned(Pairing.Message.offer(Pairing.Offer(publicKey: Data(repeating: 9, count: 32), deviceID: UUID())).qrString)
        #expect(b.step == .scan(index: 3))
        #expect(b.scanProblem == .wrongStep)
    }

    /// Board 12c: each phone times out on its own after 5 minutes, and a late tap cannot finish.
    @Test func fiveMinutesEndTheAttempt() throws {
        let clock = Clock()
        let store = Store()
        let (a, b) = makePair(clock, store: store)
        try walk(a, b)
        clock.now.addTimeInterval(PairingFlow.lifetime)
        a.confirm()
        #expect(a.step == .failed(.timedOut))
        #expect(store.saved.isEmpty)
        _ = b
    }

    @Test func aRefusedSaveSaysNotSaved() throws {
        struct Refused: Error {}
        let clock = Clock()
        let a = PairingFlow(role: .starter, deviceID: "0f8fad5b-d9cb-469f-a165-70867728950e",
                            commit: { _ in throw Refused() }, now: { clock.now })
        let b = PairingFlow(role: .joiner, deviceID: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
                            commit: { _ in }, now: { clock.now })
        try walk(a, b)
        a.confirm()
        #expect(a.step == .failed(.notSaved))
    }
}
