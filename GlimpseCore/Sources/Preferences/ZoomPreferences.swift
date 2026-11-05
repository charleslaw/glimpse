import Foundation

/// Owns persistence; views and sizing policies do not access UserDefaults directly.
public final class ZoomPreferences {
    private let defaults: UserDefaults
    private let key = "zoomMode"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: ZoomMode {
        get {
            defaults.string(forKey: key).flatMap(ZoomMode.init(rawValue:)) ?? .bestFit
        }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }
}
