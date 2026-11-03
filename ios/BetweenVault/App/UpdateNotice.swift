import Foundation
import Observation

/// Tells the owner a newer version is on the App Store. This is the app's only internet request:
/// one GET to Apple's lookup service, at most once a day, while the vault is open. Nothing that
/// identifies the owner or the vault is sent. Only three values are kept (when it last asked, the
/// newest version it saw, the one the owner dismissed), none of them secret.
///
/// ponytail: a soft nudge. Lookup cannot say "this version is too old", so nothing here blocks the
/// app; a self hosted version file would, if a fix ever must be forced.
@MainActor
@Observable
final class UpdateNotice {
    static let storeURL = URL(string: "https://apps.apple.com/app/id6818837797")!
    private static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=6818837797")!
    private static let interval: TimeInterval = 24 * 3600

    /// Persisted keys; renaming one forgets that value.
    private enum Keys {
        static let checkedAt = "betweenvault.update.checkedAt"
        static let latest = "betweenvault.update.latest"
        static let dismissed = "betweenvault.update.dismissed"
    }

    /// The newer version to offer, or nil: up to date, dismissed, or never asked.
    private(set) var available: String?

    private let defaults: UserDefaults
    private let current: String
    private let fetch: @Sendable () async -> String?

    init(
        defaults: UserDefaults = .standard,
        current: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        fetch: @escaping @Sendable () async -> String? = UpdateNotice.lookup
    ) {
        self.defaults = defaults
        self.current = current
        self.fetch = fetch
        refresh()
    }

    /// Asks Apple unless it asked in the last day, then sets `available`. A failed ask changes
    /// nothing and is tried again at the next unlock. A last check dated in the future (a clock
    /// moved back) counts as due, so the day can never be stretched.
    func check(now: Date = .now) async {
        if let last = defaults.object(forKey: Keys.checkedAt) as? Date, last <= now, now.timeIntervalSince(last) < Self.interval {
            return
        }
        guard let latest = await fetch() else { return }
        defaults.set(now, forKey: Keys.checkedAt)
        defaults.set(latest, forKey: Keys.latest)
        refresh()
    }

    /// "Not now": quiet until a still newer version appears.
    func dismiss() {
        guard let available else { return }
        defaults.set(available, forKey: Keys.dismissed)
        refresh()
    }

    private func refresh() {
        guard let latest = defaults.string(forKey: Keys.latest),
              Self.isNewer(latest, than: current),
              latest != defaults.string(forKey: Keys.dismissed)
        else {
            available = nil
            return
        }
        available = latest
    }

    /// Numeric per part, so 1.0.10 is newer than 1.0.9. An unknown current version offers nothing.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        !current.isEmpty && latest.compare(current, options: .numeric) == .orderedDescending
    }

    /// `results[0].version` from the lookup answer, only if it looks like a version (digits and
    /// dots), because it is shown on screen.
    nonisolated static func latestVersion(in data: Data) -> String? {
        struct Answer: Decodable {
            struct Item: Decodable { let version: String }
            let results: [Item]
        }
        guard let version = (try? JSONDecoder().decode(Answer.self, from: data))?.results.first?.version,
              version.count <= 14,
              version.split(separator: ".", omittingEmptySubsequences: false)
                  .allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        return version
    }

    @Sendable nonisolated static func lookup() async -> String? {
        // Ephemeral: no cookies, no cache, nothing written to disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        guard let (data, response) = try? await URLSession(configuration: configuration).data(from: lookupURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return latestVersion(in: data)
    }
}
