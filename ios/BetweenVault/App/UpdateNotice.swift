import Foundation
import Observation

/// Tells the owner a newer version is on the App Store. This is the app's only internet request:
/// one GET to Apple's lookup service, about once a day, while the vault is open. Nothing that
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
    /// After a failed ask: tried again in an hour, so a lookup that keeps failing is not asked at
    /// every unlock.
    private static let retryAfter: TimeInterval = 3600

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

    /// Asks Apple unless it asked in the last day, then sets `available`. A failed ask (offline,
    /// an error, an answer that is no version) changes nothing and is tried again in an hour. A
    /// last check dated in the future (a clock moved back) counts as due, so the day can never be
    /// stretched.
    func check(now: Date = .now) async {
        if let last = defaults.object(forKey: Keys.checkedAt) as? Date, last <= now, now.timeIntervalSince(last) < Self.interval {
            return
        }
        let latest = await fetch()
        // Locked or backgrounded meanwhile: the ask was cut short, not answered.
        guard !Task.isCancelled else { return }
        guard let latest else {
            defaults.set(now.addingTimeInterval(Self.retryAfter - Self.interval), forKey: Keys.checkedAt)
            return
        }
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

    /// Numeric per part, padded with zeros, so 1.0.10 is newer than 1.0.9 and 1.0.0 is not newer
    /// than 1.0. An unknown current version offers nothing.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
        var (new, old) = (parts(latest), parts(current))
        guard !old.isEmpty else { return false }
        let length = max(new.count, old.count)
        new += Array(repeating: 0, count: length - new.count)
        old += Array(repeating: 0, count: length - old.count)
        return old.lexicographicallyPrecedes(new)
    }

    /// `results[0].version` from the lookup answer, only if it looks like a version (digits and
    /// dots), because it is shown on screen, and only if this iOS can install it: an owner who
    /// cannot update is not nagged to.
    nonisolated static func latestVersion(
        in data: Data, osVersion: String = ProcessInfo.processInfo.operatingSystemVersion.formatted
    ) -> String? {
        struct Answer: Decodable {
            struct Item: Decodable {
                let version: String
                let minimumOsVersion: String?
            }
            let results: [Item]
        }
        guard let item = (try? JSONDecoder().decode(Answer.self, from: data))?.results.first,
              !isNewer(item.minimumOsVersion ?? "0", than: osVersion)
        else { return nil }
        let version = item.version
        guard version.count <= 14,
              version.split(separator: ".", omittingEmptySubsequences: false)
                  .allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        return version
    }

    @Sendable nonisolated static func lookup() async -> String? {
        // Ephemeral: no cookies, no cache, nothing written to disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: lookupURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return latestVersion(in: data)
    }
}

private extension OperatingSystemVersion {
    var formatted: String { "\(majorVersion).\(minorVersion).\(patchVersion)" }
}
