import SwiftUI

struct RootView: View {
    @State private var tab: AppTab = .vault

    var body: some View {
        TabView(selection: $tab) {
            VaultView()
                .tabItem { Label("Vault", systemImage: "tray.full") }
                .tag(AppTab.vault)

            ExchangeView()
                .tabItem { Label("Exchange", systemImage: "arrow.left.arrow.right") }
                .tag(AppTab.exchange)

            PartnerView()
                .tabItem { Label("Partner", systemImage: "person.2") }
                .tag(AppTab.partner)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.Colors.accent)
    }
}

enum AppTab: Hashable {
    case vault
    case exchange
    case partner
    case settings
}
