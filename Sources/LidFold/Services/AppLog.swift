import Foundation
import os

/// Read with:
///
///     log show --last 10m --predicate 'subsystem == "com.local.lidfold"' --info
enum AppLog {
    static let subsystem = "com.local.lidfold"
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let app = Logger(subsystem: subsystem, category: "app")
}
