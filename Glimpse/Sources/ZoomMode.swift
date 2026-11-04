import Foundation

enum ZoomMode: String, CaseIterable {
    case bestFit    = "bestFit"
    case actualSize = "actualSize"
    case autoSize   = "autoSize"

    private static let defaultsKey = "zoomMode"

    static var current: ZoomMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let mode = ZoomMode(rawValue: raw) else { return .bestFit }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var menuTitle: String {
        switch self {
        case .bestFit:    return "Best Fit"
        case .actualSize: return "Actual Size"
        case .autoSize:   return "Scale to Fit"
        }
    }
}
