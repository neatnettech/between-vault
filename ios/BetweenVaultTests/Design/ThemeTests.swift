import SwiftUI
import Testing
import UIKit

@testable import BetweenVault

@MainActor
struct ThemeTests {
    @Test func hexInitMapsChannels() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(hex: 0x0E_6B66).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(Int((red * 255).rounded()) == 0x0E)
        #expect(Int((green * 255).rounded()) == 0x6B)
        #expect(Int((blue * 255).rounded()) == 0x66)
        #expect(alpha == 1)
    }

    /// The handoff (Part D item 1) asks for one token source across web and app. The app cannot read
    /// `web/styles.css` at runtime, so this is a second transcription of it: change one surface and
    /// this test fails, which is the whole point. Hexes below are `web/styles.css` `:root` (light)
    /// and the `prefers-color-scheme: dark` block, in file order.
    @Test func appAndWebShareTheirTokens() {
        let shared: [(name: String, token: Color, light: UInt32, dark: UInt32)] = [
            ("--bg", Theme.Colors.bg, 0xFA_FAF8, 0x0F_1112),
            ("--surface", Theme.Colors.surface, 0xFF_FFFF, 0x1B_1E20),
            ("--text", Theme.Colors.text, 0x15_171A, 0xEC_EDEE),
            ("--secondary", Theme.Colors.secondary, 0x5B_6066, 0x9B_A1A7),
            ("--badge-fill", Theme.Colors.privateBadgeBG, 0xEC_EDEF, 0x2A_2D30),
            ("--badge-ink", Theme.Colors.privateBadgeInk, 0x45_4A50, 0xC9_CDD1),
            ("--accent", Theme.Colors.accent, 0x0E_6B66, 0x4F_B8AE),
            ("--accent-hover", Theme.Colors.accentPressed, 0x09_4C48, 0xA8_E4DD),
            ("--accent-tint", Theme.Colors.accentTint, 0xDD_F0EE, 0x1E_2A2A),
            ("--accent-on-tint", Theme.Colors.onAccentTint, 0x0B_5F5A, 0x7E_D3CA),
            ("--on-accent", Theme.Colors.onAccent, 0xFF_FFFF, 0x0F_1A1A),
            ("--border", Theme.Colors.hairline, 0xE4_E5E3, 0x2A_2D30),
            ("--border-strong", Theme.Colors.borderStrong, 0x8E_9398, 0x6B_7076),
            ("--error", Theme.Colors.destructive, 0xA1_231B, 0xFF_8A80),
        ]

        for entry in shared {
            let resolved = UIColor(entry.token)
            #expect(
                resolved.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                    == UIColor(hex: entry.light),
                "\(entry.name) light drifted from web/styles.css"
            )
            #expect(
                resolved.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                    == UIColor(hex: entry.dark),
                "\(entry.name) dark drifted from web/styles.css"
            )
        }
    }

    /// Proves the whole light and dark token mechanism, not just the accent.
    @Test func accentResolvesPerColorScheme() {
        let accent = UIColor(Theme.Colors.accent)

        #expect(accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            == UIColor(hex: 0x0E_6B66))
        #expect(accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            == UIColor(hex: 0x4F_B8AE))
    }

    @Test(arguments: NoteState.allCases)
    func badgeSpecHasWordIconAndLabel(state: NoteState) {
        let spec = StateBadge.spec(for: state, changedSinceSent: false)

        #expect(!spec.word.isEmpty)
        #expect(!spec.symbol.isEmpty)
        #expect(spec.voiceOver.hasPrefix("State: "))
    }

    @Test func changedFlagOnlyAffectsShared() {
        #expect(
            StateBadge.spec(for: .shared, changedSinceSent: true).voiceOver
                == "State: Shared. Changed since you sent it."
        )
        #expect(
            StateBadge.spec(for: .private, changedSinceSent: true)
                == StateBadge.spec(for: .private, changedSinceSent: false)
        )
        #expect(
            StateBadge.spec(for: .sealed, changedSinceSent: true)
                == StateBadge.spec(for: .sealed, changedSinceSent: false)
        )
    }

    /// Board 1: the Sealed badge reads the full helper to VoiceOver users.
    @Test func sealedBadgeLabelMatchesTheBoard() {
        #expect(
            StateBadge.spec(for: .sealed, changedSinceSent: false).voiceOver
                == "State: Sealed. Ready to send to your partner."
        )
    }
}
