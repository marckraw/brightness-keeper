# Brightness Keeper

Brightness Keeper is a small macOS utility that keeps selected displays at a target brightness. It was built for a MacBook Pro plus LG external display setup where macOS did not reliably keep brightness at 100%.

The final working setup for this machine is:

- Built-in MacBook Pro display: local Apple `DisplayServices.framework` call
- LG external display: `m1ddc`

The known-good command is:

```sh
brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

## Install

Install the external display helper:

```sh
brew install m1ddc
```

Install Brightness Keeper without cloning the repo:

```sh
curl -fsSL https://raw.githubusercontent.com/marckraw/brightness-keeper/master/install.sh | zsh
```

The installer puts the project under:

```text
~/.local/share/brightness-keeper
```

and symlinks these commands into `~/.local/bin`:

```text
brightness-keeper
brightness-keeper-install-agent
brightness-keeper-uninstall-agent
```

If `~/.local/bin` is not in your `PATH`, add it to your shell profile or run the commands with the full path.

Uninstall:

```sh
curl -fsSL https://raw.githubusercontent.com/marckraw/brightness-keeper/master/uninstall.sh | zsh
```

## Fresh Setup Check

Test the external LG display directly:

```sh
m1ddc display 1 set luminance 100
```

Test the built-in display directly through Brightness Keeper:

```sh
brightness-keeper --level 100 --display-services-only
```

If both commands work, test the combined command:

```sh
brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

If you have two external LG displays:

```sh
brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1,2
```

## Usage

Run once:

```sh
brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

Keep brightness pinned every hour:

```sh
brightness-keeper --level 100 --interval 3600 --display-services --m1ddc --m1ddc-display 1
```

Use another brightness value:

```sh
brightness-keeper --level 85 --display-services --m1ddc --m1ddc-display 1
```

Run diagnostics:

```sh
brightness-keeper --diagnose
```

Install as a background LaunchAgent after the one-shot command works:

```sh
brightness-keeper-install-agent 100 3600 --display-services --m1ddc --m1ddc-display 1
```

Uninstall the LaunchAgent:

```sh
brightness-keeper-uninstall-agent
```

## From A Cloned Repo

You can also run directly from a clone:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

Open the Finder-clickable one-shot command from a clone:

```sh
open "tools/Brightness 100.command"
```

## CLI Options

Core options:

- `--level`, `-l`: target brightness. Accepts `0.0-1.0` or `0-100`. Default: `100`.
- `--interval`, `-i`: re-apply brightness every N seconds. If omitted, runs once.
- `--once`: run once, even if `--interval` was set earlier.
- `--diagnose`: print display and helper diagnostics.
- `--quiet`, `-q`: only print errors.
- `--help`, `-h`: show usage.

Working options for this setup:

- `--display-services`: set the built-in display with local Apple DisplayServices APIs.
- `--display-services-only`: only use DisplayServices.
- `--m1ddc`: set external DDC/CI displays with `m1ddc`.
- `--m1ddc-only`: only use `m1ddc`.
- `--m1ddc-display <indexes>`: `m1ddc` display index, repeatable or comma-separated.

## Local Dependencies

Only this helper is needed for the confirmed working setup:

```sh
brew install m1ddc
```

Confirm the final helper state:

```sh
brew list --formula | grep '^m1ddc$'
```

## Privacy And Network Access

The final working setup does not require any full app helper. The built-in display is controlled locally through Apple DisplayServices APIs, and the LG display is controlled locally through `m1ddc`.

`m1ddc` is a small command-line DDC/CI tool. It does not need network access for brightness control.

The tool does not make network requests. It calls local macOS display APIs and, when requested, executes the local `m1ddc` binary.

## How It Works

The main implementation is `tools/brightness-keeper.swift`.

It can try direct macOS display APIs:

- `DisplayServicesSetBrightness` from Apple's private DisplayServices framework
- `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey`
- `CoreDisplay_Display_SetUserBrightness` from Apple's private CoreDisplay framework

For this setup, the reliable path is:

- DisplayServices controls the built-in MacBook Pro display locally.
- `m1ddc` controls LG external monitors over DDC/CI.

The shell wrapper `tools/brightness-keeper` runs the Swift file and redirects Swift/Clang module caches into the temporary directory. That avoids permission problems when the tool runs in restricted shells or as a LaunchAgent.

## Files

```text
install.sh                         No-clone installer
uninstall.sh                       No-clone uninstaller
docs/distribution.md               Distribution notes and next packaging options
tools/brightness-keeper              Shell wrapper for the Swift CLI
tools/brightness-keeper.swift        Brightness control implementation
tools/Brightness 100.command         Finder-clickable one-shot command
tools/install-brightness-keeper.sh   LaunchAgent installer
tools/uninstall-brightness-keeper.sh LaunchAgent uninstaller
tools/brightness-keeper.md           Short usage notes
```

## References

- `m1ddc`: https://github.com/waydabber/m1ddc
- Apple Support, "Change your Mac display's brightness": https://support.apple.com/guide/mac-help/mchlp2704/mac
- Apple DisplayServices usage background: https://stackoverflow.com/questions/65150131/iodisplayconnect-is-gone-in-big-sur-of-apple-silicon-what-is-the-replacement
