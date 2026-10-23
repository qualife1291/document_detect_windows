# Changelog

This changelog follows Keep a Changelog. No production release has been made.

## [Unreleased]

### Preview corner rounding

- Add optional `cornerRadius` (logical pixels, default 0) to buildPreview,
  DocumentCameraPreview and DocumentCornersPainter for outlines and L markers.
  Bound large radii to short edges and keep detection/crop geometry unchanged.
  Example uses a subtle 6 px radius.

### Crop edge preservation

- Add a default outward crop margin of 2% of the shortest detected edge, with
  configurable `CropPipeline.cropPadding` (0..0.1, zero for exact cropping).
  Bound the margin uniformly to the source image while preserving edge directions.
- Preserve detection/motion/quality geometry and original JPEG. Expose actual
  warp corners as `CapturedDocument.cropQuad`, including saved-file results.
- Add crop-corner and applied/limited-padding diagnostics and regressions for
  edge glyphs, perspective/portrait geometry, sensor bounds and 5/8 MP scaling.

### Physical test follow-up

- Fix pull-adapter analysis cadence by reserving demand before frame copying;
  keep worker backpressure and bounded timer jitter.
- Prefer complete document contours over clipped backgrounds and retry weak
  edges with sensitive Canny/closing only when the regular passes fail.
- Default warning frame to white; keep configurable green clear state and add
  a closed-outline style, selected in the example.
- Accelerate perspective resampling with byte-buffer bilinear interpolation;
  add optional crop-size limit and explicit grayscale/capped-contrast filters.
  Keep full-color/full-resolution defaults and full-resolution original JPEG.
- Log snapshot rejection decisions, per-stage processing times and auto-capture
  stability/threshold details for physical debugging.

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
