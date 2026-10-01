import Foundation
import Testing

@testable import BetweenVault

/// Row 1.12: a line that appears on both surfaces is pinned. Board 2a shows the first two clauses
/// of the web promise line, so changing either surface alone fails here.
struct PromiseLineTests {
    @Test func onboardingShowsTheWebPromiseLine() throws {
        let index = URL(filePath: #filePath)
            .deletingLastPathComponent() // Design
            .deletingLastPathComponent() // BetweenVaultTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository root
            .appending(path: "web/index.html")
        let html = try String(contentsOf: index, encoding: .utf8)
        #expect(html.contains(Copy.promiseHero + " No cloud required."))
    }
}
