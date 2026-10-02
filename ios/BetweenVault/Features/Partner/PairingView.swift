import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// Rows 3.2 to 3.6: boards 11, 12, 13 and the failures 12a, 12b, 12c, 13a, in the order of the
/// amended spec 13. The state lives in `PairingFlow`; this file only draws it.
struct PairingView: View {
    @State private var flow: PairingFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(LockManager.self) private var lockManager
    private let start: () -> PairingFlow

    /// `start` makes a fresh attempt, also for "Start again": each attempt has its own keys.
    init(start: @escaping () -> PairingFlow) {
        self.start = start
        _flow = State(initialValue: start())
    }

    var body: some View {
        NavigationStack {
            Group {
                switch flow.step {
                case let .show(message, index): showQR(message, index: index)
                case let .scan(index): ScanStep(flow: flow, index: index)
                case let .compare(code): compare(code)
                case .paired: Color.clear.onAppear { dismiss() }
                case let .failed(failure): failed(failure)
                }
            }
            .toolbar {
                if !isFailed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.cancel) { dismiss() }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: flow.step == .paired)
        // Board 12c: each phone times out on its own. Pairing is held up, not tapped, so it
        // counts as activity for auto lock, and the screen stays awake; the 5 minutes bound both.
        .task(id: ObjectIdentifier(flow)) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                flow.expire()
                lockManager.noteActivity()
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var isFailed: Bool {
        if case .failed = flow.step { true } else { false }
    }

    private func stepLabel(_ index: Int) -> some View {
        Text(Copy.stepOf(index, PairingFlow.stepCount))
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Colors.secondary)
    }

    // MARK: Board 11

    private func showQR(_ message: Pairing.Message, index: Int) -> some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                stepLabel(index)
                Text(Copy.letPartnerScan)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                QRCodeImage(text: message.qrString)
                    .frame(width: 240, height: 240)
                    .padding(Theme.Space.md)
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                    .accessibilityLabel(Copy.pairingQR)
                Text(index == 1 ? Copy.onPartnersPhone : Copy.holdUpToPartner)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.pairInPersonFootnote)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            Button(Copy.partnerScannedIt) { flow.next() }
                .buttonStyle(.vaultPrimary)
                .padding(Theme.Space.lg)
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
    }

    // MARK: Board 13

    private func compare(_ code: String) -> some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                stepLabel(PairingFlow.stepCount)
                Text(Copy.doBothShow)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                CodeDisplay(code: code)
                    .padding(Theme.Space.lg)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                Text(Copy.compareDigits)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.ifNumbersDiffer)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(Copy.codesMatch) { flow.confirm() }
                    .buttonStyle(.vaultPrimary)
                Button(Copy.theyDontMatch) { flow.reject() }
                    .buttonStyle(.vaultSecondary)
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
    }

    // MARK: Boards 12c, 13a and the save failures

    @ViewBuilder
    private func failed(_ failure: PairingFlow.Failure) -> some View {
        switch failure {
        case .timedOut:
            FailureScreen(
                systemImage: "clock",
                title: Copy.pairingDidntFinish,
                message: Copy.pairingDidntFinishBody,
                emphasis: Copy.nothingSavedHere,
                steps: [Copy.timedOutStep1, Copy.timedOutStep2],
                footnote: Copy.timedOutFootnote,
                primary: (Copy.startAgain, { flow = start() }),
                secondary: (Copy.done, { dismiss() })
            )
        case .codesDidNotMatch:
            FailureScreen(
                systemImage: "exclamationmark.triangle",
                title: Copy.codesDidntMatch,
                message: Copy.codesDidntMatchBody,
                emphasis: nil,
                steps: [Copy.mismatchStep1, Copy.mismatchStep2],
                footnote: nil,
                primary: (Copy.startAgain, { flow = start() }),
                secondary: (Copy.done, { dismiss() })
            )
        case .notSaved, .alreadyPaired:
            FailureScreen(
                systemImage: "exclamationmark.triangle",
                title: Copy.pairingDidntFinish,
                message: failure == .alreadyPaired ? Copy.alreadyPaired : Copy.pairingNotSaved,
                emphasis: nil,
                steps: [],
                footnote: nil,
                primary: (Copy.done, { dismiss() }),
                secondary: nil
            )
        }
    }
}

// MARK: - Board 12: the camera

/// Board 12, with 12a and 12b when the camera cannot run. Dark like the board.
private struct ScanStep: View {
    let flow: PairingFlow
    let index: Int

    private enum Camera { case checking, ready, off, unavailable }
    @State private var camera = Camera.checking
    @Environment(\.dismiss) private var dismiss
    @Environment(LockManager.self) private var lockManager

    var body: some View {
        Group {
            switch camera {
            case .checking:
                Color.black
            case .ready:
                ZStack(alignment: .bottom) {
                    QRScanner { flow.scanned($0) }
                        .ignoresSafeArea()
                    VStack(spacing: Theme.Space.sm) {
                        Text(Copy.stepOf(index, PairingFlow.stepCount))
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondary)
                        Text(Copy.scanPartnersCodeTitle)
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.text)
                            .accessibilityAddTraits(.isHeader)
                        if let problem = flow.scanProblem {
                            Label(Self.copy(for: problem), systemImage: "exclamationmark.triangle")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.warning)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(Theme.Space.lg)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colors.lockScreen.opacity(0.9))
                }
                .onChange(of: flow.scanProblem) { _, problem in
                    if let problem { AccessibilityNotification.Announcement(Self.copy(for: problem)).post() }
                }
            case .off:
                FailureScreen(
                    systemImage: "camera",
                    title: Copy.cameraOff,
                    message: Copy.cameraOffBody,
                    emphasis: nil,
                    steps: [Copy.cameraOffStep1, Copy.cameraOffStep2],
                    footnote: Copy.cameraOffFootnote,
                    primary: (Copy.openSettings, {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }),
                    secondary: (Copy.cancelPairing, { dismiss() })
                )
            case .unavailable:
                FailureScreen(
                    systemImage: "video.slash",
                    title: Copy.cameraUnavailable,
                    message: Copy.cameraUnavailableBody,
                    emphasis: nil,
                    steps: [Copy.cameraUnavailableStep1, Copy.cameraUnavailableStep2],
                    footnote: nil,
                    primary: (Copy.tryAgain, { Task { await check() } }),
                    secondary: (Copy.cancelPairing, { dismiss() })
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { await check() }
        // Coming back from Settings with the camera turned on.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await check() }
        }
    }

    /// Denied by the person is 12a, fixed in Settings. Restricted (Screen Time, a profile), no
    /// camera, or one in use elsewhere is 12b.
    private func check() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // The permission alert makes the app inactive, which locks it; ask on the way back.
            lockManager.expectSystemPrompt()
            camera = await AVCaptureDevice.requestAccess(for: .video) ? availability : .off
        case .authorized:
            camera = availability
        case .denied:
            camera = .off
        default:
            camera = .unavailable
        }
    }

    private var availability: Camera {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable ? .ready : .unavailable
    }

    private static func copy(for problem: Pairing.PairingError) -> String {
        switch problem {
        case .wrongStep, .alreadyRevealed: Copy.wrongStepCode
        case .ownCode: Copy.ownCode
        case .unsupportedVersion: Copy.newerVersionCode
        default: Copy.notAPairingCode
        }
    }
}

/// VisionKit's scanner, QR only. Each code is reported once when it comes into view.
private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                if let text = code.payloadStringValue { onScan(text) }
            }
        }
    }
}

// MARK: - Shared pieces

/// Boards 11 and the return QRs: crisp at any size, black on white for every camera.
private struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Boards 12a, 12b, 12c, 13a: an icon, a title, what happened, numbered steps, two buttons.
private struct FailureScreen: View {
    let systemImage: String
    let title: String
    let message: String
    let emphasis: String?
    let steps: [String]
    let footnote: String?
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondary)
                if let emphasis {
                    Text(emphasis)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.text)
                }
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { number, step in
                            Label {
                                Text(step)
                            } icon: {
                                Text("\(number + 1)")
                                    .font(Theme.Typography.footnote.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .background(Theme.Colors.accentTint, in: Circle())
                            }
                        }
                    }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .padding(Theme.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                }
                if let footnote {
                    Text(footnote)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondary)
                }
            }
            .padding(Theme.Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(primary.0, action: primary.1)
                    .buttonStyle(.vaultPrimary)
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .buttonStyle(.vaultSecondary)
                }
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
    }
}
