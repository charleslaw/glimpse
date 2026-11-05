import Cocoa

// Explicit entry point — avoids the @NSApplicationMain restriction and
// keeps the app fully programmatic (no storyboard required).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
