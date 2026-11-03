import SwiftUI

struct RootView: View {
    @Environment(UpdateNotice.self) private var updateNotice
    @Environment(LockManager.self) private var lockManager
    @Environment(\.openURL) private var openURL
    @State private var tab: AppTab = .vault
    @State private var showsUpdate = false
    /// The version already offered since launch, so locking and unlocking do not ask again.
    @State private var offered: String?

    /// A newer version, offered only with the vault open.
    private var update: String? { lockManager.isLocked ? nil : updateNotice.available }

    var body: some View {
        TabView(selection: $tab) {
            VaultView()
                .tabItem { Label(Copy.tabVault, systemImage: "tray.full") }
                .tag(AppTab.vault)

            ExchangeView(onPaired: { tab = .partner })
                .tabItem { Label(Copy.tabExchange, systemImage: "arrow.left.arrow.right") }
                .tag(AppTab.exchange)

            PartnerView()
                .tabItem { Label(Copy.tabPartner, systemImage: "person.2") }
                .tag(AppTab.partner)

            SettingsView()
                .tabItem { Label(Copy.tabSettings, systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.Colors.accent)
        .onChange(of: update, initial: true) { _, version in
            guard let version, version != offered else { return }
            offered = version
            showsUpdate = true
        }
        // "Update" leaves the alert to come back at the next launch; "Not now" silences that version.
        .alert(Copy.updateAvailable(offered ?? ""), isPresented: $showsUpdate) {
            Button(Copy.update) { openURL(UpdateNotice.storeURL) }
            Button(Copy.dismissUpdate, role: .cancel) { updateNotice.dismiss() }
        } message: {
            Text(Copy.updateBody)
        }
    }
}

enum AppTab: Hashable {
    case vault
    case exchange
    case partner
    case settings
}
