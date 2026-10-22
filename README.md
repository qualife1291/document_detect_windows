# windows_doc_capture

**Windows x64 only. Experimental; not yet approved for kiosk deployment.**
Local USB camera preview, document geometry/quality analysis in an isolate,
auto capture with visible preparation feedback, and full-resolution perspective
correction. No OCR, document recognition model, telemetry or remote service.
The detector requires a contrasting background. Physical Windows validation
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
// Put capture.buildPreview() inside an AspectRatio(capture.previewSize.aspectRatio).
// Use capture.statuses for quad, quality, stable feedback, detection FPS and time.
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
