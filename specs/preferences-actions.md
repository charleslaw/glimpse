# Preferences, background rendering and actions

## Preferences flow

```text
Settings selection / Custom Apply
    → shared preference store writes UserDefaults
    → menu updates its checkmark
    → AppDelegate callback updates every open viewer
    → newly opened viewers read the same store
```

| Key | Owner | Meaning / fallback |
| --- | --- | --- |
| `zoomMode` | `ZoomPreferences` | `bestFit`, `actualSize`, legacy raw value `autoSize`; defaults to Best Fit |
| `backgroundStyle` | `BackgroundPreferences` | `checkerboard`, `black`, `white`, `veryDarkGray`, `custom`; defaults to the pattern |
| `backgroundRGB` | `BackgroundPreferences` | Three integer sRGB channels, each 0–255; invalid/missing values fall back to 24,24,24 |
| `actionsConfigPath` | `ActionsConfigurationStore` | Previously selected config path, otherwise the app's standard support-folder file |

**Best Fit** shrinks to fit and does not enlarge beyond 100%. It refits on window resize. **Actual Size** uses 100% with scrolling. **Scale to Fit** uses up to 90% of the visible screen, enlarges small images and caps magnification at 20×. Its stored raw value stays `autoSize` for compatibility. Manual zoom does not change the selected persistent mode.

## Backgrounds

The default pattern alternates opaque sRGB **32,32,32** and **40,40,40** in 12-point squares. Black is 0,0,0; White is 255,255,255; Very Dark Gray is 24,24,24. Custom RGB is stored independently, so switching presets does not discard the user's custom color.

`BackgroundMenuController` owns menu choices and the custom editor. The editor accepts integer RGB input or the native macOS color picker and validates all channels before Apply. Cancel leaves stored settings unchanged. Apply persists and updates all image windows.

`ImageContentView` draws the background in viewport coordinates, underneath a transparent scroll/clip view. Pattern tiles retain their size while the image zooms; gutters and transparent image pixels reveal the same backdrop. This changes presentation only, with no image file writes.

## Actions data and execution

The default file is `~/Library/Application Support/Glimpse/actions.json`. The Actions menu shows configured actions and one permanent management item: **Edit Command Config…**. It opens the actual file in TextEdit. Returning to Glimpse reloads it. Saving a blank/whitespace-only file regenerates defaults; valid JSON with an empty `actions` array deliberately means no actions and is preserved.

The version-1 JSON contains `version`, optional human-readable `notes`, and an `actions` array. Default actions are **Copy Image Path** and **Open Image Location**. New defaults include a note explaining blank-file reset. Older configs without notes remain valid. Invalid nonblank JSON is not overwritten: the menu displays a config error while editing stays available.

| Action kind | App-side behavior |
| --- | --- |
| `copyImagePath` | Write the selected image path to the clipboard |
| `openImageLocation` | Reveal the selected image in Finder |
| `openURL` | Open a fixed-host HTTPS template; confirm when file information is included |
| `runCommand` | Confirm and run a fixed absolute executable with separate arguments |

`ImageAction` expands `{filename}` and `{filepath}` once. Command arguments remain literal argument-array values; URL values are percent encoded. Validation checks size/count limits, IDs/titles, placeholders, fixed HTTPS hosts and executable paths. The core store uses bounded regular-file reads and serializes config I/O.

`ActionRunner` is the only executor. It revalidates the action and resolved executable, rejects quarantined executables and common inline shell/interpreter code, and asks before each command. Configured scripts are still trusted code with the user's privileges. There is no command sandbox. Four direct children may run concurrently; after 30 seconds the app requests termination, which does not guarantee descendant processes exit.

For complete user-editable examples, see [the Actions instructions](../docs/ACTIONS.md). Add a new action kind by updating its core model/validation first, then its app executor and tests; do not embed command execution in the viewer or config parser.
