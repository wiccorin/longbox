# Longbox

A comic and manga reader for iPhone. Opens your own .cbz and .cbr files, keeps your place, and reads paged, vertical, or right-to-left.

## Features

- Add .cbz and .cbr files from the Files app, or with "Open in Longbox"
- Library with covers, progress, and a Continue Reading shortcut
- Three reading modes per book: left to right, right to left (manga), vertical scroll
- Tap the edges to turn pages, tap the middle for controls, pinch or double-tap to zoom
- Everything stays on the device. No accounts, no network access.

## Install from Windows

1. Download `Longbox.ipa` from the [latest release](../../releases/latest).
2. Install [Sideloadly](https://sideloadly.io) on your PC. It asks for the non-Microsoft-Store versions of iTunes and iCloud; install those when prompted.
3. Plug in your iPhone and trust the computer.
4. Drag `Longbox.ipa` into Sideloadly, enter your Apple ID, and press Start.
5. On the iPhone: Settings > General > VPN & Device Management, trust your Apple ID.
6. On iOS 16 or later: Settings > Privacy & Security > Developer Mode, turn it on and restart.

With a free Apple ID the app stops opening after 7 days. Run Sideloadly again to refresh it; your library is kept.

## Build

The GitHub Actions workflow in `.github/workflows/build.yml` builds an unsigned IPA on every push to `main` and publishes it as the `latest` release. To build locally on a Mac: `brew install xcodegen && xcodegen generate`, then open `Longbox.xcodeproj`.

## Credits

Uses [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) and [Unrar.swift](https://github.com/mtgto/Unrar.swift) (which includes UnRAR source by Alexander Roshal).
