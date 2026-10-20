# Grab

A personal macOS menu bar app for downloading video and audio from any site
yt-dlp supports. Built from scratch in this folder. Native SwiftUI, Liquid Glass.

## Owner preferences
- No em dashes anywhere in UI text. Use periods, commas, or a spaced hyphen.
- Short, plain UI copy. Buttons are verbs ("Export", "Show in Finder").
- Build and launch the real app after every step to check it. Test a real
  download before calling any download feature done.

## Platform and stack
- macOS 26 or later (Liquid Glass APIs). Apple Silicon.
- Swift Package (executable target) edited in VS Code. No Xcode project.
- `build.sh` compiles with `swift build -c release`, wraps the binary into
  `Grab.app` with an Info.plist (`LSUIElement` true, bundle id `com.ali.grab`),
  ad-hoc signs it (`codesign --force --sign -`), installs to /Applications,
  and relaunches it.
- Engine: `yt-dlp` for downloading, `ffmpeg` for merging, trimming, and
  converting. Both required.

## First launch setup
- Look for yt-dlp and ffmpeg in /opt/homebrew/bin and /usr/local/bin.
- If either is missing, show a setup card in the panel with one "Install"
  button that runs `brew install yt-dlp ffmpeg` and shows progress. If
  Homebrew itself is missing, say so and link to brew.sh.
- Update yt-dlp weekly in the background (`brew upgrade yt-dlp`), plus an
  "Update Downloader" button in Settings.

## Global shortcuts
- Register with Carbon `RegisterEventHotKey` (needs no Accessibility permission).
- Control-Option-Command-D: download the clipboard link as video at the
  default quality and format.
- Control-Option-Command-A: download the clipboard link as audio only at the
  default audio format.
- Do NOT use Option-Command-D (macOS Dock show/hide) or Option-Command-A
  (Finder deselect all).
- Both shortcuts are remappable in Settings.
- Shortcuts never open the panel. Feedback is the menu bar progress ring plus
  a notification when done. If the clipboard has no link, notify
  "Copy a link first."
- Shortcuts always grab just the single video, never a playlist (`--no-playlist`).

## Menu bar icon
- SF Symbol `arrow.down.circle` when idle.
- While downloading, the icon becomes a small progress ring that fills.
  MenuBarExtra labels only take Image or Text, so render the ring to an
  NSImage (ImageRenderer) and update it as progress changes.

## Panel (MenuBarExtra with .window style)
Liquid Glass throughout: `.glassEffect()` on the panel sections and cards,
`GlassEffectContainer` to group them, `.buttonStyle(.glass)` and
`.glassProminent` for the main action. Follow system light and dark mode.

Top to bottom:
1. **Link field.** Paste a link. On paste, run `yt-dlp -J --no-playlist <url>`
   and show a preview card: thumbnail, title, uploader, length. Show a
   loading state while it fetches and a clear error if the link fails.
2. **Quality picker.** Built from the formats in that JSON. Only list heights
   the video actually has, from 2160p down to 480p, plus "Audio only".
3. **Format picker.** Video: MP4 or MOV. Audio: M4A or MP3.
4. **Trim.** A range slider across the video length with editable start and
   end time fields. Off by default (full video). When on, use
   `--download-sections "*START-END" --force-keyframes-at-cuts` so cuts are
   frame accurate.
5. **Skip sponsors toggle.** Uses `--sponsorblock-remove sponsor`. Default
   value comes from Settings. Only show it for YouTube links.
6. **Export button.** Turns into a progress bar with a Cancel button while
   running. Cancel kills the process and cleans up partial files.
7. **Recent downloads.** Last 6 files with thumbnail and name. Click to show
   in Finder. Each row is draggable (`.draggable` with the file URL) so the
   file can be dropped straight into Messages, CapCut, Finder, and so on.
   Hide rows whose file no longer exists.
8. Gear icon in the corner opens Settings.

## Settings
- Default video quality and format (used by the video shortcut).
- Default audio format (used by the audio shortcut).
- Save folder (default ~/Downloads).
- Skip sponsors by default (on or off).
- Shortcut remapping for both shortcuts.
- Launch at Login (`SMAppService.mainApp`).
- Update Downloader button and the installed yt-dlp version.
Store with @AppStorage.

## Download details
- Output template: `<save folder>/%(title).150B.%(ext)s`.
- Video: `-f "bv*[height<=H]+ba/b[height<=H]"`, then `--merge-output-format`
  mp4 or mov (remux, re-encode only if needed).
- Audio: `-x --audio-format m4a|mp3`.
- Progress: `--newline --progress-template "download:GRAB %(progress._percent_str)s"`
  and parse it. Get the final path with `--print after_move:filepath`
  (add `--progress` since --print implies quiet).
- **Duplicate check:** before downloading, get the expected filename
  (`--print filename` with the same options). If that file exists, notify
  "Already downloaded" with a Show in Finder action instead of downloading.
- Notifications via UNUserNotificationCenter. Clicking "Saved" reveals the
  file in Finder.
- One download at a time from the panel. A shortcut press during a download
  waits its turn.

## Build order
1. Package, build.sh, empty MenuBarExtra panel with Liquid Glass styling.
2. yt-dlp and ffmpeg detection and the setup card.
3. Link field, `-J` fetch, preview card.
4. Quality and format pickers, Export with progress and Cancel.
5. Trim.
6. Recent downloads with drag out, duplicate check, notifications.
7. Global shortcuts and the menu bar progress ring.
8. Settings, SponsorBlock, Launch at Login, weekly updates.

## Not in scope
Timestamp links auto-filling trim, browser cookie sign-in, playlist
downloads, a download queue.
