# Actions configuration

**Actions → Edit Command Config…** is the only management item and always stays in the menu, including when the JSON is invalid or has no actions. By default it edits `~/Library/Application Support/Glimpse/actions.json` in TextEdit. Save as plain UTF-8 JSON. Returning to Glimpse reloads it. Bad configuration shows an error with a repair hint, then uses the two default actions: Copy Image Path and Open Image Location. The bad file is kept for editing. The same error is reported once until it changes or a valid config loads.

To reset, select all text, delete it and **save a blank file**. When you return to Glimpse, it regenerates these defaults. Whitespace-only files also reset. Valid JSON with `"actions": []` keeps an empty menu rather than resetting. Save a copy of your customized config first if you want to keep it.

```json
{
  "version": 1,
  "notes": "To reset the actions, save a blank file and Glimpse will regenerate the defaults.",
  "variables": {
    "{filename}": "The image's filename, including extension, without its directory.",
    "{filepath}": "The full local path to the image file.",
    "{fname}": "Alias for {filename}: the filename without its directory.",
    "{fpath}": "Alias for {filepath}: the full local path to the image file.",
    "{ppath}": "The full path to the image's parent directory; open {ppath} opens that folder."
  },
  "examples": {
    "Open directory": "open {ppath}",
    "Open in Chrome": "chrome {fname}",
    "Google image search": "google-lens {filepath}"
  },
  "actions": [
    { "id": "copy-image-path", "title": "Copy Image Path", "kind": "copyImagePath" },
    { "id": "open-image-location", "title": "Open Image Location", "kind": "openImageLocation" }
  ]
}
```

The `notes`, `variables`, and `examples` fields are maintained documentation. Every time **Edit Command Config…** opens a valid JSON object, Glimpse inserts or restores their standard values. `variables` describes the built-in substitutions; it does not define new variables. `examples` lists copyable commands and does not execute them. Actions and other user fields are preserved. Invalid nonblank JSON still opens for repair without being replaced. Older configs without these fields remain valid. If you previously selected another config file in an older Glimpse build, Edit Command Config still opens that remembered path and clearing it resets that file.

The config is stored outside `Glimpse.app`, so replacing, updating or reinstalling the app preserves it. Deleting the Application Support file yourself or intentionally saving it blank resets it.

## Simple commands

Add command strings or `label`/`cmd` objects to the `actions` array alongside the two built-ins:

```json
{
  "version": 1,
  "actions": [
    { "id": "copy-image-path", "title": "Copy Image Path", "kind": "copyImagePath" },
    { "id": "open-image-location", "title": "Open Image Location", "kind": "openImageLocation" },
    "chrome {fname}",
    { "label": "Open dir", "cmd": "open {ppath}" },
    { "label": "Open in Preview", "cmd": "open -a Preview {fpath}" },
    { "label": "Google image search", "cmd": "google-lens {filepath}" }
  ]
}
```

Object commands need only `label` and `cmd`; IDs are generated from array positions when omitted. A string uses the command text as its menu label. Quotes group arguments, for example `open -a "Google Chrome" {fpath}`. Parse the template first, then substitute file values: an unquoted `{fpath}` still remains one argument when the path contains spaces or quotes.

| Placeholder | Value |
| --- | --- |
| `{fname}` / `{filename}` | Filename, including extension |
| `{fpath}` / `{filepath}` | Full image path |
| `{ppath}` | Full parent-directory path |

Commands run with the image's parent directory as their working directory, so `chrome {fname}` works with a relative filename. `chrome` is a convenience alias for opening with the installed Google Chrome app via macOS. Other bare executables are searched in `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/opt/homebrew/bin`, then `/usr/local/bin`. The image directory is never searched for executables. Use an absolute executable path for programs elsewhere. For filenames that might begin with `-`, prefer the absolute `{fpath}` or the command's `--` option terminator.

No shell evaluates the command string. Quotes/backslash escapes tokenize arguments; pipes, redirects, `$variables`, command substitution and globs are not executed or expanded. Use a trusted script file for more involved operations and pass file placeholders as separate arguments.

### Google image search

`google-lens {filepath}` is a built-in helper, not an external program you need to install. It opens Google Lens and reveals the selected image in Finder. Drag that image into Lens or use Upload a file to finish the visual search. The helper itself does not upload the image; submission happens in the browser. It accepts only the selected-image placeholder (or no arguments), not arbitrary files. Google describes the supported [upload/drag-and-drop workflow](https://support.google.com/websearch/answer/1325808?co=GENIE.Platform%3DDesktop&hl=en).

A local `{filepath}` cannot be passed as a public image URL: Google's servers cannot read files from your Mac. An ordinary Google text search for `{fname}` searches the name, not the image's visual contents.

## Structured commands and links

The existing `openURL` and `runCommand` formats remain supported. Filenames remain literal arguments, and URL substitutions are percent encoded. For example, append these objects to `actions`:

```json
{ "id": "search-name", "title": "Search Image Name", "kind": "openURL",
  "url": "https://www.google.com/search?q={filename}" }
```

```json
{ "id": "print", "title": "Send to Default Printer", "kind": "runCommand",
  "executable": "/usr/bin/lp", "arguments": ["--", "{filepath}"] }
```

The first searches the filename; it does not upload an image or perform Google Lens visual search. Visual search would require an explicit upload integration. The second uses the system's configured default printer and supported file formats.

Command actions ask before each execution, showing the executable and expanded arguments. Links containing file information ask before opening. No actions run on image open. Commands use `Process` with an argument array, without shell parsing. Quarantined executables and common inline shell/interpreter code are rejected. For more complex commands, configure a trusted script file and pass the image path as a separate argument; never construct executable code from filenames. Commands are limited to four concurrent direct children; after 30 seconds Glimpse requests termination. This is not a hard execution sandbox or a guarantee that descendants exit.

Treat config files and scripts as trusted executable configuration: a command can access everything your user account can, use the network, or change files. The checks do not make arbitrary downloaded commands safe. Glimpse does not remove quarantine or grant elevated privileges. Configuration is capped at 64 KB and 64 actions with unique IDs and short labels. Only the placeholders above are accepted.
