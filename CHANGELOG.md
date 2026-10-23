# Changelog

This changelog follows Keep a Changelog. No production release has been made.

## [Unreleased]

### Reliability and continuous operation

- Bound analysis load and portrait dimensions; skip unwanted native samples and
  remove per-pixel allocations and redundant JPEG copies.
- Cancel crop/JPEG on stop/dispose, consume late snapshots, serialize native
  operations, guard competing controllers and share concurrent disposal.
- Keep paper-removal gating through stale frames; detect failed/stalled workers.
- Write completed captures through a same-directory partial file and handle
  graceful example exit. Document abrupt-exit and 24/7 hardware limits.
- Cover additional rectangular document ratios, lighting, 5/8 MP processing and
  lifecycle failures; add a configurable synthetic endurance tool.

### Added

- Opt-in profile/release and default-debug `debugPrint` JSON diagnostics for
  camera lifecycle, document state, capture/errors and five-second performance
  summaries. Redact image content, identifiers, paths and raw exception details;
  coalesce noisy state changes and cancel heartbeat timers on teardown.

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
