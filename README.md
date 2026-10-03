# SnagFrog for Godot 4

In-game bug reports for Godot 4. One call (or one key) captures a screenshot, the tail of the
log file and diagnostics, stages them on [SnagFrog](https://snagfrog.com), and opens the report
page in the player's browser. The player describes the problem, optionally leaves an email, and
you can reply to them from the dashboard.

Works on Windows, macOS and Linux exports. Web exports are best effort: the browser may block a
tab opened after a network request and the sessions API is not CORS-enabled, so on web the addon
skips staging and opens the prefilled report page link directly (no screenshot or log). Mobile is
untested.

## Install

1. Download [snagfrog-godot.zip](https://snagfrog.com/downloads/snagfrog-godot.zip) (or the latest
   [GitHub release](https://github.com/gorgekara/snagfrog-godot/releases)) and copy its
   `addons/snagfrog` folder into your project's `addons/` folder.
2. **Project → Project Settings → Plugins**: enable **SnagFrog**. This registers the `SnagFrog`
   autoload and adds the `snagfrog/*` project settings.
3. In **Project Settings** fill in `snagfrog/app_slug` and
   `snagfrog/public_key` from your app's **Install** tab in the SnagFrog dashboard.

| Setting | Default | |
| --- | --- | --- |
| `snagfrog/app_slug` | | Your app's slug (required) |
| `snagfrog/public_key` | | The app's publishable key |
| `snagfrog/base_url` | `https://snagfrog.com` | Change if you self-host |
| `snagfrog/hotkey` | `F9` | Key that opens the report; empty disables it |
| `snagfrog/include_log` | `true` | Attach the last 256 KB of the log file |
| `snagfrog/include_screenshot` | `true` | Attach a screenshot |

The log is only attached when file logging is on (**Debug → File Logging → Enable File
Logging**).

## Use

```gdscript
# From your own pause-menu button:
SnagFrog.report()

# With extra diagnostics for this report:
SnagFrog.report({"level": "forest_3", "difficulty": "hard"})

# Values attached to every report from now on:
SnagFrog.set_context("save_slot", 2)

# Optional signals:
SnagFrog.report_opened.connect(func(url): print("Report page opened: ", url))
SnagFrog.report_failed.connect(func(error): push_warning("SnagFrog: " + error))
```

Pressing the hotkey (F9 by default; a single key, modifiers like Ctrl or Shift are ignored) calls
`SnagFrog.report()`. If staging fails (offline, wrong
key), `report_failed` fires, then `report_opened` fires as the report page still opens with the diagnostics in the URL, just
without the files.

## What is sent

- A screenshot of the game viewport (PNG, at most 1920 px on the long edge).
- The last 256 KB of the Godot log file, if file logging is enabled.
- Game name and version, engine version, OS name and version, device model, CPU architecture,
  locale, renderer, GPU, screen size, and anything you add with `set_context` or `report(extra)`.

Nothing is submitted by the addon. It only stages these files on a short-lived session. The player
sees what is attached on the report page and confirms (or opts out) before the report is created.
The public key is publishable: it can only create capture sessions for your app, and you can
rotate it from the dashboard.

## Try it

This folder is itself a minimal Godot project with the addon wired up. Open it in Godot, or run
`godot --headless --path .` from it for a smoke test.

## License

MIT
