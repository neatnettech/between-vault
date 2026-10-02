import SwiftData
import SwiftUI

@main
struct BetweenVaultApp: App {
    @State private var services: AppServices?
    @State private var lockManager = LockManager()
    @State private var cover = CoverWindow()
    @State private var clipboard = ClipboardGuard()
    @State private var showsClipboardToast = false
    /// A file opened from AirDrop, Messages or Files, held until the vault is open (row 3.7).
    @State private var openedFile: URL?
    /// Row 5.2 toast: "N items imported".
    @State private var importedCount: Int?
    /// Row 2.2: onboarding is shown once. Frozen key, like the other persisted names.
    @AppStorage(LockManager.onboardedKey) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _services = State(initialValue: try? AppServices())
    }

    /// The cover and the launch prompt apply once the vault exists, and before onboarding too when
    /// it already holds notes (rc.1, a flag lost in a restore): the flag alone must never take the
    /// lock off a vault that holds something. Then Face ID opens onboarding, which sets the passcode.
    private var guarded: Bool { onboarded || services?.guardsOnboarding ?? true }
    private var covered: Bool { guarded && lockManager.isLocked }

    /// Row 5.1: a package from the partner. Checked first (9a to 9d), then reviewed (9, U4); the
    /// file itself is read once here and nothing else keeps it.
    private func receivePackage(_ url: URL, services: AppServices) {
        let content: ImportReviewView.Content
        do {
            content = .review(try services.importService.inspect(Data(contentsOf: url)))
        } catch let failure as ImportService.ImportFailure {
            content = .failed(failure)
        } catch {
            content = .failed(.damaged)
        }
        cover.present(
            ImportReviewView(content: content) { imported in
                cover.dismissScreen()
                withAnimation { importedCount = imported }
            }
            .environment(services)
            .environment(lockManager)
        )
    }

    /// Row 3.7: a recovery file from the partner. Only once the vault is open and onboarded, so a
    /// file opened onto the lock screen waits for the owner. Exchange packages arrive with 5.1.
    private func receiveOpenedFile() {
        guard let url = openedFile, onboarded, !covered, let services else { return }
        openedFile = nil
        // AirDrop and Messages hand the app its own copy in Documents/Inbox: it goes on every path,
        // so no copy of a wrapped key stays on disk. A file opened in place from Files is left alone.
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory).standardizedFileURL.path
        defer { if url.standardizedFileURL.path.hasPrefix(inbox) { try? FileManager.default.removeItem(at: url) } }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension == PackageSerializer.fileExtension {
            receivePackage(url, services: services)
            return
        }
        // Never silent: found on two phones, a file the app did not handle looked like nothing
        // happened at all.
        guard url.pathExtension == Pairing.RecoveryFile.fileExtension else {
            cover.alert(Copy.cantBeOpened, Copy.unknownFile)
            return
        }
        do {
            try services.receiveRecoveryFile(Data(contentsOf: url))
            cover.alert(Copy.recoverySavedTitle, Copy.recoverySaved)
        } catch AppServices.PartnerError.notPaired {
            cover.alert(Copy.recoveryNotSavedTitle, Copy.recoveryNotPaired)
        } catch Pairing.RecoveryFile.Problem.notForThisPairing {
            cover.alert(Copy.recoveryNotSavedTitle, Copy.recoveryNotForThisPairing)
        } catch {
            cover.alert(Copy.recoveryNotSavedTitle, Copy.recoveryUnreadable)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboarded {
                    OnboardingView(lockManager: lockManager) { onboarded = true }
                } else if let services {
                    RootView()
                        .environment(services)
                        .modelContainer(services.container)
                } else {
                    ContentUnavailableView(
                        Copy.vaultUnavailable,
                        systemImage: "exclamationmark.triangle",
                        description: Text(Copy.storeCouldNotOpen)
                    )
                }
            }
            .environment(lockManager)
            // The lock screen itself is in the cover window. This plain shield only spares the
            // first frame at launch, before that window exists.
            .overlay {
                if covered { Theme.Colors.lockScreen.ignoresSafeArea() }
            }
            // Row 2.6: counts only, never content.
            .overlay(alignment: .bottom) {
                if showsClipboardToast, !covered {
                    Toast(systemImage: "doc.on.clipboard", text: Copy.toastClipboardCleared)
                        .padding(.bottom, Theme.Space.xxxl)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let importedCount, !covered {
                    Toast(systemImage: "tray.and.arrow.down", text: Copy.itemsImported(importedCount))
                        .padding(.bottom, Theme.Space.xxxl)
                        .transition(.opacity)
                }
            }
            // Handoff C8: success on import.
            .sensoryFeedback(.success, trigger: importedCount) { _, new in new != nil }
            .task(id: importedCount) {
                guard let importedCount else { return }
                AccessibilityNotification.Announcement(Copy.itemsImported(importedCount)).post()
                try? await Task.sleep(for: .seconds(2))
                withAnimation { self.importedCount = nil }
            }
            .onChange(of: clipboard.clearedAt) {
                AccessibilityNotification.Announcement(Copy.toastClipboardCleared).post()
                withAnimation { showsClipboardToast = true }
            }
            .task(id: showsClipboardToast) {
                guard showsClipboardToast else { return }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { showsClipboardToast = false }
            }
            .onOpenURL { openedFile = $0 }
            .onChange(of: openedFile) { receiveOpenedFile() }
            .onChange(of: covered) { receiveOpenedFile() }
            .onChange(of: onboarded) { receiveOpenedFile() }
            .onAppear {
                clipboard.observe()
                cover.install(lockManager: lockManager, services: services)
                cover.show(covered)
            }
            .onChange(of: covered) { _, covered in
                // A reset drops `guarded` while still locked: take any vault sheet down first.
                if !covered, lockManager.isLocked { cover.dismissPresented() }
                cover.show(covered)
            }
            // Row 2.5: auto lock. Checked often enough that a minute means about a minute.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    lockManager.lockIfIdle()
                }
            }
        }
        // Spec 21 and 22, decided in LockManager so row 2.7 can test it.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if lockManager.sceneChanged(to: phase, guarded: guarded) {
                Task { await lockManager.unlock() }
            }
        }
    }
}
