import SwiftUI

/// Over the tabs while the App Store has a newer version. Dismissing it silences that version only.
struct UpdateBanner: View {
    let version: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(Copy.updateAvailable(version))
                    .font(Theme.Typography.body.weight(.semibold))
                Text(Copy.updateBody)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Link(Copy.update, destination: UpdateNotice.storeURL)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.Colors.secondary)
            }
            .accessibilityLabel(Copy.dismissUpdate)
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.md)
        .background(Theme.Colors.surface)
        .overlay(alignment: .bottom) { Theme.Colors.hairline.frame(height: 1) }
    }
}
