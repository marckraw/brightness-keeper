# Brightness Keeper

Brightness Keeper is a small macOS utility that keeps selected displays at a target brightness. It was built for a MacBook Pro plus LG external display setup where macOS did not reliably keep brightness at 100%.

The final working setup for this machine is:

- Built-in MacBook Pro display: local Apple `DisplayServices.framework` call
- LG external display: `m1ddc`

The known-good command is:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

## Fresh Setup

Clone the repo, then install the only required helper:

```sh
brew install m1ddc
```

Test the external LG display directly:

```sh
m1ddc display 1 set luminance 100
```

Test the built-in display directly through Brightness Keeper:

```sh
./tools/brightness-keeper --level 100 --display-services-only
```

If both commands work, test the combined command:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

If you have two external LG displays:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1,2
```

## Usage

Run once:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

Keep brightness pinned every hour:

```sh
./tools/brightness-keeper --level 100 --interval 3600 --display-services --m1ddc --m1ddc-display 1
```

Use another brightness value:

```sh
./tools/brightness-keeper --level 85 --display-services --m1ddc --m1ddc-display 1
```

Run diagnostics:

```sh
./tools/brightness-keeper --diagnose
```

Install as a background LaunchAgent after the one-shot command works:

```sh
./tools/install-brightness-keeper.sh 100 3600 --display-services --m1ddc --m1ddc-display 1
```

Uninstall the LaunchAgent:

```sh
./tools/uninstall-brightness-keeper.sh
```

Open the Finder-clickable one-shot command:

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

Troubleshooting-only options:

- `--brightness-cli`: use the Homebrew `brightness` CLI.
- `--brightness-only`: only use the Homebrew `brightness` CLI.
- `--brightness-display <indexes>`: `brightness` display index, repeatable or comma-separated.
- `--ddcctl`: use `ddcctl`.
- `--ddcctl-only`: only use `ddcctl`.
- `--ddcctl-display <indexes>`: `ddcctl` display index, repeatable or comma-separated.
- `--lunar`: use Lunar CLI.
- `--lunar-only`: only use Lunar CLI.
- `--lunar-display <selector>`: Lunar display selector. Default: `Built-in`.

The old `--fallback-keys` option has been removed. It sent repeated synthetic brightness-up key events and behaved unpredictably.

## Cleanup

Only this helper is needed for the confirmed working setup:

```text
m1ddc
```

These helpers were tested and should not be kept for this setup:

```text
brightness
ddcctl
lunar
```

Remove them with:

```sh
brew uninstall brightness ddcctl
brew uninstall --cask lunar
```

Confirm the final helper state:

```sh
brew list --formula | grep '^m1ddc$'
brew list --formula | grep -E '^(brightness|ddcctl)$' || true
brew list --cask | grep '^lunar$' || true
```

## Privacy And Network Access

The final working setup does not require Lunar or any full app helper. The built-in display is controlled locally through Apple DisplayServices APIs, and the LG display is controlled locally through `m1ddc`.

`m1ddc` is a small command-line DDC/CI tool. It does not need network access for brightness control.

Lunar was tested and worked, but it is not used in the final setup because the app may perform unrelated outbound requests for crash reporting, licensing, updates, and other app features. That does not fit this project's privacy requirement.

## What Failed Here

`ddcctl` detected the LG displays but failed before controlling them:

```text
Failed to parse WindowServer's preferences! (/Library/Preferences/com.apple.windowserver.plist)
Failed to acquire framebuffer device for display
```

On this macOS install, `/Library/Preferences/com.apple.windowserver.plist` is not present; the current display preferences are stored under `/Library/Preferences/com.apple.windowserver.displays.plist`. That makes `ddcctl` unsuitable here.

The Homebrew `brightness` CLI detected the built-in display but could not read its brightness:

```text
display 1: active, awake, online, built-in, ID 0x1
brightness: failed to get brightness of display 0x1 (error -536870201)
```

Lunar controlled the built-in display, but it is a full app with possible outbound network behavior, so it is excluded from the final setup.

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
- `brightness`: https://github.com/nriley/brightness
- `ddcctl`: https://github.com/kfix/ddcctl
- Lunar: https://lunar.fyi/
