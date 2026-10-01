import Foundation

enum Identity {
    /// Persisted key. Renaming it hands the installation a new device ID, which unpairs it, so it
    /// is frozen from the first TestFlight build onward.
    private static let deviceIDKey = "betweenvault.deviceID"

    /// Stable per installation random ID. Never leaves the device except inside exchange packages.
    static func deviceID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIDKey) { return existing }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: deviceIDKey)
        return fresh
    }

    /// A reset makes this installation a new phone: the next read mints a fresh ID.
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: deviceIDKey)
    }
}
