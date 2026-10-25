# Sakura-Cap

**[中文](README.md)** | **[English](README.en.md)** | **[日本語](README.ja.md)**

**A minimalist menu-bar tool for Mac: screen recording, audio recording, screenshots, and AI.** Light, fast, and clean — one click on the menu bar to start recording; trim and annotate right after you stop; pull text out of screenshots in a single step; or just ask AI about what's on screen.

Sakura-Cap focuses on doing one thing well: capturing your screen. No Dock icon, no extra windows, fast launch, low footprint. Tune resolution, microphone, camera, click highlighting and key display on the floating HUD before recording starts; jump straight into the post-recording workbench when it ends; screenshots open directly in the annotation editor.

## Features

**Screen Recording**
- Full screen (single display / all displays in parallel, one file each), region, or window capture (system share picker)
- Floating HUD: armed first — press ▶ to actually start; pause / resume / stop mid-recording
- Adjust in place: output resolution (original / 1080p / 720p), microphone, system audio, camera, click indicator, key display
- Paused segments are removed from the timeline — the output is seamless
- Recording aids: mouse click indicator (pointer arrows), key display, start / stop sound cues, camera picture-in-picture, 3-second countdown

**Audio Recording**
- One click from the menu bar: system audio / microphone / both, saved as m4a with system audio and mic on **separate tracks**
- Pause / resume with gaps stitched seamlessly
- Floating recording bar: pulsing red dot, level meter, timer, draggable — and never captured into screenshots or recordings
- Jumps into the audio editor when finished (can be turned off in Settings)

**Screenshots**
- Full-screen / region capture
- **OCR**: select an area, recognition runs offline via system Vision, text goes straight to your clipboard
- **QR code recognition**: select to decode and copy the content
- **Upload to image host**: one click in the annotation editor uploads the whole image (with annotations) — supports **S3-compatible object storage** (Cloudflare R2 / MinIO / any cloud), **GitHub repositories**, and **custom APIs** (multipart; link parsed via JSON path or regex). On success the link is copied to the clipboard in your chosen format (plain URL / Markdown / HTML)
- **Scrolling capture (long screenshot)**: after selecting the region, choose **Auto-scroll** or **Manual scroll**; frames are stitched vertically by overlap into one long image, with a live preview on the side
  - Auto-scroll runs hands-free; manual scroll stitches in real time as you scroll — switch between them at any time
  - The matching algorithm is robust to sub-pixel scroll offsets on Retina displays, pinned headers / floating elements, and lazy-loaded content
  - The control bar and preview window are placed away from the selected region and never leak into the capture
- Screenshots are **never saved directly** — they open in the annotation editor, where you save, copy to clipboard, or discard

**Translation & AI** (one shared service configuration)
- **Text translation** window + **screen translation** (select → OCR → AI translation), with configurable translation style
- **AI chat**: full Markdown rendering, streaming output (stoppable mid-generation), image attachments, ⏎ to send / ⇧⏎ for newline
- **Ask AI about your screen**: send the image directly (vision models) or OCR it into text first (for text-only models)
- **"Ask AI" in the annotation editor**: send the whole annotated image in one click
- **Chat history**: session list, thorough deletion (including image files); long conversations get a rolling summary so context is never lost
- Compatible with **OpenAI Chat / OpenAI Responses / Anthropic** API formats — streaming and multimodal images in all three

**Post-production: Video Workbench** (opens automatically after recording)
- Multi-track timeline: video thumbnail strip, separate waveforms for system audio and microphone, focus track, annotation track
- Editing: split (S), delete, trim by dragging edges, reorder, undo / redo (⌘Z / ⇧⌘Z), snapping
- Create segments by dragging directly on tracks: focus segments, annotation segments, volume segments — resize via end handles
- **Spotlight focus**: drag a rectangle on the preview to zoom 1–6×, independently adjustable
- Annotate in place: pen / arrow / shapes / text / numbering / mosaic, with a toolbar floating under the preview
- Audio: per-track volume and mute, volume segments (local mute / attenuation), fades
- Export **MP4 (instant passthrough when unedited) / GIF / frame extraction**; Space to play, ←→ to step frames (⇧ jumps 1s), ⌘+scroll to zoom the timeline

**Post-production: Audio Editor**
- Large waveform on top (per-track, trimmed regions dimmed, click-to-seek); segment row + per-track volume row below
- Trim / split / reorder segments; volume segments, fades, per-segment mute, 0–200% gain
- Export m4a (instant passthrough when unedited); Space / ←→ / S / ⌘Z shortcuts
- "Edit Audio…" in the menu opens any audio file

**Annotation Editor** (shared by screenshots and "Annotate Image…")
- Tools: pen, arrow, rectangle, text, numbering, mosaic (pixelate / blur / hexagon), crop
- Everything you draw stays **re-editable**: select to move, recolor, restroke, redirect arrows, or delete
- Undo / redo; scroll to zoom, ⌘+scroll to pan, one-click "fit to window"
- Crop applies instantly (image and annotations together)
- **Pin**: stick the result cleanly onto your screen (red dashed border, draggable, scroll / button zoom, close button in the corner)

**More**
- Global hotkeys: fullscreen / window / region recording, fullscreen / region screenshot, OCR, scrolling capture — **blank by default, you decide**
- Tools menu: **screen annotation** (draw over the whole screen), **camera preview** (floating camera window), annotate image, trim video, edit audio, **compare** (side-by-side full-view comparison of two images), **color picker** (sample any screen pixel), **extract audio** (video audio track to m4a)
- Camera picture-in-picture has a **scissors button**: capture the current camera frame straight into the annotation editor
- Pick specific microphone / camera devices (in both Settings and the HUD)
- All permissions in one "Permissions" tab: screen recording / microphone / input monitoring / camera; the mic permission is only requested when the mic is actually used
- Focus returns to your app the moment a selection finishes — update dialogs and menus never jump over what you're working on
- **In-app updates**: read release notes in place, download and install in one step, with mandatory sha256 verification
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

1. Click the menu-bar icon → "Start Recording / Audio Recording / Screenshot / Translate / AI / Tools", or press the global hotkeys you configured
2. After selecting the area, a floating HUD appears at the bottom of the screen: pick resolution, toggle mic / system audio / camera / click indicator / key display, then press **▶**
3. Pause / resume / stop while recording; screenshot / OCR / scrolling capture live under the "Screenshot" submenu (scrolling capture asks for auto or manual mode after region selection)
4. When recording stops, it goes into the **video workbench** (trim / focus / annotate / export MP4 / GIF / frames); audio recording opens the **audio editor**; screenshots / long images open the **annotation editor** (save, copy, or "pin")

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
