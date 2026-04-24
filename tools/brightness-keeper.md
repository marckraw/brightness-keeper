# Brightness Keeper

Known-good command for this MacBook Pro plus LG setup:

```sh
brightness-keeper --level 100 --display-services --m1ddc --m1ddc-display 1
```

Run every hour:

```sh
brightness-keeper --level 100 --interval 3600 --display-services --m1ddc --m1ddc-display 1
```

Install the LaunchAgent after one-shot control works:

```sh
brightness-keeper-install-agent 100 3600 --display-services --m1ddc --m1ddc-display 1
```

Required helper:

```sh
brew install m1ddc
```

No-clone install:

```sh
curl -fsSL https://raw.githubusercontent.com/marckraw/brightness-keeper/master/install.sh | zsh
```

See `../README.md` for full setup, options, and troubleshooting notes.
