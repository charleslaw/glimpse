# Changelog

All notable changes to Glimpse are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- AVIF format support via macOS 16 image I/O

---

## [1.3.1] — 2024-11-08

### Fixed
- Window title not updating when navigating rapidly with held arrow key (#112) — @mthurston
- Crash opening zero-byte image files (#118) — @danielbr

---

## [1.3.0] — 2024-10-02

### Added
- Full-screen mode (`⌃⌘F`) — @yuki-tanaka
- Window remembers last size when opening images of the same dimensions — @fernanda-cx

### Changed
- Folder navigation now wraps around (last → first and first → last) — @ryanmoss
- Window minimum size reduced to 200×150 — @julesvidal

### Fixed
- `.jfif` files not appearing in folder sibling list (#97) — @mthurston
- Incorrect image count shown when hidden files exist in folder (#103) — @pbontempi

---

## [1.2.0] — 2024-07-15

### Added
- WebP and HEIF format support — @yuki-tanaka
- Natural sort order for filenames containing numbers (e.g. `img2.png` before `img10.png`) — @danielbr

### Changed
- Switched deployment target from macOS 11 to macOS 12 for `UTType` API use — @fernanda-cx
- Black background now applied during window animation to avoid white flash — @ryanmoss

### Fixed
- First-responder not set correctly after window first appears (#72) — @pbontempi
- Image scaling incorrect for 1-pixel-wide images (#78) — @mthurston

---

## [1.1.1] — 2024-05-20

### Fixed
- App quit immediately on launch when no file was passed (#64) — @julesvidal
- `.tif` extension (without second `f`) not recognised (#67) — @danielbr

---

## [1.1.0] — 2024-04-03

### Added
- `Esc` key closes the current window — @mthurston
- Window title shows position within folder: `photo.jpg (3 of 17)` — @fernanda-cx
- File > Open… menu item with image-type filter — @ryanmoss

### Changed
- Window no longer upscales images smaller than the screen — @yuki-tanaka
- Improved memory handling: previous `NSImage` released before loading next — @pbontempi

---

## [1.0.0] — 2024-02-14

### Added
- Initial release
- Open images via "Open With", Dock drag-and-drop, or File > Open…
- Best-fit window sizing (90% of visible screen area, maintain aspect ratio)
- Folder navigation with `←` / `→` arrow keys
- Support for JPEG, PNG, GIF, BMP, TIFF, HEIC, JPEG 2000, ICO
- macOS 12+ deployment target

[Unreleased]: https://github.com/glimpse-app/glimpse/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/glimpse-app/glimpse/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/glimpse-app/glimpse/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/glimpse-app/glimpse/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/glimpse-app/glimpse/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/glimpse-app/glimpse/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/glimpse-app/glimpse/releases/tag/v1.0.0
