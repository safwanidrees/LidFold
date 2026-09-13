import Foundation

enum AppEnvironment {
    static let name = "LidFold"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.local.lidfold"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
}
