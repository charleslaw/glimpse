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

The version-1 JSON contains `version`, an `actions` array, and documentation fields `notes`, `variables` and `examples`. Default actions are **Copy Image Path** (`echo "{filepath}" | pbcopy`) and **Open Image Location** (`open {parentpath}`), both encoded with only `label` and `cmd`. Opening the config in the editor restores the standard documentation in valid configs, preserving custom actions and unknown user fields. The variable dictionary describes built-in tokens; the examples array of `label`/`cmd` objects is not executable. Older configs without these fields remain valid. Invalid nonblank JSON is kept for repair: the app shows an actionable error once per distinct failure, falls back to the two default actions, and keeps editing available. A successful load clears the failure state. Config files live outside the app bundle and survive app replacement/reinstallation.

The actions array accepts the original structured objects, strings such as `"chrome {filename}"`, and compact objects such as `{"label":"Open dir","cmd":"open {parentpath}"}`. `ImageAction` normalizes these into one execution model and generates stable positional IDs when omitted. `ActionPipeline` parses quoting, escapes and unquoted pipes into at most four `ActionCommand` stages before any filename expansion; it never evaluates a shell.

| Action kind | App-side behavior |
| --- | --- |
| `copyImagePath` | Write the selected image path to the clipboard |
| `openImageLocation` | Reveal the selected image in Finder |
| `openURL` | Open a fixed-host HTTPS template; confirm when file information is included |
| `runCommand` | Confirm and run a fixed absolute executable with separate arguments |

`ActionPlaceholders` expands `{filename}`, `{filepath}`, and `{parentpath}` once. The store migrates earlier abbreviated placeholders and built-in action objects, validates before writing, and preserves custom fields; invalid configs remain intact. Command arguments remain literal argument-array values; URL values are percent encoded. Validation checks size/count limits, IDs/titles, placeholders, fixed HTTPS hosts and executable paths. The core store uses bounded regular-file reads and serializes config I/O.

`ActionRunner` owns execution policy and confirmation. Core `ProcessPipeline` owns native process/pipe lifecycle for already validated stages, keeping this I/O separate from configuration parsing. `ActionCommand` resolves bare executables in fixed system/Homebrew directories, never in the image directory; `chrome` maps to macOS `open` with Google Chrome's bundle ID. The runner revalidates the resolved executable, rejects quarantined executables and common inline shell/interpreter code, and asks before each action, showing every expanded stage. Parsing precedes substitution, so a filename containing `|` cannot add a pipeline stage. `ProcessPipeline` starts consumers before producers, closes parent pipe handles for EOF, and terminates started children after a partial launch failure. Its working directory is the image's parent, allowing basename placeholders. Configured scripts are still trusted code with the user's privileges. There is no command sandbox. Four actions may run concurrently, each with up to four direct child processes; after 30 seconds the app requests termination, which does not guarantee descendant processes exit.

`google-lens {filepath}` is a reserved helper handled by the app before executable resolution. It opens Lens and reveals the selected image for the user to upload/drag into the browser. It accepts selected-image tokens only. It does not upload file bytes, automate a browser upload, or treat a local path as a publicly reachable URL.

For complete user-editable examples, see [the Actions instructions](../docs/ACTIONS.md). Add a new action kind by updating its core model/validation first, then its app executor and tests; do not embed command execution in the viewer or config parser.
