# Actions configuration

**Actions → Edit Command Config…** is the only management item and always stays in the menu, including when the JSON is invalid or has no actions. By default it edits `~/Library/Application Support/Glimpse/actions.json` in TextEdit. Save as plain UTF-8 JSON. Returning to Glimpse reloads it. Invalid nonblank configuration displays an error rather than running old actions and is not overwritten.

To reset, select all text, delete it and **save a blank file**. When you return to Glimpse, it regenerates these defaults. Whitespace-only files also reset. Valid JSON with `"actions": []` keeps an empty menu rather than resetting. Save a copy of your customized config first if you want to keep it.

```json
{
  "version": 1,
  "notes": "To reset the actions, save a blank file and Glimpse will regenerate the defaults.",
  "actions": [
    { "id": "copy-image-path", "title": "Copy Image Path", "kind": "copyImagePath" },
    { "id": "open-image-location", "title": "Open Image Location", "kind": "openImageLocation" }
  ]
}
```

The `notes` field is human-readable documentation, not a command. Older configs without it remain valid. If you previously selected another config file in an older Glimpse build, Edit Command Config still opens that remembered path and clearing it resets that file.

Add HTTPS links using `openURL`, or a fixed absolute executable and separate arguments using `runCommand`. Available placeholders are `{filename}` (basename including extension) and `{filepath}` (absolute path). Filenames remain literal arguments, and URL substitutions are percent encoded. For example, append these objects to `actions`:

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

Treat config files and scripts as trusted executable configuration: a command can access everything your user account can, use the network, or change files. The checks do not make arbitrary downloaded commands safe. Glimpse does not remove quarantine or grant elevated privileges. Configuration is capped at 64 KB and 64 actions with unique IDs and short titles. Only the two documented placeholders are accepted.
