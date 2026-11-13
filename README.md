# Longbox

A comic and manga reader for iPhone. Opens your own .cbz and .cbr files, keeps your place, and reads paged, vertical, or right-to-left.

## Features

- Add .cbz and .cbr files from the Files app, or with "Open in Longbox"
- Library with covers, progress, and a Continue Reading shortcut
- Three reading modes per book: left to right, right to left (manga), vertical scroll
- Tap the edges to turn pages, tap the middle for controls, pinch or double-tap to zoom in every mode
- Page scrubber with a thumbnail preview
- Reading time, per comic and in total, plus a reading streak
- Drop folder: put files in the Longbox folder (Files app, or USB from a computer) and they import on launch
- Folders tab: make your own collections; a comic can be in several, and subfolders in the drop folder become folders
- Series stacks: issues of one series group together in reading order, with the next issue offered when you finish
- Trim margins, and two pages side by side in landscape
- Panel view: step through a page panel by panel
- Search, sort by release date, and a details screen with author, publisher, year, description and chapters
- Reads details and chapters from `ComicInfo.xml` and folders inside the file; you can also mark your own chapters
- Your comics stay on the device. The only network use is the optional "Find details" lookup, which sends your search text to Google Books.

## Install from Windows

1. Download `Longbox.ipa` from the [latest release](../../releases/latest).
2. Install [Sideloadly](https://sideloadly.io) on your PC. It asks for the non-Microsoft-Store versions of iTunes and iCloud; install those when prompted.
3. Plug in your iPhone and trust the computer.
4. Drag `Longbox.ipa` into Sideloadly, enter your Apple ID, and press Start.
5. On the iPhone: Settings > General > VPN & Device Management, trust your Apple ID.
6. On iOS 16 or later: Settings > Privacy & Security > Developer Mode, turn it on and restart.

## Adding comics from a PC

Plug in the iPhone, open Apple Devices (or iTunes) on Windows, pick the phone, go to Files, and drag .cbz or .cbr files onto Longbox. They import the next time Longbox opens.

With a free Apple ID the app stops opening after 7 days. Run Sideloadly again to refresh it; your library is kept.

## Build

The GitHub Actions workflow in `.github/workflows/build.yml` builds an unsigned IPA on every push to `main` and publishes it as the `latest` release. To build locally on a Mac: `brew install xcodegen && xcodegen generate`, then open `Longbox.xcodeproj`.

## Credits

Uses [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) and [Unrar.swift](https://github.com/mtgto/Unrar.swift) (which includes UnRAR source by Alexander Roshal). Display type is [Bangers](https://github.com/google/fonts/tree/main/ofl/bangers) under the SIL Open Font License.
