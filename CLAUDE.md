# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build commands

```bash
# Debug build
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build

# Release build
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release build CODE_SIGN_IDENTITY="-"

# Open in Xcode, then ⌘R to build and run
open Glimpse.xcodeproj
```

Output lands under `~/Library/Developer/Xcode/DerivedData/Glimpse-*/Build/Products/<Configuration>/Glimpse.app`.

There are no unit tests; CI builds both Debug and Release to verify compilation.

## Architecture

Glimpse is a minimal macOS image viewer (~625 lines, no external dependencies) built with AppKit. The UI is entirely programmatic — no storyboards.

**Component responsibilities:**

- `main.swift` — explicit entry point; starts `NSApplication` manually (avoids `@NSApplicationMain`)
- `AppDelegate` — app lifecycle, all menu construction (programmatic), file-open APIs (`openFile:`, `openFiles:`, `⌘O`)
- `WindowController` — creates each window (black background, min 200×150) and its `NSToolbar` with 4 zoom actions using SF Symbols
- `ViewController` — image display, zoom (0.05×–20×), keyboard navigation (`←`/`→`/`Esc`), window fitting; contains two nested custom views:
  - `ContentView` (NSView subclass): accepts first-responder for key events
  - `ZoomableScrollView` (NSScrollView subclass): intercepts ⌘-scroll and ⌃-scroll for zoom
- `FileNavigator` — loads all image siblings from a directory, sorted with `localizedStandardCompare`, with wrapping navigation
- `ImageLoader` — registry of supported extensions (14 formats) and their `UTType` mappings; used by `NSOpenPanel` and `FileNavigator`

**Multiple windows:** Each opened file gets its own `WindowController`/`ViewController` pair. `AppDelegate` holds strong references to all active window controllers and removes them on close.

**Image loading:** Uses `CGImageSourceCreateWithURL` with `kCGImageSourceShouldCacheImmediately` and `kCGImageSourceShouldAllowFloat` flags (not `NSImage(contentsOf:)`).

**Window fitting:** `fitWindowToImage(_:)` in `ViewController` constrains the window to 90% of screen size while preserving aspect ratio.

## Code style

- Most restrictive access control (`private` > `fileprivate` > `internal`)
- No force-unwrapping in production; use `guard let` / `if let`
- Mark leaf classes `final`
- One primary type per file
- Tab indentation (Xcode default)
- Commit format: `<type>: <summary>` where type is `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`, or `test`
