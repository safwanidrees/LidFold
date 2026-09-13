import Observation

/// State and actions for the onboarding screen: whether this Mac has the
/// sensor, whether Screen Recording is granted, and the two ways to ask
/// for it (first the system prompt, then a link to Settings if declined).
@MainActor
@Observable
final class OnboardingViewModel {

    private let foldViewModel: FoldViewModel

    private(set) var permissionGranted: Bool
    private(set) var askedForPermission = false

    var sensorAvailable: Bool { foldViewModel.sensorAvailable }

    init(foldViewModel: FoldViewModel) {
        self.foldViewModel = foldViewModel
        permissionGranted = ScreenRecordingPermissionService.isGranted
    }

    func probeSensor() {
        foldViewModel.probeSensor()
    }

    /// Shows the system prompt the first time; opens Settings afterward,
    /// since macOS won't prompt twice for the same app.
    func requestPermission() {
        if askedForPermission {
            ScreenRecordingPermissionService.openSettings()
        } else {
            askedForPermission = true
            ScreenRecordingPermissionService.request()
        }
    }

    /// Called periodically by the view while it's visible, since nothing
    /// pushes permission changes to us.
    func refreshPermissionStatus() {
        let now = ScreenRecordingPermissionService.isGranted
        if now != permissionGranted { permissionGranted = now }
    }
}
