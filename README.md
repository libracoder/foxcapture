# FoxCapture

Screen recorder that lives in your macOS menu bar: drag to select an area, or
grab the whole screen, and it records straight to MP4. Native SwiftUI, no
Electron, no cloud.

Third member of the fox family, built on the same principles as
[ClipboardFox](https://github.com/libracoder/clipboardfox) and
[FoxRecorder](https://github.com/libracoder/foxrecorder): a plain Swift
package, a tiny menu bar app, everything stays on your machine.

## Features

- **Area recording**: click Record Area, drag a rectangle on any screen,
  recording starts the moment you release — Esc cancels
- **Full-screen recording**: records the screen your pointer is on
- **Straight to MP4** via ScreenCaptureKit's recording output (H.264 or HEVC,
  30 or 60 fps) — no re-encoding step, the file is ready when you stop
- **System audio and microphone** can be muxed into the video, both optional
- **Menu bar control**: elapsed time in the bar; click the icon to stop
- **History**: recent recordings in the popover with play / reveal / delete;
  files are plain timestamped MP4s in `~/Movies/FoxCapture` (configurable)

## Build

```sh
./build.sh
open build/FoxCapture.app
```

Requires macOS 15+ and Xcode command line tools.

## Permissions

- **Screen Recording** (System Settings → Privacy & Security → Screen &
  System Audio Recording) — prompted on first recording
- **Microphone** — only if you enable mic narration

The app is signed with a stable identity, so permission grants survive
rebuilds.

## License

MIT
