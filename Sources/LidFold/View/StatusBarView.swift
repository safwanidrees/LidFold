import AppKit

/// The menu bar item and its dropdown menu. Presentation only — every
/// piece of state and every action reads from or calls into
/// `StatusMenuViewModel`.
@MainActor
final class StatusBarView: NSObject, NSMenuDelegate {

    private let viewModel: StatusMenuViewModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let statusLine = NSMenuItem()
    private let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "Preview Fold", action: #selector(preview), keyEquivalent: "p")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Allow Screen Recording…", action: #selector(openPermission), keyEquivalent: "")
    private var startRow: MenuSliderControl!
    private var frostRow: MenuSliderControl!
    private var darkRow: MenuSliderControl!
    private var iconTimer: Timer?
    private var lastIcon: (angle: Int, active: Bool) = (-1, false)

    init(viewModel: StatusMenuViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        statusItem.menu = menu
        refreshIcon()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }

    /// Redraws the menu bar glyph only when the angle (rounded) or the
    /// active state actually changed, so an idle lid costs nothing.
    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let angle = Int(viewModel.displayAngle.rounded())
        let active = viewModel.isFolding
        if lastIcon.angle != angle || lastIcon.active != active {
            lastIcon = (angle, active)
            button.image = MenuBarIcon.image(angle: viewModel.displayAngle, active: active)
        }
        button.appearsDisabled = !viewModel.isEnabled || !viewModel.isEnableToggleAvailable
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enableItem.target = self
        menu.addItem(enableItem)
        previewItem.target = self
        menu.addItem(previewItem)
        menu.addItem(.separator())

        // The three knobs people reach for most, right in the menu.
        startRow = MenuSliderControl(title: "Starts at", value: viewModel.startAngle, range: 40...125, step: 1,
                                     format: { String(format: "%.0f°", $0) }) { [weak self] value in
            self?.viewModel.startAngle = value
        }
        frostRow = MenuSliderControl(title: "Frost", value: viewModel.frostRadius, range: 16...180, step: 2,
                                     format: { String(format: "%.0f pt", $0) }) { [weak self] value in
            self?.viewModel.frostRadius = value
        }
        darkRow = MenuSliderControl(title: "Darkness", value: viewModel.darkness, range: 0...1, step: 0.05,
                                    format: { String(format: "%.0f%%", $0 * 100) }) { [weak self] value in
            self?.viewModel.darkness = value
        }
        for row in [startRow!, frostRow!, darkRow!] {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        permissionItem.target = self
        menu.addItem(permissionItem)

        let about = NSMenuItem(title: "About \(viewModel.appName)", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(viewModel.appName)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusLine.title = viewModel.statusLineText
        enableItem.state = viewModel.isEnabled ? .on : .off
        enableItem.isEnabled = viewModel.isEnableToggleAvailable
        startRow.set(value: viewModel.startAngle)
        frostRow.set(value: viewModel.frostRadius)
        darkRow.set(value: viewModel.darkness)
        loginItem.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        previewItem.isEnabled = viewModel.canPreview
        permissionItem.isHidden = !viewModel.needsPermissionPrompt
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        viewModel.toggleEnabled()
    }

    @objc private func preview() {
        viewModel.preview()
    }

    @objc private func toggleLaunchAtLogin() {
        viewModel.toggleLaunchAtLogin()
    }

    @objc private func openPermission() {
        viewModel.openPermissionPrompt()
    }

    @objc private func openAbout() {
        let alert = NSAlert()
        alert.messageText = viewModel.appName
        alert.informativeText = viewModel.aboutInformativeText
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
