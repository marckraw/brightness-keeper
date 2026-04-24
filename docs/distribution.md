# Distribution Notes

Brightness Keeper is currently distributed as a small script-based CLI. The first install path is a no-clone installer:

```sh
curl -fsSL https://raw.githubusercontent.com/marckraw/brightness-keeper/master/install.sh | zsh
```

That installer downloads the repository archive, installs the tool under `~/.local/share/brightness-keeper`, and creates command symlinks under `~/.local/bin`.

## Recommended Path

Use the no-clone installer first. It is simple, transparent, and matches how the project works today: the CLI is a Swift script executed by the system Swift runtime, plus the local `m1ddc` helper for external DDC/CI displays.

The next clean distribution step is a Homebrew tap:

```sh
brew install marckraw/tap/brightness-keeper
```

That would require a separate `marckraw/homebrew-tap` repository with a formula that depends on `m1ddc` and installs the wrapper plus Swift source. Homebrew's tap convention maps `brew tap user/repo` to a GitHub repo named `user/homebrew-repo`.

## Other Options

GitHub Releases can publish tagged release assets. The GitHub CLI supports creating a release from a tag and uploading files as release assets.

A signed and notarized `.pkg` or `.app` is the most native macOS distribution path, but it is heavier. Apple's notarization workflow is intended for Developer ID-signed macOS software distributed outside the App Store, and requires code-signing, hardened runtime, and notarization tooling. That is worth doing only if this grows beyond a small CLI.

## Sources

- Homebrew taps: https://docs.brew.sh/Taps
- GitHub CLI release creation: https://cli.github.com/manual/gh_release_create
- Apple notarization overview: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
