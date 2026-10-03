import SwiftUI
import UniformTypeIdentifiers

/// Board 15, rows 6.1 and 6.3: restore from the partner, on a new phone or after a reset. Pair
/// again, the partner sends their recovery copy, and this phone's own vault key comes back inside
/// it. Over the nearby connection first, as a file otherwise, like the Partner tab's P2.
struct RestoreView: View {
    let paired: Bool
    let pair: (PairingFlow.Role) -> Void
    let nearby: () -> Void
    @Environment(AppServices.self) private var services
    @State private var opening = false
    @State private var awaits = false
    @State private var alert: RecoveryAlert?
    @State private var choosesRole = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(Copy.restoreBody).foregroundStyle(Theme.Colors.secondary)
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    step(1, Copy.restoreStep1, paired ? Copy.restoreStep1Done : Copy.restoreStep1Todo, done: paired)
                    Divider()
                    step(2, Copy.restoreStep2, Copy.restoreStep2Body, done: false)
                    Divider()
                    step(3, Copy.restoreStep3, Copy.restoreStep3Body, done: false)
                }
                .padding(Theme.Space.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                // Row 6.4: said before anyone tries, not after it fails.
                if !awaits {
                    Text(Copy.nothingWaitsForKey)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                if paired {
                    Button(Copy.getItNearby, action: nearby).buttonStyle(.vaultPrimary)
                    Button(Copy.openRecoveryFile) { opening = true }.buttonStyle(.vaultSecondary)
                } else {
                    Button(Copy.pairWithPartner) { choosesRole = true }.buttonStyle(.vaultPrimary)
                }
                Text(Copy.nothingToRestoreFrom)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.lg)
            .background(Theme.Colors.bg)
        }
        .background(Theme.Colors.bg)
        .navigationTitle(Copy.restoreFromPartner)
        .onAppear { awaits = services.awaitsRestore }
        .fileImporter(isPresented: $opening, allowedContentTypes: [UTType(exportedAs: "tech.neatnet.nvrec")]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            alert = RecoveryAlert.receiving { try services.receiveRecoveryFile(Data(contentsOf: url)) }
            awaits = services.awaitsRestore
        }
        // Here, not on the Partner tab underneath: a dialog asked from a view that is not on top
        // of the navigation stack may never show.
        .confirmationDialog(Copy.whichPhone, isPresented: $choosesRole, titleVisibility: .visible) {
            Button(Copy.showMyCode) { pair(.starter) }
            Button(Copy.scanTheirCodeChoice) { pair(.joiner) }
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button(Copy.ok, role: .cancel) {}
        } message: {
            Text(alert?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: alert) { _, new in new?.restored == true }
    }

    private func step(_ number: Int, _ title: String, _ body: String, done: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.Colors.text)
                Text(body).font(Theme.Typography.footnote).foregroundStyle(Theme.Colors.secondary)
            }
        } icon: {
            Group {
                if done { Image(systemName: "checkmark") } else { Text("\(number)") }
            }
            .font(Theme.Typography.footnote.weight(.semibold))
            .frame(width: 24, height: 24)
            .background(done ? Theme.Colors.accentTint : Theme.Colors.privateBadgeBG, in: Circle())
            .foregroundStyle(done ? Theme.Colors.onAccentTint : Theme.Colors.privateBadgeInk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What opening a recovery file says, from the Files picker here or a file opened from AirDrop,
/// Messages or Files anywhere (row 3.7).
struct RecoveryAlert: Equatable {
    let title: String
    let message: String
    var restored = false

    @MainActor
    static func receiving(_ receive: () throws -> AppServices.RecoveryReceipt) -> RecoveryAlert {
        do {
            switch try receive() {
            case .restored: return RecoveryAlert(title: Copy.vaultRestoredTitle, message: Copy.vaultRestored, restored: true)
            case .kept: return RecoveryAlert(title: Copy.recoverySavedTitle, message: Copy.recoverySaved)
            case .notThisVaultsKey: return RecoveryAlert(title: Copy.vaultNotRestoredTitle, message: Copy.notThisVaultsKey)
            }
        } catch AppServices.PartnerError.notPaired {
            return RecoveryAlert(title: Copy.recoveryNotSavedTitle, message: Copy.recoveryNotPaired)
        } catch Pairing.RecoveryFile.Problem.notForThisPairing {
            return RecoveryAlert(title: Copy.recoveryNotSavedTitle, message: Copy.recoveryNotForThisPairing)
        } catch {
            return RecoveryAlert(title: Copy.recoveryNotSavedTitle, message: Copy.recoveryUnreadable)
        }
    }
}
