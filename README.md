# Brightness Keeper

Brightness Keeper is a small macOS utility for forcing display brightness back to a chosen level. It was created during this session as a standalone repo at:

```text
/tmp/brightness-keeper-repo
```

The requested final location is:

```text
/Users/marckraw/Projects/Private/brightness-keeper
```

This Codex session could not create that directory directly because the sandbox rejected writes to `/Users/marckraw/Projects/Private` with `Operation not permitted`. Move the repo there from a normal Terminal session:

```sh
mv /tmp/brightness-keeper-repo /Users/marckraw/Projects/Private/brightness-keeper
```

The Git branch is initialized as `master`.

## Why This Exists

macOS sometimes does not leave displays at the brightness level you expect, especially when automatic brightness, True Tone, external display control, docks, or monitor firmware are involved. This utility gives you two practical modes:

- Run once and force the brightness target now.
- Keep running and re-apply the target every few seconds.

It is intended as a pragmatic local tool, not a polished app.

## Usage

Run once:

```sh
./tools/brightness-keeper --level 100
```

Keep brightness pinned to 100% every 10 seconds:

```sh
./tools/brightness-keeper --level 100 --interval 10
```

Use another brightness value:

```sh
./tools/brightness-keeper --level 85 --interval 15
```

Open the Finder-clickable one-shot command:

```sh
open "tools/Brightness 100.command"
```

Install as a background LaunchAgent:

```sh
./tools/install-brightness-keeper.sh 100 10
```

Uninstall the LaunchAgent:

```sh
./tools/uninstall-brightness-keeper.sh
```

Run diagnostics:

```sh
./tools/brightness-keeper --diagnose
```

## How It Works

The main implementation is `tools/brightness-keeper.swift`.

It tries direct macOS display control first:

- `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey`
- `CoreDisplay_Display_SetUserBrightness` from Apple’s private CoreDisplay framework

The wrapper script `tools/brightness-keeper` runs the Swift file and redirects Swift/Clang module caches into the temporary directory. That avoids permission problems when the tool runs in restricted shells.

For 100% brightness only, the tool can use a fallback:

```sh
./tools/brightness-keeper --level 100 --fallback-keys
```

That fallback sends repeated macOS brightness-up key events through AppleScript/System Events. macOS may ask for Accessibility permission for Terminal or the app that launches it.

The clickable command `tools/Brightness 100.command` uses this fallback automatically.

## Important Limitations

From inside the Codex sandbox, diagnostics reported:

```text
Active displays: 0
IODisplayConnect services: 0
CoreDisplay SetUserBrightness available: true
```

That means the sandbox could run and validate the CLI, but it could not see the real logged-in display session. Verify hardware brightness from your normal macOS Terminal session.

Some external displays do not accept brightness changes through macOS display APIs. Many non-Apple monitors need DDC/CI control instead. If this utility cannot control an external monitor directly, check:

- Whether the monitor supports DDC/CI.
- Whether DDC/CI is enabled in the monitor’s on-screen menu.
- Whether the display is connected through a dock, adapter, or DisplayLink path that blocks or virtualizes monitor control.
- Whether a dedicated tool such as `ddcctl`, MonitorControl, BetterDisplay, or DisplayLink Manager is needed.

## Files

```text
tools/brightness-keeper              Shell wrapper for the Swift CLI
tools/brightness-keeper.swift        Brightness control implementation
tools/Brightness 100.command         Finder-clickable one-shot command
tools/install-brightness-keeper.sh   LaunchAgent installer
tools/uninstall-brightness-keeper.sh LaunchAgent uninstaller
tools/brightness-keeper.md           Short usage notes
```

## Internet References

These are the references used while deciding how the tool should behave:

- Apple Support, “Change your Mac display’s brightness”: documents manual brightness controls, automatic brightness, and Apple’s note that turning off automatic brightness can affect energy use and display performance.  
  https://support.apple.com/guide/mac-help/mchlp2704/mac

- Apple Support, “Use True Tone on Mac”: documents that True Tone can adjust display color and intensity based on ambient light, including support details for some external displays.  
  https://support.apple.com/102147

- `ddcctl` GitHub repository: command-line DDC monitor control for macOS, including external monitor brightness and contrast.  
  https://github.com/kfix/ddcctl

- MacPorts `ddcctl` page: confirms `ddcctl` as a macOS command-line tool for DDC monitor brightness control.  
  https://ports.macports.org/port/ddcctl/

- DisplayLink Support, “Brightness and Contrast Control settings”: documents that DisplayLink brightness/contrast control depends on DisplayLink Manager, macOS version, DisplayLink hardware, and a DDC/CI-compliant monitor.  
  https://support.displaylink.com/knowledgebase/articles/2021015

## Next Improvements

- Add optional `ddcctl` integration for external monitors that do not respond to Apple display APIs.
- Package this as a `.app` or menu bar app if the CLI proves useful.
- Add a LaunchAgent mode that uses `--fallback-keys` for 100% setups where direct API control fails.
