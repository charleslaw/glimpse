# Building, checking and extending the app

## Local workflow

Run from the repository root with Xcode installed:

```bash
# Core regression tests, then strict Debug and Release app builds
bash scripts/check.sh

# Core tests alone
swift test

# Universal ad-hoc signed local archive, without an Apple membership
bash scripts/package_release.sh --local

# Check committed Git history for secrets
bash scripts/check_secrets.sh
```

The app uses Apple frameworks and has no third-party runtime dependencies. The optional diagram generator uses Pillow, and secret scanning downloads a checksum-pinned development-only Gitleaks binary to the ignored build directory. Neither ships in the app.

`check.sh` treats Swift warnings as errors and enables complete concurrency diagnostics. `GLIMPSE_SWIFT_SCRATCH` and `GLIMPSE_DERIVED_DATA` relocate outputs. On an already-sandboxed build host, `GLIMPSE_DISABLE_PACKAGE_SANDBOX=1` disables only SwiftPM's nested manifest subprocess sandbox; it does not change the app's security settings.

## Common changes

| Change | Start here | Verify |
| --- | --- | --- |
| New setting | Core Preferences + app menu/controller | Persistence, invalid-value fallback, all open windows, restart |
| Zoom/window behavior | `ImageSizing` + image controller | Aspect ratio, tiny/huge images, resize and manual zoom |
| Background appearance | `ImageContentView` + Appearance | Transparent image, gutters, zoom, RGB validation, cancel/apply |
| Format/decoder behavior | `ImageFormats` / `ImageDecoder` | Generated fixture, orientation/animation, resource limits |
| Navigation/cache | `FileNavigator` / `ImageRepository` / cache | Wrap/sorting, file changes, cancellation, stale in-flight prefetch |
| Action kind | Core Actions model/validation + `ActionRunner` | Literal substitutions, invalid configuration, execution boundary |
| Metadata field/parser | Metadata readers/container inspector | Truncated and malformed data, bounds/budgets, honest labels |
| App menu/window lifetime | App and window controllers | Responder-chain routing, multiple windows, close/reopen behavior |

Keep new UI classes main-actor isolated. Keep reusable policy out of window controllers and preference I/O out of views. Register new app/core files in Xcode as well as putting them in the intended source folder. Add focused behavioral tests for new policies and failure cases; a passing core suite does not replace a visual UI check.

## Security and distribution

The app is not App Sandbox enabled, though hardened runtime is used. Do not interpret bounded reads or command confirmation as process isolation. Keep native decoder dependencies updated through macOS updates, and review any new runtime package or executable boundary.

GitHub workflows provide build/tests, history secret scanning and optional Swift/Actions CodeQL. Their presence does not establish that a GitHub run has completed; private CodeQL also depends on repository licensing. The prior local audit could not complete AddressSanitizer startup; no clean sanitizer result is claimed.

Public direct distribution needs a **Developer ID Application** certificate/private key and Apple notarization credentials. `package_release.sh --public` builds universal code, signs with hardened runtime/timestamp, submits to Apple, requires acceptance, staples the app and assesses Gatekeeper before packaging. It does not publish releases. Ad-hoc local packages are explicitly labeled for testing and do not establish public trust. See [distribution setup](../docs/DISTRIBUTION.md) for the credential workflow.

## Documentation maintenance

Update the relevant page here when changing a boundary or persistent behavior. Regenerate diagram PNG/SVG pairs with `python3 specs/render_diagrams.py` after editing their definitions. Keep diagram labels aligned with actual class names and folder names. Put new architecture images under `specs/images/` and use relative links so this entire guide works in a checkout or on GitHub.
