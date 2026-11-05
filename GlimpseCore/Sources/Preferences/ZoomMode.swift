import Foundation

public enum ZoomMode: String, CaseIterable {
    case bestFit = "bestFit"
    case actualSize = "actualSize"
    // Keep this persisted value compatible with existing installations.
    case autoSize = "autoSize"

    public var menuTitle: String {
        switch self {
        case .bestFit: return "Best Fit"
        case .actualSize: return "Actual Size"
        case .autoSize: return "Scale to Fit"
        }
    }
}
