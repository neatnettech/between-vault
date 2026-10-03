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

    /// Settings > License reads a copy of the GPLv3 bundled with the app (board 17d). It lives
    /// inside ios/ because a file outside it gets machine dependent IDs in the generated project;
    /// this keeps the copy identical to the repository's LICENSE.
    @Test func theBundledLicenseIsTheRepositoryLicense() throws {
        let ios = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundled = try Data(contentsOf: ios.appending(path: "BetweenVault/Resources/LICENSE.txt"))
        let repository = try Data(contentsOf: ios.deletingLastPathComponent().appending(path: "LICENSE"))
        #expect(bundled == repository)
    }
}
