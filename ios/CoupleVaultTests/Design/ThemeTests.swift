import SwiftUI
import Testing
import UIKit

@testable import CoupleVault

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
}
