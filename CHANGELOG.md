# Changelog

This changelog follows Keep a Changelog. No production release has been made.

## [Unreleased]

### Fifth physical-log follow-up: independent bitmap cadence

- Split cached analysis and bitmap streams; request about 15 FPS for example
  preview while analysis keeps its 200 ms interval. Share readback/downsample
  when both consumers need a frame, with upstream decoder demand and no queue.
- Pause extra bitmap work during capture/start/teardown through an optional
  source interface. Keep texture defaults and custom FrameSource compatibility.
- Back off preview-only reads using measured copy/downsample cost; add safe
  health counters distinguishing bitmap offers, native delivery and analysis.
  Expose example DOC_CAPTURE_PREVIEW_FPS (5–20) for hardware comparisons.
- Keep crop/JPEG/quality gates and prior dispose/stream identity fixes unchanged.
  The target is not a physical displayed-FPS, CPU or 24/7 guarantee.

### Fourth physical-log follow-up: bitmap flicker and result presentation

- Cache the UVC frame stream so status/parent rebuilds do not unsubscribe, clear
  the current bitmap and flash black while waiting for a new frame.
- Prevent result magnification with scaleDown and device-pixel-ratio mapping;
  use medium filtering for shrinking and evict old providers on DPI changes.
- Restore high capture preset independently of low-resource sampling, with an
  example resolution selector; keep bounded bitmap preview and serial camera
  teardown/restart. Larger modes depend on hardware and cost more memory/CPU.
- Reproduce stream identity failure and test 30 real-decoder status/parent
  rebuilds, result pixel sizing at 100/150/200% DPI and preset forwarding/retake.
  Crop/JPEG/filter/quality thresholds are unchanged; optical blur is not repaired.

### Repeated-capture performance and GPU failure follow-up

- Add opt-in bounded UVC bitmap preview without external-texture registration;
  keep one in-flight decoder, drop busy frames and dispose superseded/late images.
  Expose polling interval/native FPS preference; preserve texture API default.
- Initially default the example to medium (superseded by the fourth-log fix),
  200 ms analysis/polling and bitmap
  preview. Stop camera before showing results; reopen on retake. Limit result
  display decode and evict only the result's image-cache entry on close/replace.
- Clear analyzer lifecycle references on dispose; add example UI/cache diagnostics
  and include engine GPU errors in log-copy instructions.
- Add regressions for decoder backpressure/unmount/no-paint disposal, adapter
  texture/headless cleanup and repeated capture/retake result-cache ownership.
  These mitigations do not certify recovery from GPU device loss or 24/7 uptime.

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
