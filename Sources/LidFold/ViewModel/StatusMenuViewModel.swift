import Observation

/// Everything the menu bar dropdown shows or can do, so the view itself
/// (`StatusBarView`) only has to build the menu and bind to this — it
/// never reaches into preferences or the fold engine directly.
@MainActor
@Observable
final class StatusMenuViewModel {

    private let preferences: AppPreferences
    private let foldViewModel: FoldViewModel
    private let showOnboarding: () -> Void

    init(preferences: AppPreferences, foldViewModel: FoldViewModel, showOnboarding: @escaping () -> Void) {
        self.preferences = preferences
        self.foldViewModel = foldViewModel
        self.showOnboarding = showOnboarding
    }

    var appName: String { AppEnvironment.name }

    var statusLineText: String {
        switch foldViewModel.status {
        case .noSensor: return "No lid angle sensor on this Mac"
        case .needsPermission: return "Screen Recording access needed"
        case .off: return "\(AppEnvironment.name) is off"
        case .ready: return foldViewModel.isActive ? "Folding…" : "Ready"
        }
    }

    var isEnabled: Bool { preferences.isEnabled }
    var isEnableToggleAvailable: Bool { foldViewModel.status != .noSensor }
    func toggleEnabled() { preferences.isEnabled.toggle() }

    var canPreview: Bool { foldViewModel.status == .ready || foldViewModel.status == .off }
    func preview() { foldViewModel.preview() }

    var startAngle: Double {
        get { preferences.effect.startAngle }
        set { preferences.effect.startAngle = newValue }
    }
    var frostRadius: Double {
        get { preferences.effect.blurRadius }
        set { preferences.effect.blurRadius = newValue }
    }
    var darkness: Double {
        get { preferences.effect.dimAmount }
        set { preferences.effect.dimAmount = newValue }
    }

    var isLaunchAtLoginEnabled: Bool { LaunchAtLoginService.isEnabled }
    func toggleLaunchAtLogin() { LaunchAtLoginService.set(!LaunchAtLoginService.isEnabled) }

    var needsPermissionPrompt: Bool { foldViewModel.status == .needsPermission }
    func openPermissionPrompt() { showOnboarding() }

    var aboutInformativeText: String {
        "Version \(AppEnvironment.version)\n\nClosing the lid tilts the display over a desktop that stays put, blurring as it goes. Open it back up and the picture sharpens again."
    }

    /// The angle the menu bar icon should be drawn at, and whether to show
    /// the fold-active marker.
    var displayAngle: Double { foldViewModel.sensorAvailable ? foldViewModel.angle : 92 }
    var isFolding: Bool { foldViewModel.isActive }
}
