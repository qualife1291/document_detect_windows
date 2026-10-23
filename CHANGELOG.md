# Changelog

This changelog follows Keep a Changelog. No production release has been made.

## [Unreleased]

### Added

- Built-in live four-corner document overlay with matching contain/cover/fill
  coordinates, perspective-following corner markers and configurable styling.
- `DocumentPreviewState` enum callback (`onDocumentStateChanged`) and
  `previewStatus` listenable for per-frame geometry and quality UI, including
  detection while auto-capture is disabled.
- Clear expired/stopped/error preview corners and report capture lifecycle states.

- Windows x64 plugin guard and explicit, interchangeable camera frame sources.
- Experimental UVC adapter and separately resolved camera_desktop candidate.
- Pure Dart document geometry, ROI quality warnings, isolated latest-frame
  analysis and stable auto-capture with preparation feedback and cooldown.
- Full-resolution re-detection, perspective-correct JPEG and optional file output.
- Vietnamese kiosk example with manual capture, device choice, keyboard retake,
  quality messages and analysis metrics.
- Synthetic functional tests and Windows SDK matrix automation.

### Fixed

- Close public event streams even if native camera shutdown reports an error.
- Finish decoding desktop still images before removing their temporary files.

### Known limitations

- Physical Windows camera, accessibility and kiosk performance gates are
  pending; the implementation is not a completed handover.
