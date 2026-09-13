import AppKit
import ScreenCaptureKit
import LidFoldRender

/// One still of the built-in display, captured the moment the fold triggers.
@MainActor
final class ScreenCaptureService {

    private(set) var image: CGImage?
    private var filter: SCContentFilter?
    private var filterDisplay: CGDirectDisplayID?
    private var inFlight: Task<CGImage?, Never>?

    func discard() {
        image = nil
    }

    func invalidateFilter() {
        filter = nil
        filterDisplay = nil
    }

    /// Builds the capture filter ahead of time; enumerating windows takes ~70 ms.
    func warm() async {
        guard let id = NSScreen.builtIn?.displayID, filter == nil || filterDisplay != id else { return }
        await rebuildFilter(display: id)
    }

    /// Captures once. Concurrent callers share the same in-flight capture.
    @discardableResult
    func capture() async -> CGImage? {
        if let inFlight { return await inFlight.value }
        let task = Task<CGImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.performCapture()
            self.inFlight = nil
            return image
        }
        inFlight = task
        return await task.value
    }

    private func performCapture() async -> CGImage? {
        guard let screen = NSScreen.builtIn, let id = screen.displayID else { return nil }
        if filter == nil || filterDisplay != id {
            await rebuildFilter(display: id)
        }
        guard let filter else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.colorSpaceName = FoldRenderer.colourSpace
        do {
            let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            image = captured
            return captured
        } catch {
            AppLog.capture.error("snapshot failed: \(String(describing: error), privacy: .public)")
            invalidateFilter()
            return nil
        }
    }

    private func rebuildFilter(display id: CGDirectDisplayID) async {
        filter = await CaptureFilterFactory.make(display: id)
        filterDisplay = filter == nil ? nil : id
    }
}

/// Builds a display filter that excludes this app's own windows, so the
/// overlay can never capture itself.
enum CaptureFilterFactory {
    @MainActor
    static func make(display id: CGDirectDisplayID) async -> SCContentFilter? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            let own = content.applications.filter { $0.bundleIdentifier == AppEnvironment.bundleID }
            return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        } catch {
            AppLog.capture.error("shareable content failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
