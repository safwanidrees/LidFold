import ServiceManagement

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the state after the change, which can differ from what was
    /// asked for if macOS refused it.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.app.error("launch at login change failed: \(String(describing: error), privacy: .public)")
        }
        return isEnabled
    }
}
