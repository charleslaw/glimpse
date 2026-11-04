<p align="center">
  <img src="docs/icon.png" width="128" alt="Glimpse icon">
</p>

<h1 align="center">Glimpse</h1>

<p align="center">
  A fast, minimal image viewer for macOS.
</p>

<p align="center">
  <a href="https://github.com/glimpse-app/glimpse/actions/workflows/build.yml">
    <img src="https://github.com/glimpse-app/glimpse/actions/workflows/build.yml/badge.svg" alt="Build">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-15%2B-blue" alt="Xcode">
  <img src="https://img.shields.io/badge/license-GPL--3.0-green" alt="License">
</p>

<p align="center">
  <img src="docs/preview.png" alt="Glimpse screenshot" width="800">
</p>

---

## Features

- **Best-fit display** — images open scaled to fit your screen without cropping
- **Folder navigation** — press `←` / `→` to step through every image in the same folder, sorted naturally by filename
- **Multi-format** — JPEG, PNG, GIF, BMP, TIFF, HEIC, HEIF, WebP, JPEG 2000, AVIF, and more
- **Zero clutter** — a single resizable window, black background, nothing else
- **"Open With" integration** — set Glimpse as the default viewer for any image type in Finder
- **Full-screen support** — `⌃⌘F` to go full screen
- **Privacy-first** — no telemetry, no network access, no cloud, just files

## Installation

### Homebrew (recommended)

```bash
brew install glimpse
```

### Direct download

Download the latest `.dmg` from the [Releases](https://github.com/glimpse-app/glimpse/releases) page, drag Glimpse to your `/Applications` folder, and you're done.

### Build from source

See [Building](#building) below.

## Usage

| Action | How |
|--------|-----|
| Open an image | Double-click (when set as default viewer), drag onto the Dock icon, or **File → Open…** (`⌘O`) |
| Next image in folder | `→` arrow key |
| Previous image in folder | `←` arrow key |
| Zoom in | `⌘+` or `⌘=` |
| Zoom out | `⌘−` |
| Actual size (100%) | `⌘0` |
| Close window | `⌘W` or `Esc` |
| Full screen | `⌃⌘F` |
| Resize window | Drag any edge or corner |

The window title shows the current filename and position in the folder, e.g. `photo.jpg (7 of 42)`.

## Building

**Requirements**

- macOS 12.0 or later (to run)
- Xcode 15.0 or later (to build)

No external dependencies or package manager required — pure Cocoa/AppKit.

**Clone the repository**

```bash
git clone https://github.com/glimpse-app/glimpse.git
cd glimpse
```

**Option A — Command line**

Build a debug binary:

```bash
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build
```

Build a release binary:

```bash
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release build CODE_SIGN_IDENTITY="-"
```

The built `.app` is placed under `~/Library/Developer/Xcode/DerivedData/Glimpse-*/Build/Products/<Configuration>/Glimpse.app`.

**Option B — Xcode GUI**

```bash
open Glimpse.xcodeproj
```

Press `⌘R` to build and run.

**Local settings**

Copy `LocalDev.xcconfig.template` to `LocalDev.xcconfig` (git-ignored) to override build settings for your machine, such as setting your Apple Developer Team ID for device signing:

```bash
cp LocalDev.xcconfig.template LocalDev.xcconfig
# then edit LocalDev.xcconfig and set DEVELOPMENT_TEAM = <your Team ID>
```

## Project structure

```
Glimpse/
├── Sources/
│   ├── AppDelegate.swift       # App entry point, menu bar, file opening
│   ├── WindowController.swift  # Window creation and management
│   ├── ViewController.swift    # Image display and keyboard navigation
│   └── Common/
│       ├── FileNavigator.swift # Sorted sibling-file traversal
│       └── ImageLoader.swift   # Supported format registry
└── Resources/
    └── Assets.xcassets         # App icon and accent colour
```

## Contributing

Pull requests are very welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting.

- **Bugs** → [open an issue](https://github.com/glimpse-app/glimpse/issues/new?template=bug_report.md)
- **Features** → [open a feature request](https://github.com/glimpse-app/glimpse/issues/new?template=feature_request.md)
- **Questions** → [start a discussion](https://github.com/glimpse-app/glimpse/discussions)

## License

Glimpse is released under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

---

<p align="center">Made with care by the Glimpse contributors</p>



Add settings tab to top menu
  It has an item that is “best fit” or "actual size” or “auto size"
  When best fit, make the image fill the window as best as possible, meaning, maximize the size such that both the width and height fit within the window. When resizing the window resize the image. When going to the next image, if the window isn’t exactly the same size as the image, make the next image fit in the window
  When actual size, show the image at full resolution 
  When autosize, when showing a single image, do best fit, when going to the next image, 

When the image does not fill the window, center the image

