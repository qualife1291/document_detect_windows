# windows_doc_capture

**Windows x64 only. Experimental; not yet approved for kiosk deployment.**
Local USB camera preview, document geometry/quality analysis in an isolate,
auto capture with visible preparation feedback, and full-resolution perspective
correction. No OCR, document recognition model, telemetry or remote service.
The detector requires a contrasting background. Physical camera validation
and camera backend selection are still outstanding; see `docs/limitations.md`.

## Prerequisites

- Windows x64; Flutter **3.32.8 / Dart 3.8.1** or later. The package keeps
  `sdk: >=3.8.0`; the optional UVC adapter needs Dart 3.8.1.
- Visual Studio 2022 with **Desktop development with C++**, Windows SDK and
  CMake, as required by `flutter doctor -v`.
- Local camera supported by Windows Media Foundation. Windows N editions may
  require Microsoft's Media Feature Pack.
- Enable **Settings → Privacy & security → Camera → Camera access** and
  **Let desktop apps access your camera**. An IT group policy can override
  these settings. Start/device errors must be handled by the caller.
- Host/firewall configuration is not applicable to runtime: this package opens
  no sockets and does not use a server. Dependency installation needs Internet.

## Install and run

This package is currently configured for local development only (`publish_to: none`). Use a local
path dependency on the root package and one adapter; do not depend on both
adapters in applications that must resolve on the SDK floor.

```yaml
dependencies:
  windows_doc_capture:
    path: ../document_detect_windows
  windows_doc_capture_uvc:
    path: ../document_detect_windows/adapters/windows_doc_capture_uvc
```

No camera backend is silently selected. `flutter_ffi_uvc` is explicitly selected
by the example as an **experimental candidate**, not a measured default. The
optional `adapters/windows_doc_capture_desktop` uses `camera_desktop` and requires
Dart 3.11 / Flutter 3.41.9. It is outside the default dependency graph. Real Windows
measurements must choose the production backend.

```powershell
flutter pub get
cd example
flutter pub get
flutter run -d windows
```

Select a device and choose **Bắt đầu**. **Tự chụp** toggles automatic capture;
**Chụp ngay** captures manually when four document corners can be found. Manual
capture bypasses quality gates. Check the warning before using it. Enable file
saving and enter an operator-controlled directory before starting if needed.
The result shows the corrected image; **Chụp lại** or **Esc** dismisses it.
There is no login or authentication layer in this local example.

## Integration

```dart
final capture = WindowsDocCapture(frameSource: UvcFrameSource());
final errors = capture.errors.listen((error) {
  // Present a camera/permission/IO error without logging sensitive paths.
});
final warnings = capture.warnings.listen((warning) {
  // Display warning.message and an icon, as well as a color.
});
await capture.start(
  preset: ResolutionPreset.high,
  enableAutoCapture: true,
  saveDirectory: outputDirectory, // omit to keep outputs only in memory
  onAutoCapture: (document) {
    consume(document.croppedJpeg); // caller owns retention and delivery
  },
);
// Put capture.buildPreview() in an Expanded or a SizedBox. Four corners are drawn automatically.
// Use capture.previewStatus for UI state/corners, and capture.statuses for analysis metrics.
final manual = await capture.captureNow(); // null when busy or no document
await capture.stop(); // can start again
await warnings.cancel();
await errors.cancel();
await capture.dispose(); // terminal; closes streams
```

Import `package:windows_doc_capture/windows_doc_capture.dart` and the chosen
adapter. Subscribe before starting. The caller owns the controller and must await
`stop()`/`dispose()`. Auto-capture callbacks run once per capture; only successful
automatic captures invoke `onAutoCapture`. `captureNow()` returns its result to
its caller. Exceptions from capture/file IO are propagated; automatic errors
appear on `errors`. Stream/device failures stop the camera and require restart.
Concurrent manual capture calls return null while the first is in progress.

`CapturedDocument` includes full-frame and cropped JPEG, clockwise TL/TR/BR/BL
corners in full-resolution pixel coordinates, sharpness, coverage, timestamp,
optional saved path and processing time. A fresh snapshot is detected again
before crop. JPEG quality defaults to 90. Saved files use opaque random names;
only cropped JPEGs are persisted by the UVC flow. No retention policy is applied.

## Live detection, corner overlay and enum callback

Detection starts with the camera and runs even when `enableAutoCapture: false`.
Auto-capture controls taking photos; it does not disable detection or quality
callbacks. Inside a Flutter `State` that owns `capture`:

```dart
DocumentPreviewState documentState = DocumentPreviewState.idle;

Future<void> startCamera() async {
  await capture.start(
    enableAutoCapture: false,
    onDocumentStateChanged: (DocumentPreviewState state) {
      if (mounted) setState(() => documentState = state);
    },
  );
}

Widget buildDocumentPreview() => SizedBox(
  height: 420,
  child: capture.buildPreview(
    fit: BoxFit.contain,
    showDocumentCorners: true, // default
    validColor: const Color(0xff69f0ae),
    warningColor: const Color(0xffffffff), // default white until quality is clear
    frameStyle: DocumentFrameStyle.outline, // or .corners (API default)
    cornerLength: 24,
    cornerRadius: 6, // logical pixels; API default 0 (sharp), also works with .corners
    strokeWidth: 3,
  ),
);
```

`buildPreview()` keeps the native camera texture and four L-shaped corner markers
in the same coordinate space. `BoxFit.contain` shows the complete camera frame;
`BoxFit.cover` crops it while keeping marker coordinates aligned. Markers follow
the detected quadrilateral edges, including perspective. `DocumentFrameStyle.outline`
draws a closed frame; the example uses it. The API defaults to four corner markers.
White is the default warning color, green indicates clear quality (motion stability
is checked separately before auto-capture). Both colors are customizable. `cornerRadius` rounds the frame or L-shaped markers
in logical pixels; the API default is `0`, and the example selects `6`. Large
values are limited to the available edge/marker lengths. Rounding affects the
preview drawing only; detected corners and crop geometry stay unchanged. Turning
`showDocumentCorners` off keeps the same preview fit. Avoid separately mirroring
or rotating only the texture; apply app transforms to the whole preview widget.

| Enum | Meaning for app UI |
| --- | --- |
| `idle` | Camera stopped |
| `processing` | Starting or waiting for fresh analysis |
| `noDocument` | No valid document quadrilateral |
| `outOfFrame` | Insufficient camera-frame margin or coverage |
| `tooDark` / `tooBright` | Exposure unsuitable |
| `blurry` | Document ROI is not sharp enough |
| `tilted` | Perspective/corner angles exceed the threshold |
| `clear` | All quality checks pass; movement/stability may still prevent auto-capture |
| `capturing` | Snapshot / perspective / JPEG processing is in progress |
| `cooldown` | Capture finished; auto-capture is waiting to rearm |
| `error` | Camera startup or frame stream failed |

The callback fires only when the enum changes, including lifecycle transitions.
It does not flicker to `processing` for every frame. Quality priority is
`noDocument` → `outOfFrame` → `tooDark` → `tooBright` → `blurry` → `tilted` →
`clear`; capture lifecycle states take priority while capturing/cooling down.
All simultaneous warnings are retained in the snapshot. A synchronous exception
in the enum callback is delivered on `errors` and does not stop analysis.

For frame-by-frame custom UI, listen to `capture.previewStatus`, a
`ValueListenable<DocumentPreviewStatus>`. It updates on every accepted analysis,
including corner movement while the enum stays unchanged:

```dart
ValueListenableBuilder<DocumentPreviewStatus>(
  valueListenable: capture.previewStatus,
  builder: (context, status, child) => Text(status.state.name),
);
// Also available synchronously: capture.currentPreviewStatus.
```

`normalizedQuad` is an immutable TL/TR/BR/BL list relative to the complete,
unmirrored camera frame. It is null when no document is found, the controller
stops/errors, or analysis expires after 500 ms. Expiry clears old markers even
when no new frame arrives. `report` contains sharpness/coverage/exposure and
analysis-frame dimensions. Use `projectDocumentQuad()` with the same `BoxFit`
and `Alignment` if drawing your own overlay. Quality enums describe the full
camera frame, even if the app chooses to crop the viewport with `cover`.

## Thresholds and feedback

```dart
final capture = WindowsDocCapture(
  frameSource: UvcFrameSource(),
  autoCapture: AutoCaptureController(
    stableFrameCount: 8,
    feedbackDuration: const Duration(milliseconds: 500),
    thresholds: const QualityThresholds(blurThreshold: 100),
  ),
  cropPipeline: const CropPipeline(jpegQuality: 90, analysisWidth: 640),
);
```

Analysis uses grayscale → 5×5 Gaussian → Canny / intensity contours → convex
quad fitting, with at least 5% area. Quality uses document-interior Laplacian
variance, mean luma and highlight clipping. A4/ID labels are aspect-ratio hints,
not proof of document identity. Blur thresholds need calibration for the chosen
camera and analysis size.

Automatic capture requires coverage ≥15%, frame margin ≥2%, corner-angle
error ≤15°, acceptable sharpness/exposure, eight consecutive stable frames,
normalized corner motion ≤0.015 and at least 500 ms of preparation feedback.
Gaps above 400 ms reset stability. Reports/snapshots older than 500 ms are
rejected. After capture, remove the document and wait for cooldown (2 seconds)
before another automatic capture. Camera preview remains a native texture;
analysis and JPEG/perspective processing run off the UI isolate.

## Continuous operation and low-end devices

Analysis is throttled (`analysisInterval`, default 100 ms) and adapters skip
sampling while the analyzer or capture worker is busy. Stop/dispose cancel
crop/JPEG work and suppress late session results. One capture controller at a
time owns camera access in a Dart isolate; await cleanup before another camera
feature starts. Do not enumerate devices while preview is active.

For a weak PC, begin with `ResolutionPreset.medium` and an analysis interval of
200 ms, then measure responsiveness and document readability. A 5/8 MP sensor
does not imply full sensor resolution at the default preset. The upstream UVC
API still copies full RGBA before sampling; full 8 MP low-end latency and 24/7
stability require physical profiling. See [continuous operation](docs/continuous_operation.md)
for cancellation/file behavior, document/light coverage and the physical soak matrix.

## Optional scan presentation

```dart
final capture = WindowsDocCapture(
  frameSource: yourFrameSource,
  cropPipeline: const CropPipeline(
    cropPadding: .02, // default: 2% of shortest detected edge per side; 0..0.1
    maxOutputDimension: 1600, // null (default) keeps full-resolution crop
    imageFilter: DocumentImageFilter.original, // or .enhance / .grayscale
  ),
);
```

Perspective correction always re-detects the captured snapshot. By default a
small outward crop margin protects edge content from approximate analysis
corners. `cropPadding` is per edge, relative to the shortest detected edge, and
can be set to `0` for the exact detected-quad crop. The margin shrinks uniformly
when the source frame has insufficient room; it can include a thin background
border. It cannot recover content outside the camera frame or fix detection of
an entirely wrong region. `CapturedDocument.quad` remains the detected quad;
`cropQuad` contains the actual source-pixel corners used for the corrected JPEG.
Quality and motion checks still use the detected quad, before the safety margin.

The optional longest-side limit applies during resampling to bound crop work and memory;
`originalJpeg` remains full resolution. `original` preserves colors and is the
default for IDs. `enhance` applies capped contrast stretching; `grayscale` is an
explicit presentation choice. Neither restores blur, performs OCR or guarantees
readability. Filtering and JPEG encoding run in the cancellable capture worker.
See the [physical-log review and reference comparison](docs/progress/PHYSICAL_LOG_REVIEW.md)
and [second-log crop review](docs/progress/CROP_LOG_REVIEW.md).

## Copy diagnostic logs from physical testing

`debugPrint` diagnostics are on by default in debug builds. Opt in explicitly
for a profile/release test, or turn them off in any build:

```dart
final capture = WindowsDocCapture(
  frameSource: UvcFrameSource(),
  enableDebugLogging: true, // false disables all library diagnostic output
);
```

The `DOC_CAPTURE_LOGS` define also enables the default in profile/release builds
(an explicit constructor value takes precedence). From the integrating Flutter
app or `example/`, run in Windows PowerShell:

```powershell
flutter run -d windows --profile --dart-define=DOC_CAPTURE_LOGS=true 2>&1 |
  Tee-Object -FilePath camera-test.log
```

Reproduce the issue, stop the app, then copy the library's lines:

```powershell
Get-Content camera-test.log |
  Select-String '\[windows_doc_capture\]' |
  ForEach-Object { $_.Line } |
  Set-Clipboard
```

Paste those lines with a description of the visible problem, camera's advertised
5/8 MP, selected preset and lighting. Include lines from startup through the
failure/stop so the controller ID, session number and UTC timestamps can be
correlated. This file is created by the command above; the library only prints
and does not create or upload a log file.

Each `[windows_doc_capture]` line is a JSON object (`v: 1`). Events include:

- `enumeration_*`, `start`, `started`, `stop`, `stopped`, `dispose`, `disposed`:
  lifecycle, requested preset, actual preview dimensions and analysis settings.
- `state`: document enum, warning enums, normalized quad, sharpness, exposure,
  clipping, coverage, margin and tilt. Rapid quality transitions are coalesced
  to at most one per 250 ms; lifecycle terminal/capture states print immediately.
  The first analysis prints immediately; `coalesced` counts omitted transitions.
  UI callbacks are unaffected.
- `health`: every five seconds while running and once before stop clears the
  current quality/geometry snapshot (including short test sessions); recent
  analysis FPS, mean/max analysis time, received/submitted/skipped analysis-frame
  counts, stale reports/expiries, last-frame age, RSS MiB and native delivered FPS
  when provided by the backend. Counters are cumulative per session; FPS covers
  the interval since the preceding health sample. Native delivered FPS is not
  measured UI/composited FPS. Backend skips before Dart delivery are not included
  in `skippedAtController`.
- `capture_*`, `snapshot`, `snapshot_rejected`: capture outcome, source dimensions,
  JPEG byte counts and processing time. `rejected` means the snapshot did not
  pass detection/quality/movement checks; no result was produced.
- `capture_processing`: exact decision (`accepted`, `no_document`, `quality`,
  `motion`, `invalid_expected_quad`), snapshot geometry/quality, and accepted
  stage times (`detectionMs`, `warpMs`, `filterMs`, `encodeOriginalMs`,
  `encodeCropMs`), output dimensions and filter. Rejected images stop before
  encoding. Accepted captures also record `cropQuad` (normalized actual crop
  corners), `cropPadding`, `paddingRequestedPx`, `paddingAppliedPx` and
  `paddingLimited`. Compare these with `quad` (detected corners) when checking
  missing edge content. `health` also includes auto-enabled/state/stable-frame/progress values.
  `start` records quality/stability thresholds so test sessions can be compared.
- `camera_conflict`, `*_rejected`, `error`: lifecycle conflicts and errors tagged
  by stage, exception type, safe platform/OS error code and package stack frames.
  Raw exception messages/details, paths, device IDs/names, pixel/JPEG bytes and
  document text are deliberately omitted. Error details already raised to the
  caller are unchanged.

Use logging for a bounded test session; console IO still has a cost. Disable it
for normal unattended production operation. The diagnostic timer is cancelled
on stop/dispose, and a failing app replacement for `debugPrint` does not interrupt
camera cleanup.

## Validation

```powershell
./tool/verify_windows.ps1
# On a physical target with an operator placing the paper:
./tool/verify_windows.ps1 -RealCamera -EnforceKioskFps
```

The Windows CI matrix runs package/example analysis, synthetic tests and release
build for 3.32.8, 3.41.9 and current stable. CI does not replace physical-camera,
Windows accessibility or kiosk performance checks. The synthetic benchmark
reports its runner/mode; it does not measure camera-to-texture latency.

Performance **targets, not verified promises**: preview latency ≤100 ms,
detection ≥10 FPS, detect-to-capture ≤300 ms and ≤25% of one CPU core. The example
shows analysis FPS/time and UVC native delivered-frame FPS when available.
This native counter is not composited display FPS. Camera-to-texture latency is
explicitly marked unavailable until driver timestamps are instrumented. See
[limitations](docs/limitations.md), [platforms](docs/platforms.md) and
[security](SECURITY.md) before integrating sensitive documents.
