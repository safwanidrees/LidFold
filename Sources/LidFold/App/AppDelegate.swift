import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferences: AppPreferences!
    private var foldViewModel: FoldViewModel!
    private var statusBarView: StatusBarView!
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = AppPreferences.shared
        self.preferences = preferences
        let foldViewModel = FoldViewModel(preferences: preferences)
        self.foldViewModel = foldViewModel
        let statusMenuViewModel = StatusMenuViewModel(preferences: preferences, foldViewModel: foldViewModel) { [weak self] in
            self?.showOnboarding()
        }
        statusBarView = StatusBarView(viewModel: statusMenuViewModel)
        foldViewModel.start()

        if !preferences.hasCompletedOnboarding {
            showOnboarding()
        }
        AppLog.app.notice("launched \(AppEnvironment.version, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        foldViewModel?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOnboarding()
        return true
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let onboardingViewModel = OnboardingViewModel(foldViewModel: foldViewModel)
            let root = OnboardingView(viewModel: onboardingViewModel) { [weak self] in
                self?.preferences.hasCompletedOnboarding = true
                self?.onboardingWindow?.close()
            }
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to \(AppEnvironment.name)"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
