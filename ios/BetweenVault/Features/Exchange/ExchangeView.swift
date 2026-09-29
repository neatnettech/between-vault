import SwiftUI

struct ExchangeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(Copy.readyToSend) {
                    EmptyState(
                        systemImage: "tray",
                        headline: Copy.nothingSealedYet,
                        message: Copy.sealANote
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
                Section(Copy.waitingForMe) {
                    EmptyState(
                        systemImage: "tray.and.arrow.down",
                        headline: Copy.nothingWaiting,
                        message: Copy.openPartnerFile
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
                Section(Copy.recentlyExchanged) {
                    EmptyState(
                        systemImage: "clock.arrow.circlepath",
                        headline: Copy.noExchangesYet,
                        message: Copy.exchangeHistoryHint
                    )
                    .listRowBackground(Theme.Colors.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bg)
            .navigationTitle(Copy.tabExchange)
        }
    }
}
