import CoreGraphics
import AppKit

/// Screen Recording — the one permission the fold needs. Without it,
/// capture returns nothing but a wallpaper-coloured frame.
enum ScreenRecordingPermissionService {

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time only; later calls return the
    /// stored answer, so Settings is the way back in after a decline.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
