import Observation
import UIKit

/// Row 2.6, spec "Clipboard": whatever is copied inside the app is cleared after 60 s. The app has
/// no copy button of its own; copying happens through the system text menu in the editor, so the
/// guard listens for any change this app makes to the clipboard.
@MainActor
@Observable
final class ClipboardGuard {
    static let delay: Duration = .seconds(60)

    /// Set when a clear happened, for the "Clipboard cleared" toast.
    private(set) var clearedAt: Date?

    @ObservationIgnored private let changeCount: () -> Int
    @ObservationIgnored private let protect: (Duration) -> Void
    @ObservationIgnored private let clear: () -> Void
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// The clipboard as this guard last wrote it, so its own writes are not taken for a copy.
    @ObservationIgnored private var ownCount: Int?
    /// Set during the guard's own writes: posted on the main queue, their notification can arrive
    /// inside the write, before `ownCount` knows about it.
    @ObservationIgnored private var writing = false

    /// Parameters only so a test can hand in its own clipboard and clock.
    init(
        changeCount: @escaping () -> Int = { UIPasteboard.general.changeCount },
        protect: @escaping (Duration) -> Void = { delay in
            // Re-set what was just copied with an expiry the system enforces even while the app is
            // suspended, and keep it off Universal Clipboard. Reading our own copy never prompts.
            let board = UIPasteboard.general
            board.setItems(board.items, options: [
                .expirationDate: Date.now.addingTimeInterval(TimeInterval(delay.components.seconds)),
                .localOnly: true,
            ])
        },
        clear: @escaping () -> Void = { UIPasteboard.general.items = [] },
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.changeCount = changeCount
        self.protect = protect
        self.clear = clear
        self.sleep = sleep
    }

    func observe() {
        NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.copied() }
        }
    }

    /// Something was copied in the app. The system expires it after the delay even if the app is
    /// suspended; while the app runs, the guard clears it on time and says so. A newer copy starts
    /// the delay over; something else replacing it is left alone.
    func copied() {
        guard !writing, changeCount() != ownCount else { return }
        pending?.cancel()
        writing = true
        protect(Self.delay)
        writing = false
        let count = changeCount()
        ownCount = count
        pending = Task { [sleep] in
            await sleep(Self.delay)
            guard !Task.isCancelled, changeCount() == count else { return }
            writing = true
            clear()
            writing = false
            ownCount = changeCount()
            clearedAt = .now
        }
    }

    /// The pending clear, for tests.
    var pendingTask: Task<Void, Never>? { pending }
}
