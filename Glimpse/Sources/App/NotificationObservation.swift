import Foundation

/// An immutable registration handle. NotificationCenter supports removal from
/// any thread, including a main-actor owner's nonisolated deinitializer.
final class NotificationObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(name: Notification.Name, object: AnyObject?, handler: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
            handler()
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
