import Foundation
import Testing

@testable import BetweenVault

/// Row 2.6 against a fake clipboard: every write bumps the change count, as UIPasteboard does.
@MainActor
struct ClipboardGuardTests {
    private final class Board {
        var count = 0
        var cleared = 0
        var protected = 0
    }

    private func makeGuard(_ board: Board) -> ClipboardGuard {
        ClipboardGuard(
            changeCount: { board.count },
            protect: { _ in board.protected += 1; board.count += 1 },
            clear: { board.cleared += 1; board.count += 1 },
            sleep: { _ in }
        )
    }

    @Test func aCopyIsProtectedThenCleared() async {
        let board = Board()
        let guarder = makeGuard(board)
        board.count += 1
        guarder.copied()
        await guarder.pendingTask?.value

        #expect(board.protected == 1)
        #expect(board.cleared == 1)
        #expect(guarder.clearedAt != nil)
    }

    /// The guard's own writes post the same notification; they must not start another round, or
    /// the toast would come back every minute.
    @Test func itsOwnWritesAreNotTakenForACopy() async {
        let board = Board()
        let guarder = makeGuard(board)
        board.count += 1
        guarder.copied()
        guarder.copied() // the protect write's notification
        await guarder.pendingTask?.value
        guarder.copied() // the clear's notification

        #expect(board.protected == 1)
        #expect(board.cleared == 1)
    }

    /// Something else replaced the clipboard before the delay ran out: left alone.
    @Test func aReplacedClipboardIsLeftAlone() async {
        let board = Board()
        let slow = ClipboardGuard(
            changeCount: { board.count },
            protect: { _ in board.count += 1 },
            clear: { board.cleared += 1 },
            sleep: { _ in board.count += 1 }
        )
        board.count += 1
        slow.copied()
        await slow.pendingTask?.value

        #expect(board.cleared == 0)
        #expect(slow.clearedAt == nil)
    }

    /// UIPasteboard can post its change notification inside the write. The guard must not take
    /// its own write for a new copy and recurse.
    @Test func aNotificationInsideItsOwnWriteIsIgnored() async {
        let board = Board()
        var guarder: ClipboardGuard!
        guarder = ClipboardGuard(
            changeCount: { board.count },
            protect: { _ in board.protected += 1; board.count += 1; guarder.copied() },
            clear: { board.cleared += 1; board.count += 1; guarder.copied() },
            sleep: { _ in }
        )
        board.count += 1
        guarder.copied()
        await guarder.pendingTask?.value

        #expect(board.protected == 1)
        #expect(board.cleared == 1)
    }
}
