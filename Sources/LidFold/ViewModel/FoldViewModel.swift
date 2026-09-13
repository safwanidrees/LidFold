import AppKit
import Observation
import QuartzCore
import LidFoldModel
import LidFoldRender

/// Runs the fold end to end: watches the lid, keeps a fresh screenshot
/// ready as the lid approaches the start angle, puts the picture up the
/// moment it crosses, and drives it every frame until the lid reopens far
/// enough to let go. The observable state and commands here are what the
/// views (status bar menu, onboarding screen) bind to.
@MainActor
@Observable
final class FoldViewModel {

    enum Status: Equatable {
        case noSensor
        case needsPermission
        case ready
        case off
    }

    /// The live hinge angle, for the menu bar icon to reflect.
    private(set) var angle: Double = 0
    private(set) var isActive = false
    private(set) var sensorAvailable = false

    var status: Status {
        if !sensorAvailable { return .noSensor }
        if !ScreenRecordingPermissionService.isGranted { return .needsPermission }
        return preferences.isEnabled ? .ready : .off
    }

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let monitor = HingeAngleMonitor()
    @ObservationIgnored private let capture = ScreenCaptureService()
    @ObservationIgnored private let overlay = FoldOverlayWindow()
    @ObservationIgnored private var decider: FoldDecider
    @ObservationIgnored private var spring = DampedSpring(frequency: 11)
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrameTime: CFTimeInterval = 0
    @ObservationIgnored private var captureTimer: Timer?
    @ObservationIgnored private var captureInFlight = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isPreviewing = false
    @ObservationIgnored private var drewSettledFrame = false

    init(preferences: AppPreferences) {
        self.preferences = preferences
        decider = FoldDecider(startAngle: preferences.effect.startAngle)
    }

    // MARK: Lifecycle

    /// Answers only whether the sensor exists, for the onboarding window
    /// shown before `start()`.
    func probeSensor() {
        sensorAvailable = monitor.isAvailable
    }

    func start() {
        sensorAvailable = monitor.isAvailable
        overlay.warmUp()
        observeSystemSleep()
        guard sensorAvailable else { return }
        monitor.onSample = { [weak self] tracker, time in self?.handle(tracker: tracker, at: time) }
        monitor.start()
        angle = monitor.tracker.angle
        // ScreenCaptureKit's own APIs trigger the system permission prompt
        // the moment they're called — only touch them once permission is
        // already granted, so launching the app never asks on its own.
        if ScreenRecordingPermissionService.isGranted {
            Task { await capture.warm() }
        }
    }

    func stop() {
        monitor.stop()
        stopDisplayLink()
        overlay.dismiss(animated: false)
        stopWarming()
        isActive = false
    }

    /// Plays one close-and-reopen without the lid actually moving.
    func preview() {
        guard !isActive, ScreenRecordingPermissionService.isGranted else { return }
        let startAngle = preferences.effect.startAngle
        let sweep = SimulatedFoldSweep(
            startedAt: CACurrentMediaTime() + 0.05,
            openAngle: min(startAngle + 30, 135),
            closedAngle: max(startAngle - FoldPhysicsConstants.span * 1.1, 8)
        )
        isPreviewing = true
        monitor.override = { time in sweep.angle(at: time) }
        monitor.setRate(.active)
        decider.forceIdle()
    }

    // MARK: Sampling

    private func handle(tracker: HingeAngleTracker, at time: CFTimeInterval) {
        guard !isSuspended else { return }
        angle = tracker.angle

        if isPreviewing, monitor.override == nil {
            isPreviewing = false
            monitor.resetBaseline()
            decider.forceIdle()
            endFold()
            return
        }

        decider.startAngle = preferences.effect.startAngle
        let previousPhase = decider.phase
        let phase = decider.update(tracker: tracker, enabled: preferences.isEnabled, time: time)

        switch (previousPhase, phase) {
        case (_, .active) where !isActive:
            beginFold()
        case (.active, .idle), (.active, .armed):
            endFold()
        case (_, .armed):
            startWarming()
        case (.armed, .idle):
            stopWarming()
        default:
            break
        }
        if isActive, !overlay.isVisible, !captureInFlight {
            present()
        }
        if isActive, overlay.isVisible, displayLink == nil {
            startDisplayLink()
        }

        monitor.setRate(isPreviewing || isActive || phase == .armed ? .active : .idle)
    }

    // MARK: Warm-up

    /// While the lid is approaching the start angle, keep a fresh
    /// screenshot on hand so the fold can appear the instant it triggers.
    private func startWarming() {
        guard ScreenRecordingPermissionService.isGranted, captureTimer == nil else { return }
        Task { _ = await capture.capture() }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { _ = await self.capture.capture() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
    }

    private func stopWarming() {
        captureTimer?.invalidate()
        captureTimer = nil
        capture.discard()
    }

    // MARK: Fold

    private func beginFold() {
        guard ScreenRecordingPermissionService.isGranted else {
            decider.forceIdle()
            return
        }
        isActive = true
        drewSettledFrame = false
        // Ease in from the start angle, so a lid already past it doesn't pop.
        spring.snap(to: max(monitor.tracker.angle, preferences.effect.startAngle))
        captureTimer?.invalidate()
        captureTimer = nil
        present()
    }

    private func endFold() {
        guard isActive else { return }
        isActive = false
        stopDisplayLink()
        overlay.dismiss(animated: true)
        capture.discard()
    }

    private func present() {
        guard let screen = NSScreen.builtIn else { return }
        if let image = capture.image {
            overlay.show(image, on: screen) { [weak self] in self?.startDisplayLink() }
            return
        }
        captureInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let image = await self.capture.capture()
            self.captureInFlight = false
            guard self.isActive, !self.overlay.isVisible, let image, let screen = NSScreen.builtIn else { return }
            self.overlay.show(image, on: screen) { [weak self] in self?.startDisplayLink() }
        }
    }

    // MARK: Frame loop

    private func startDisplayLink() {
        stopDisplayLink()
        guard let window = overlay.hostWindow else { return }
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        lastFrameTime = CACurrentMediaTime()
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrameTime, 1.0 / 240), 1.0 / 20)
        lastFrameTime = now
        let target = monitor.tracker.extrapolatedAngle(at: now)
        let wasSettled = spring.isSettled(at: target, tolerance: 0.02)
        spring.advance(toward: target, dt: dt)
        // A lid held perfectly still needs no more redraws.
        if wasSettled, spring.isSettled(at: target, tolerance: 0.02), drewSettledFrame { return }
        drewSettledFrame = spring.isSettled(at: target, tolerance: 0.02)
        overlay.render(FrameParameters.make(angle: spring.value, screenSize: overlay.screenSize, settings: preferences.effect))
    }

    // MARK: System sleep

    private func observeSystemSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isActive { self.endFold() }
                self.capture.invalidateFilter()
            }
        }
    }

    private func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        stopDisplayLink()
        overlay.dismiss(animated: false)
        stopWarming()
        monitor.override = nil
        isPreviewing = false
        isActive = false
        captureInFlight = false
        decider.forceIdle()
    }

    private func resume() {
        guard isSuspended else { return }
        isSuspended = false
        monitor.resetBaseline()
        monitor.setRate(.idle)
    }
}
