import Foundation
import Observation
import LidFoldModel

/// The few things worth remembering between launches.
@MainActor
@Observable
final class AppPreferences {

    static let shared = AppPreferences()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let effect = "effect"
    }

    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// The three knobs the menu bar exposes: start angle, frost, darkness.
    var effect: FoldAppearanceModel {
        didSet {
            if let data = try? JSONEncoder().encode(effect) {
                defaults.set(data, forKey: Key.effect)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.isEnabled: true, Key.hasCompletedOnboarding: false])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        if let data = defaults.data(forKey: Key.effect), let saved = try? JSONDecoder().decode(FoldAppearanceModel.self, from: data) {
            effect = saved
        } else {
            effect = FoldAppearanceModel()
        }
    }
}
