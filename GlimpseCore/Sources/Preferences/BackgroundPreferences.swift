import Foundation

/// An opaque, validated 8-bit sRGB color, independent of AppKit.
public struct BackgroundRGBColor: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init?(red: Int, green: Int, blue: Int) {
        guard [red, green, blue].allSatisfy({ (0...255).contains($0) }) else { return nil }
        self.red = red
        self.green = green
        self.blue = blue
    }

    private init(validRed: Int, green: Int, blue: Int) {
        red = validRed
        self.green = green
        self.blue = blue
    }

    public static let black = BackgroundRGBColor(validRed: 0, green: 0, blue: 0)
    public static let white = BackgroundRGBColor(validRed: 255, green: 255, blue: 255)
    public static let veryDarkGray = BackgroundRGBColor(validRed: 24, green: 24, blue: 24)
    public static let patternBase = BackgroundRGBColor(validRed: 32, green: 32, blue: 32)
    public static let patternAlternate = BackgroundRGBColor(validRed: 40, green: 40, blue: 40)
}

public enum ViewerBackgroundStyle: String, CaseIterable, Sendable {
    case checkerboard, black, white, veryDarkGray, custom

    public var menuTitle: String {
        switch self {
        case .checkerboard: return "Dark Gray Pattern"
        case .black: return "Black"
        case .white: return "White"
        case .veryDarkGray: return "Very Dark Gray"
        case .custom: return "Custom…"
        }
    }

    public func baseColor(custom: BackgroundRGBColor) -> BackgroundRGBColor {
        switch self {
        case .checkerboard: return .patternBase
        case .black: return .black
        case .white: return .white
        case .veryDarkGray: return .veryDarkGray
        case .custom: return custom
        }
    }
}

/// Shared by all viewer windows; only this service reads/writes the defaults.
public final class BackgroundPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var style: ViewerBackgroundStyle {
        get { defaults.string(forKey: "backgroundStyle").flatMap(ViewerBackgroundStyle.init(rawValue:)) ?? .checkerboard }
        set { defaults.set(newValue.rawValue, forKey: "backgroundStyle") }
    }

    public var customColor: BackgroundRGBColor {
        get {
            guard let values = defaults.array(forKey: "backgroundRGB") as? [Int], values.count == 3,
                  let color = BackgroundRGBColor(red: values[0], green: values[1], blue: values[2]) else { return .veryDarkGray }
            return color
        }
        set { defaults.set([newValue.red, newValue.green, newValue.blue], forKey: "backgroundRGB") }
    }
}
