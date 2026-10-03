import SwiftUI
import UIKit

/// The two icons from the "App icon concepts" board, chosen in Settings (free for everyone).
/// The interlocking shapes are the default and the board's recommendation; the keyhole is the
/// one alternate. iOS shows its own confirmation when the icon changes.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case interlocking
    case keyhole

    var id: Self { self }

    /// `nil` is the primary icon; the other names are alternate icon sets in the asset catalog.
    var alternateName: String? {
        switch self {
        case .interlocking: nil
        case .keyhole: "AppIconKeyhole"
        }
    }

    var preview: String {
        switch self {
        case .interlocking: "IconPreviewInterlocking"
        case .keyhole: "IconPreviewKeyhole"
        }
    }

    var title: String {
        switch self {
        case .interlocking: Copy.iconTwoOfYou
        case .keyhole: Copy.iconVaultDoor
        }
    }

    @MainActor static var current: AppIconChoice {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .interlocking
    }
}

struct AppIconPicker: View {
    @State private var selected = AppIconChoice.current
    @State private var failed = false

    var body: some View {
        List {
            Section {
                ForEach(AppIconChoice.allCases) { choice in
                    Button { choose(choice) } label: {
                        HStack(spacing: Theme.Space.md) {
                            Image(choice.preview)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                                .accessibilityHidden(true)
                            Text(choice.title).foregroundStyle(Theme.Colors.text)
                            Spacer()
                            if choice == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(choice == selected ? .isSelected : [])
                }
            } footer: {
                if failed {
                    Label(Copy.iconNotChanged, systemImage: "exclamationmark.triangle")
                } else {
                    Text(Copy.iconFooter)
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.appIcon)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            Task { @MainActor in
                if error == nil {
                    selected = choice
                    failed = false
                } else {
                    failed = true
                    AccessibilityNotification.Announcement(Copy.iconNotChanged).post()
                }
            }
        }
    }
}
