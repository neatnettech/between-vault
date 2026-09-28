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
/// Members are computed `static var` on purpose: under `SWIFT_STRICT_CONCURRENCY: complete`
/// a `static let` holding a type Swift cannot prove `Sendable` is a diagnostic.
enum Theme {
    enum Colors {
        static var bg: Color { dyn(0xFA_FAF8, 0x0F_1112) }
        static var surface: Color { dyn(0xFF_FFFF, 0x1B_1E20) }
        /// derived: light has no band token, reuse bg
        static var band: Color { dyn(0xFA_FAF8, 0x15_1719) }
        static var text: Color { dyn(0x15_171A, 0xEC_EDEE) }
        /// derived: dark publishes no separate body ink
        static var bodyInk: Color { dyn(0x2B_2F33, 0xEC_EDEE) }
        static var secondary: Color { dyn(0x5B_6066, 0x9B_A1A7) }
        /// derived: light has no tertiary ink, reuse secondary
        static var tertiary: Color { dyn(0x5B_6066, 0x8A_9096) }
        /// derived: hairline separators, between the board's bg and surface
        static var hairline: Color { dyn(0xE4_E5E3, 0x2A_2D30) }
        /// derived: strong borders on the secondary button
        static var borderStrong: Color { dyn(0x8E_9398, 0x6B_7076) }

        static var accent: Color { dyn(0x0E_6B66, 0x4F_B8AE) }
        /// derived: dark publishes no accent hover, use the bright accent step
        static var accentPressed: Color { dyn(0x09_4C48, 0x7E_D3CA) }
        /// derived: accent fill for secondary buttons
        static var accentTint: Color { dyn(0xDD_F0EE, 0x1E_2A2A) }
        /// derived: ink that reads on the accent tint
        static var onAccentTint: Color { dyn(0x0B_5F5A, 0x7E_D3CA) }
        /// derived: ink on the accent fill
        static var onAccent: Color { dyn(0xFF_FFFF, 0x0F_1A1A) }
        /// derived: the favicon's dark teal panel, for dark fills in both modes
        static var panel: Color { dyn(0x0F_1A1A, 0x0F_1A1A) }

        /// Board 1 specifies #B3261E for both modes, but that is ~4.0:1 on the dark background,
        /// below AA for text, and destructive is text only. Dark uses the lightened red for ~8:1,
        /// the same swap `web/styles.css` makes for `--error`.
        static var destructive: Color { dyn(0xB3_261E, 0xF2_B8B5) }
        /// derived: dark publishes no destructive tint
        static var destructiveTint: Color { dyn(0xE8_CCC9, 0x5A_3A38) }
        /// derived: dark publishes no disabled fill, use the dark border
        static var disabledFill: Color { dyn(0xD5_D8DA, 0x2A_2D30) }
        /// derived: ink for disabled controls
        static var disabledInk: Color { dyn(0x6B_7076, 0x6B_7076) }

        /// derived: badge backgrounds and inks (board shows the badges but publishes no hex)
        static var privateBadgeBG: Color { dyn(0xEC_EDEF, 0x26_292C) }
        static var privateBadgeInk: Color { dyn(0x45_4A50, 0xC3_C7CB) }
        static var sealedBadgeBG: Color { dyn(0xFB_EFD6, 0x3A_2A0C) }
        static var sealedBadgeInk: Color { dyn(0x7A_4E00, 0xF2_C572) }
        static var sharedBadgeBG: Color { dyn(0xDD_F0EE, 0x12_3532) }
        static var sharedBadgeInk: Color { dyn(0x0B_5F5A, 0x7E_D3CA) }
        static var changedFlagBG: Color { dyn(0xFB_F6EA, 0x3A_2A0C) }
        static var changedFlagInk: Color { dyn(0x4A_3500, 0xD9_B56A) }
    }

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
        /// Board publishes 10 for web only. Not used by the app.
        static let control: CGFloat = 10
        /// derived: between control and panel, for cards
        static let card: CGFloat = 12
        /// Board publishes 14 for the app. Used by buttons, sheets, and cards.
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
        /// Board says 12 semibold. 13 is the nearest semantic style and keeps Dynamic Type.
        static let badge = Font.footnote.weight(.semibold)
        /// Board "Hero only": the serif line used on the lock screen and onboarding
        /// ("Shared by choice."). New York serif, large title size.
        static let hero = Font.system(.largeTitle, design: .serif).weight(.semibold)
    }
}
