import UIKit

/// Settings > Appearance. The handoff's default is the system setting; Light and Dark override it
/// for this app only. Every token in Theme already has both values, so this only picks one.
/// The lock screen stays dark in every choice, as board 1 draws it.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// Persisted key; renaming it resets the choice to System.
    static let storageKey = "betweenvault.appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: Copy.appearanceSystem
        case .light: Copy.appearanceLight
        case .dark: Copy.appearanceDark
        }
    }

    /// Set on the app window, so sheets, alerts and the share sheet follow it too.
    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
