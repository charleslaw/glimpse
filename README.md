<p align="center">
  <img src="docs/icon.png" width="128" alt="Glimpse icon">
</p>

<h1 align="center">Glimpse</h1>

<p align="center">
  A fast, minimal image viewer for macOS.
</p>

<p align="center">
  <a href="https://github.com/charleslaw/glimpse/actions/workflows/build.yml">
    <img src="https://github.com/charleslaw/glimpse/actions/workflows/build.yml/badge.svg" alt="Build">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-15%2B-blue" alt="Xcode">
  <img src="https://img.shields.io/badge/license-GPL--3.0-green" alt="License">
</p>

---

## Features

- **Best-fit display** — images open scaled to fit your screen without cropping
- **Folder navigation** — press `←` / `→` to step through every image in the same folder, sorted naturally by filename
- **Multi-format** — JPEG, PNG, GIF, BMP, TIFF, HEIC, HEIF, WebP, JPEG 2000, AVIF, and more
- **Simple viewing** — a resizable image window with a subtle dark-gray pattern or your preferred background color
- **"Open With" integration** — set Glimpse as the default viewer for any image type in Finder
- **Full-screen support** — `⌃⌘F` to go full screen
- **Quick navigation** — bounded caching and adjacent-image preloading
- **Metadata inspector** — searchable ImageIO/EXIF fields and JPEG, PNG and GIF container details
- **Configurable Actions menu** — copy paths, reveal images, or add trusted commands and HTTPS links
- **Local viewing** — no telemetry or automatic uploads; custom actions can open websites or run commands only when selected

## Installation

Build from source below. Public distribution tooling is prepared, but a Developer ID-signed, notarized release has not yet been produced. See [Distribution](docs/DISTRIBUTION.md) for local packaging, Apple account setup, and the public release workflow.

## Usage

| Action | How |
|--------|-----|
| Open an image | Double-click (when set as default viewer), drag onto the Dock icon, or **File → Open…** (`⌘O`) |
| Next image in folder | `→` arrow key |
| Previous image in folder | `←` arrow key |
| Zoom in | `⌘+` or `⌘=` |
| Zoom out | `⌘−` |
| Actual size (100%) | `⌘0` |
| Inspect metadata | **File → View Metadata…** (`⌘I`) |
| Copy path / reveal image | **Actions → Copy Image Path / Open Image Location** |
| Close window | `⌘W` or `Esc` |
| Full screen | `⌃⌘F` |
| Resize window | Drag any edge or corner |

The window title shows the current filename and position in the folder, e.g. `photo.jpg (7 of 42)`.

The title bar also has Zoom Out, Zoom In, Actual Size and Best Fit buttons. Choose a default zoom mode in **Settings**. Your last selection is remembered between launches:

- **Best Fit** fits images without enlarging them beyond 100%, and refits when you resize the window.
- **Actual Size** opens images at 100%; scroll to see any parts outside the window.
- **Scale to Fit** enlarges small images or shrinks large images to fit within 90% of the visible screen, preserving their proportions (up to 20× zoom). It reapplies when you open or navigate to an image.

Manual zoom shortcuts work in every mode; `⌘0` returns the current image to 100%.

Choose **Settings → Background** for **Dark Gray Pattern** (the default), **Black**, **White**, **Very Dark Gray**, or **Custom…**. Custom accepts red, green and blue values from 0–255 and includes the macOS color picker. Click Apply to update all image windows. Your selection and custom RGB color are remembered between launches. Backgrounds show around images and through transparent pixels; image files are not modified.

## Building

**Requirements**

- macOS 12.0 or later (to run)
- Xcode 15.0 or later (to build)

No external dependencies or package manager required — pure Cocoa/AppKit.

**Clone the repository**

```bash
git clone https://github.com/charleslaw/glimpse.git
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

**Verification**

Run `bash scripts/check.sh` for core unit tests and Debug/Release builds with strict concurrency diagnostics. `bash scripts/check_secrets.sh` installs a checksum-pinned, development-only Gitleaks binary into the ignored build folder and scans Git history. GitHub Actions also has optional Swift/Actions CodeQL analysis; private repositories need an eligible license. See [Security](SECURITY.md).

## Project structure

The AppKit app in `Glimpse/Sources` owns application lifecycle, windows, menus and presentation. `GlimpseCore/Sources` contains navigation, preferences, layout, bounded image loading/cache, actions configuration and metadata services. Xcode links core as a static framework; SwiftPM runs its independent tests against the same files. See [Architecture and audit](docs/ARCHITECTURE-AUDIT.md) and [Actions configuration](docs/ACTIONS.md).

## Contributing

Pull requests are very welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting.

- **Bugs and features** → [open an issue](https://github.com/charleslaw/glimpse/issues)

## License

Glimpse is released under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

---

<p align="center">Made with care by the Glimpse contributors</p>

