import SwiftUI
import UIKit

/// Row 2.5: the lock screen in its own window, above every sheet, alert and dialog the app draws.
/// While locked nothing of the vault reaches the screen or the app switcher snapshot, whatever was
/// presented when it locked. The window also reports touches and keystrokes for auto lock.
@MainActor
final class CoverWindow {
    private var window: UIWindow?
    private weak var appWindow: UIWindow?

    /// Called once the scene is up. The cover starts hidden; `show` decides.
    func install(lockManager: LockManager, services: AppServices?) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let appWindow = scene.windows.first
        else { return }
        self.appWindow = appWindow

        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        let host = UIHostingController(
            rootView: PrivacyOverlayView.Cover(lockManager: lockManager).environment(services)
        )
        host.view.backgroundColor = .clear
        // VoiceOver stays in the cover and never reaches the vault drawn underneath.
        host.view.accessibilityViewIsModal = true
        cover.rootViewController = host
        window = cover

        appWindow.addGestureRecognizer(ActivityRecognizer { lockManager.noteActivity() })
        // Typing reaches the keyboard's window, not ours, so a long note counts through its text.
        // VoiceOver and Switch Control move focus without touches; that counts too.
        for name in [
            UITextField.textDidChangeNotification,
            UITextView.textDidChangeNotification,
            UIAccessibility.elementFocusedNotification,
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { lockManager.noteActivity() }
            }
        }
    }

    /// After a reset the cover comes off while a vault sheet may still be up; it goes first,
    /// without the animation that would show it on the way out.
    func dismissPresented() {
        appWindow?.rootViewController?.dismiss(animated: false)
    }

    /// An alert above whatever the vault presents, so a sheet that is up does not swallow it.
    func alert(_ title: String, _ message: String) {
        var top = appWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Copy.ok, style: .cancel))
        top?.present(alert, animated: true)
    }

    func show(_ visible: Bool) {
        guard let window else { return }
        if visible {
            // The keyboard's window sits above any level the app can pick, so the editor gives it
            // up before the cover takes over; otherwise it keeps typing into the hidden note.
            appWindow?.endEditing(true)
            window.makeKeyAndVisible()
        } else {
            window.isHidden = true
            appWindow?.makeKey()
        }
    }
}

/// Sees every touch on the app window and lets it through untouched.
private final class ActivityRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}
