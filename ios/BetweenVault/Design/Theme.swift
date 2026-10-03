import SwiftUI
import UIKit

extension UIColor {
    /// 0xRRGGBB, opaque.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Light and dark pair resolved against the hosting trait collection, so system dark mode,
/// `.preferredColorScheme`, previews and `resolvedColor(with:)` in tests all agree.
private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
}

/// Design tokens from the handoff boards: board 0 "Brand tokens", board 1 "Component library".
/// Values are transcribed, not invented. Anything the boards do not publish is marked `derived`.
///
/// The handoff (Part D item 1) calls for one token source across web and app, so where a token
/// exists on both surfaces `web/styles.css` is authoritative and the hex here is a transcription of
/// it. A value that deliberately departs from web says so and gives the measured reason.
/// `ThemeTests.appAndWebShareTheirTokens` pins the shared ones so the two cannot drift silently.
///
/// Members are computed `static var` on purpose: under `SWIFT_STRICT_CONCURRENCY: complete`
/// a `static let` holding a type Swift cannot prove `Sendable` is a diagnostic.
enum Theme {
    enum Colors {
        static var bg: Color { dyn(0xFA_FAF8, 0x0F_1112) }
        /// Board 1: the lock screen stays dark in both modes.
        static var lockScreen: Color { dyn(0x0F_1A1A, 0x0F_1A1A) }
        /// The vault mark's two strokes, as on board 1, the app icon and web/favicon.svg.
        static var markTeal: Color { dyn(0x5C_C2B8, 0x5C_C2B8) }
        static var markLight: Color { dyn(0xF4_F4F2, 0xF4_F4F2) }
        /// Boards 2e and 1a: the passcode keypad keys and the empty digit ring.
        static var keypadKey: Color { dyn(0xE4_E6E7, 0x1E_2A2A) }
        static var digitRing: Color { dyn(0x8E_9398, 0x9B_A1A7) }
        /// Board 1a: the wrong passcode line, amber in the dark lock screen.
        static var warning: Color { dyn(0x7A_4E00, 0xF2_C572) }
        static var surface: Color { dyn(0xFF_FFFF, 0x1B_1E20) }
        static var text: Color { dyn(0x15_171A, 0xEC_EDEE) }
        static var secondary: Color { dyn(0x5B_6066, 0x9B_A1A7) }
        /// derived: light has no tertiary ink, reuse secondary
        static var tertiary: Color { dyn(0x5B_6066, 0x8A_9096) }
        /// `--border`: hairline separators
        static var hairline: Color { dyn(0xE4_E5E3, 0x2A_2D30) }
        static var borderStrong: Color { dyn(0x8E_9398, 0x6B_7076) }

        static var accent: Color { dyn(0x0E_6B66, 0x4F_B8AE) }
        /// derived (no board draws it; the owner asked for it in cycle 5): notes that came from the
        /// partner. Violet, apart from the teal accent and the amber Sealed badge. About 6.5:1 on the
        /// light surface and 8:1 on the dark one, so it also carries text.
        static var partner: Color { dyn(0x6B_4FA3, 0xB7_A2E8) }
        /// `--accent-hover`
        static var accentPressed: Color { dyn(0x09_4C48, 0xA8_E4DD) }
        static var accentTint: Color { dyn(0xDD_F0EE, 0x1E_2A2A) }
        /// `--accent-on-tint`: ink that reads on the accent tint
        static var onAccentTint: Color { dyn(0x0B_5F5A, 0x7E_D3CA) }
        /// `--on-accent`: ink on the accent fill
        static var onAccent: Color { dyn(0xFF_FFFF, 0x0F_1A1A) }

        /// `--error`. Board 1 specifies #B3261E for both modes, but measured against our own
        /// backgrounds that is 2.90:1 on dark bg #0F1112 and 2.56:1 on dark surface #1B1E20, far
        /// below AA, and destructive is text only. Both modes therefore follow web instead:
        /// #A1231B is 7.17:1 on light bg #FAFAF8, #FF8A80 is 8.30:1 on dark bg #0F1112.
        static var destructive: Color { dyn(0xA1_231B, 0xFF_8A80) }
        /// derived: dark publishes no disabled fill, use the dark border
        static var disabledFill: Color { dyn(0xD5_D8DA, 0x2A_2D30) }
        /// derived: ink for disabled controls
        static var disabledInk: Color { dyn(0x6B_7076, 0x6B_7076) }

        /// `--badge-fill` / `--badge-ink`: the neutral badge, reused for Private.
        static var privateBadgeBG: Color { dyn(0xEC_EDEF, 0x2A_2D30) }
        static var privateBadgeInk: Color { dyn(0x45_4A50, 0xC9_CDD1) }
        static var sealedBadgeBG: Color { dyn(0xFB_EFD6, 0x3A_2A0C) }
        static var sealedBadgeInk: Color { dyn(0x7A_4E00, 0xF2_C572) }
        static var sharedBadgeBG: Color { dyn(0xDD_F0EE, 0x12_3532) }
        static var sharedBadgeInk: Color { dyn(0x0B_5F5A, 0x7E_D3CA) }
        static var changedFlagBG: Color { dyn(0xFB_F6EA, 0x3A_2A0C) }
        /// Board F2's "Sent · not confirmed" ring: #7FBDB6 on light; derived for dark from the
        /// Shared ink so it keeps its contrast there.
        static var sentNotConfirmedRing: Color { dyn(0x7F_BDB6, 0x4F_8F89) }
        static var changedFlagInk: Color { dyn(0x4A_3500, 0xD9_B56A) }
    }

    /// The full board scale. `xl` and above are unused so far and kept deliberately: the scale is
    /// the deliverable, not the subset cycle 1 happened to need.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 72
    }

    enum Radius {
        /// Board publishes 14 for the app. Used by buttons, sheets, and cards.
        /// (`--radius-control` 10 and `--radius-card` 12 are web only, so they are not mirrored here.)
        static let panel: CGFloat = 14
        /// derived: pill for toasts
        static let toast: CGFloat = 30
    }

    /// Semantic styles only, so Dynamic Type scales to the accessibility sizes for free.
    /// At the default content size these are SF Pro 34 / 22 / 20 / 17 / 13, which is exactly
    /// the board scale.
    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title2 = Font.title2.weight(.bold)
        static let title3 = Font.title3.weight(.semibold)
        static let body = Font.body
        static let footnote = Font.footnote
        /// Board 4 previews: 15px
        static let subheadline = Font.subheadline
        /// Board says 12 semibold. 13 is the nearest semantic style and keeps Dynamic Type.
        static let badge = Font.footnote.weight(.semibold)
        /// Board "Hero only": the serif line used on the lock screen and onboarding
        /// ("Shared by choice."). New York serif, large title size.
        static let hero = Font.system(.largeTitle, design: .serif).weight(.semibold)
    }
}
