import SwiftUI

/// Settings > About: the in-app statements, with links to the full versions on the web.
enum AboutLinks {
    static let privacyPolicy = URL(string: "https://neatnettech.github.io/between-vault/privacy.html")!
    static let threatModel = URL(string: "https://github.com/neatnettech/between-vault#threat-model")!
    static let sourceCode = URL(string: "https://github.com/neatnettech/between-vault")!
    /// Apple's standard EULA, which applies to an app without its own (owner request: terms of use).
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Privacy policy: the app's own, short statement, and the full policy on the website.
struct PrivacyStatementView: View {
    var body: some View {
        AboutPage(title: Copy.privacyPolicy) {
            ForEach(Copy.privacyStatement, id: \.self) { Text($0) }
            Text(Copy.privacyWebsiteNote).foregroundStyle(Theme.Colors.secondary)
            Link(destination: AboutLinks.privacyPolicy) { Label(Copy.fullPrivacyPolicy, systemImage: "arrow.up.right.square") }
        }
    }
}

/// Board 17e.
struct ThreatModelView: View {
    var body: some View {
        AboutPage(title: Copy.threatModelTitle) {
            list(Copy.protectsAgainst, Copy.protectsList, systemImage: "checkmark.shield")
            list(Copy.doesNotProtect, Copy.doesNotProtectList, systemImage: "exclamationmark.triangle")
            Link(destination: AboutLinks.threatModel) { Label(Copy.fullThreatModel, systemImage: "arrow.up.right.square") }
        }
    }

    private func list(_ title: String, _ items: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title).font(Theme.Typography.title3).accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: systemImage).foregroundStyle(Theme.Colors.text)
            }
        }
    }
}

/// Board 17d.
struct LicenseView: View {
    var body: some View {
        AboutPage(title: Copy.license) {
            Text(Copy.licenseIntro)
            Text(Copy.inPlainWords.uppercased())
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Copy.licensePlain, id: \.self) { Label($0, systemImage: "checkmark").foregroundStyle(Theme.Colors.text) }
            VStack(spacing: Theme.Space.sm) {
                NavigationLink { FullLicenseView() } label: {
                    LabeledContent(Copy.fullLicenseText, value: Copy.offline)
                }
                Divider()
                NavigationLink { AboutPage(title: Copy.thirdPartyNotices) { Text(Copy.thirdPartyNone) } } label: {
                    Text(Copy.thirdPartyNotices).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Link(destination: AboutLinks.sourceCode) { Label(Copy.sourceCode, systemImage: "arrow.up.right.square") }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Space.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            Text(Copy.licenseFootnote).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
        }
    }
}

/// The GPLv3 text bundled with the app, readable offline.
private struct FullLicenseView: View {
    private var text: String {
        Bundle.main.url(forResource: "LICENSE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.fullLicenseText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Terms of use: owner request, no board. A free app with no account and no service is covered by
/// Apple's standard licence agreement.
struct TermsView: View {
    var body: some View {
        AboutPage(title: Copy.termsOfUse) {
            ForEach(Copy.termsBody, id: \.self) { Text($0) }
            Link(destination: AboutLinks.appleEULA) { Label(Copy.appleStandardEULA, systemImage: "arrow.up.right.square") }
        }
    }
}

/// A plain reading page for the About screens.
private struct AboutPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) { content }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(title)
    }
}
