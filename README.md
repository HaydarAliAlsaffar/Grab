# Grab

A personal macOS menu bar app for downloading video and audio from any site
yt-dlp supports. Native SwiftUI with Liquid Glass. macOS 26 or later, Apple Silicon.

## Build and install

```
./build.sh
```

The script does a release build, wraps the binary into Grab.app, ad-hoc signs
it, installs it to /Applications, and relaunches it. It uses the Xcode
toolchain when /Applications/Xcode.app exists, which is required for SwiftUI
macros. No Xcode project is needed. Swift 6.2 or later.

## Requirements

- yt-dlp and ffmpeg from Homebrew. On first launch the panel offers an
  Install button that runs `brew install yt-dlp ffmpeg`.
- yt-dlp is upgraded in the background once a week. Settings has an
  Update Downloader button as well.

## Use

- Click the menu bar icon, paste a link, pick a quality and format, and
  press Export. Trim cuts a section. Skip sponsors appears for YouTube links.
- Control-Option-Command-D downloads the clipboard link as video at the
  default quality and format. Control-Option-Command-A downloads audio only.
  Both are remappable in Settings.
- Recent downloads can be clicked to reveal in Finder or dragged into other
  apps.

## Notes

- Files are saved to Downloads by default. Change the folder in Settings.
- Audio exports embed the thumbnail as cover art and fill in title, artist,
  and album when the site provides them.
- Errors are written to ~/Library/Logs/Grab/grab.log, including the link
  and yt-dlp's error output. Nothing is sent anywhere.

The full product spec is in CLAUDE.md.

## License

MIT. See LICENSE.
