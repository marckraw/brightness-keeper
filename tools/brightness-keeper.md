# Brightness Keeper

Known-good command for this MacBook Pro plus LG setup:

```sh
./tools/brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

Run every hour:

```sh
./tools/brightness-keeper --level 100 --interval 3600 --display-services --m1ddc --m1ddc-display 1
```

Install the LaunchAgent after one-shot control works:

```sh
./tools/install-brightness-keeper.sh 100 3600 --display-services --m1ddc --m1ddc-display 1
```

Required helper:

```sh
brew install m1ddc
```

Helpers that failed or are excluded for this machine:

```sh
brew uninstall brightness ddcctl
brew uninstall --cask lunar
```

The `--fallback-keys` option has been removed because repeated synthetic brightness-key events can behave unpredictably.

See `../README.md` for full setup, cleanup, options, and troubleshooting notes.
