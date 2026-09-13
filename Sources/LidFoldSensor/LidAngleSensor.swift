import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook's built-in lid angle sensor.
///
/// Machines with a hinge sensor (MacBook Air M2 and later, 14/16-inch
/// MacBook Pro 2021 and later, the 2019 16-inch MacBook Pro) expose it as
/// a HID feature report on a device matching usage page `0x20` (sensor),
/// usage `0x8A` (orientation), vendor `0x05AC`. Two report shapes are seen
/// in the wild:
///
/// - Report `7`: five bytes `[7, b0, b1, b2, b3]`, a little-endian 32-bit
///   count of hundredths of a degree.
/// - Report `1`: three bytes `[1, lo, hi]`, a little-endian 16-bit count
///   of whole degrees.
///
/// No permission is required to read it. The hardware refreshes roughly
/// every 100 ms; 0° is fully closed and most lids open to about 130°.
public final class LidAngleSensor: @unchecked Sendable {

    enum ReportShape: Sendable {
        case hundredthsOfADegree
        case wholeDegrees

        var reportID: CFIndex {
            switch self {
            case .hundredthsOfADegree: return 7
            case .wholeDegrees: return 1
            }
        }
    }

    private var reportShape: ReportShape?
    public var isAvailable: Bool { device != nil && reportShape != nil }

    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var buffer = [UInt8](repeating: 0, count: 64)

    public init() {
        openDevice()
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    /// The current hinge angle in degrees, or `nil` if the read failed.
    public func read() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let reportShape, let bytes = readReport(reportShape.reportID) else { return nil }
        let degrees: Double
        switch reportShape {
        case .hundredthsOfADegree:
            guard bytes.count >= 5 else { return nil }
            let raw = UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
            degrees = Double(raw) / 100
        case .wholeDegrees:
            guard bytes.count >= 3 else { return nil }
            degrees = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        }
        guard (0...360).contains(degrees) else { return nil }
        return degrees
    }

    private func openDevice() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: NSDictionary = [
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.manager = manager

        guard let candidates = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in candidates {
            device = candidate
            if let bytes = readReport(7), bytes.count >= 5 {
                reportShape = .hundredthsOfADegree
                return
            }
            if let bytes = readReport(1), bytes.count >= 3 {
                reportShape = .wholeDegrees
                return
            }
        }
        device = nil
    }

    private func readReport(_ id: CFIndex) -> [UInt8]? {
        guard let device else { return nil }
        var length = CFIndex(buffer.count)
        let status = buffer.withUnsafeMutableBufferPointer { pointer -> IOReturn in
            guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, id, base, &length)
        }
        guard status == kIOReturnSuccess, length > 0 else { return nil }
        return Array(buffer[0..<Int(length)])
    }
}
