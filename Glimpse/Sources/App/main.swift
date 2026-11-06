import Cocoa

// The synchronous executable entry point runs on the main thread. Explicitly
// establish actor isolation for older Swift compilers as well as Swift 6.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication's delegate is weak; retain it for the entire event loop.
    withExtendedLifetime(delegate) { app.run() }
}
