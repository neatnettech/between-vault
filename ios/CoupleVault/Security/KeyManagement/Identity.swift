import Foundation

enum Identity {
    private static let deviceIDKey = "pcv.deviceID"

    /// Stable per installation random ID. Never leaves the device except inside exchange packages.
    static func deviceID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIDKey) { return existing }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: deviceIDKey)
        return fresh
    }
}
