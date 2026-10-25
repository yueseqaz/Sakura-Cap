# Sakura-Cap

**[中文](README.md)** | **[English](README.en.md)** | **[日本語](README.ja.md)**

**A minimalist menu-bar screen recorder & screenshot tool for Mac.** Light, fast, and clean — one click on the menu bar to start recording; trim and annotate right after you stop; pull text out of screenshots in a single step.

Sakura-Cap focuses on doing one thing well: capturing your screen. No Dock icon, no extra windows, fast launch, low footprint. Tune resolution, microphone, camera, click highlighting and key display on the floating HUD before recording starts; jump straight into the trimmer when it ends; screenshots open directly in the annotation editor.

## Features

**Screen Recording**
- Full screen (single display / all displays in parallel, one file each), region, or window capture (system share picker)
- Floating HUD: armed first — press ▶ to actually start; pause / resume / stop mid-recording
- Adjust in place: output resolution (original / 1080p / 720p), microphone, system audio, camera, click indicator, key display
- Paused segments are removed from the timeline — the output is seamless
- Recording aids: mouse click indicator (pointer arrows), key display, start / stop sound cues, camera picture-in-picture, 3-second countdown

**Screenshots**
- Full-screen / region capture
- **OCR**: select an area, recognition runs offline via system Vision, text goes straight to your clipboard
- **Scrolling capture (long screenshot)**: after selecting the region, choose **Auto-scroll** or **Manual scroll**; frames are stitched vertically by overlap into one long image, with a live preview on the side
  - Auto-scroll runs hands-free; manual scroll stitches in real time as you scroll — switch between them at any time
  - The matching algorithm is robust to sub-pixel scroll offsets on Retina displays, pinned headers / floating elements, and lazy-loaded content
  - The control bar and preview window are placed away from the selected region and never leak into the capture
- Screenshots are **never saved directly** — they open in the annotation editor, where you save, copy to clipboard, or discard

**Annotation Editor** (shared by screenshots and "Annotate Image…")
- Tools: pen, arrow, rectangle, text, numbering, mosaic (pixelate / blur / hexagon), crop
- Everything you draw stays **re-editable**: select to move, recolor, restroke, redirect arrows, or delete
- Undo / redo; scroll to zoom, ⌘+scroll to pan, one-click "fit to window"
- Crop applies instantly (image and annotations together)
- **Pin**: stick the result cleanly onto your screen (red dashed border, draggable, scroll / button zoom, close button in the corner)

**More**
- Global hotkeys: fullscreen / window / region recording, fullscreen / region screenshot, OCR, scrolling capture — **blank by default, you decide**
- Pick specific microphone / camera devices (in both Settings and the HUD)
- All permissions in one "Permissions" tab: screen recording / microphone / input monitoring / camera; the mic permission is only requested when the mic is actually used
- Focus returns to your app the moment a selection finishes — update dialogs and menus never jump over what you're working on
- Launch at login, Do Not Disturb while recording (via Shortcuts), completion notification (reveal in Finder), hot-plug display support, English & Chinese UI

## Installation

### Homebrew (recommended)

```bash
brew tap yueseqaz/sakura-cap https://github.com/yueseqaz/Sakura-Cap
brew trust yueseqaz/sakura-cap          # newer Homebrew requires trusting third-party taps first
brew install --cask sakura-cap
```

### Build from source

```bash
git clone https://github.com/yueseqaz/Sakura-Cap.git
cd Sakura-Cap
./run.sh
```

> The app is ad-hoc signed and not notarized. If macOS blocks the first launch, right-click → Open, or allow it under System Settings → Privacy & Security.

## Usage

1. Click the menu-bar icon → "Start Recording / Screenshot / Annotate Image…", or press the global hotkeys you configured
2. After selecting the area, a floating HUD appears at the bottom of the screen: pick resolution, toggle mic / system audio / camera / click indicator / key display, then press **▶**
3. Pause / resume / stop while recording; screenshot / OCR / scrolling capture live under the "Screenshot" submenu (scrolling capture asks for auto or manual mode after region selection)
4. When recording stops, it goes straight into the **trimmer**; screenshots / long images open the **annotation editor** (save, copy, or "pin")

## Requirements

- macOS 13 or later
- **Screen recording** permission is required on first use; microphone, camera, and input monitoring are optional — a missing one only disables that specific feature, recording itself keeps working

## Development

Tech stack, build steps, signing & permissions, internal conventions and known pitfalls → **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** (in Chinese)

- Swift 5.9 + SwiftUI / AppKit; capture via ScreenCaptureKit; encoding via AVFoundation; OCR via Vision
- Zero third-party dependencies, system frameworks only; built purely with Command Line Tools — no `.xcodeproj` anywhere

## Links

- Repository: <https://github.com/yueseqaz/Sakura-Cap>
- Releases: <https://github.com/yueseqaz/Sakura-Cap/releases>
