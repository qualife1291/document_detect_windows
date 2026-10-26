# Preview detail and integration performance

Camera modes, preview pixels and document pixels are different quantities. The
reported Integrated Webcam supplies 1280×720 (~0.92 MP) in the supplied log; a
cropped document contains fewer pixels. Presets cannot create an unsupported mode
or correct optical/focus/motion blur. Test in profile/release, with the host UI,
lighting and intended camera; debug FPS is not a hardware performance result.

## Configure independent budgets

```dart
final capture = WindowsDocCapture(
  analysisInterval: const Duration(milliseconds: 200),
  cropPipeline: const CropPipeline(jpegQuality: 92),
  frameSource: UvcFrameSource(
    previewMode: UvcPreviewMode.bitmap,
    bitmapPreviewProfile: BitmapPreviewProfile.balanced,
    bitmapPreviewInterval: const Duration(microseconds: 66667),
    pollInterval: const Duration(milliseconds: 200),
    preferredNativeFps: 15,
  ),
);
```

Import the root package and windows_doc_capture_uvc. Root/custom sources keep
working; optional desktop backend remains outside the default dependency graph.
UVC still defaults to texture; bitmap is explicit and avoids external textures.

| Bitmap profile | Maximum longest side | Configured target | Under load |
| --- | --- | --- | --- |
| lowResource | 640 | 10 FPS | same size, slower cadence |
| balanced (example default) | 960 | 20 FPS; default target ~15 | 640, slower cadence |
| detail | 1280 | 20 FPS; default target ~15 | 960, then 640; slower cadence |

No upscaling. The profile only changes preview; analysis remains <=640 and full
snapshots keep the negotiated camera mode. Nearest sampling preserves existing
analysis behavior; bilinear native preview sampling avoids nearest-neighbor
jaggedness. Both outputs come from one locked native frame when requested
together, with independent sizes and the same sequence. Full camera RGBA is no
longer copied into Dart for preview/analysis. Native camera conversion still has
full-stream cost; 5/8MP modes can remain expensive even with a small preview.

The requested period starts at sampling start; slow work does not get added to
every period. Missed slots are dropped, never replayed. One decoder, one displayed
image, no frame history, no extra preview reads when the decoder is busy.
Per-session load levels 0..2 consider recent sampling, decode and host Flutter
build/raster costs. At most one level is lost per second; a recovery step needs
10 healthy seconds. Reduced profiles lengthen the period to 1.5x/2x. Sampling
cost adds a five-times-cost readback floor. Analysis has its own demand; these
limits do not cap total host CPU/GPU use or guarantee displayed FPS/latency.

## Integrate without competing owners

- Await the existing camera's stop/dispose before starting capture. Await capture
  stop/dispose before handing the device back. Do not open a second owner while
  it is processing a capture or stopping. Operation serialization is per source;
  a separate camera plugin/process is outside its lease.
- Stop capture when the route is hidden for a long time. TickerMode(false) and
  inactive lifecycle suppress bitmap demand, but do not stop the native producer
  or analysis. Offstage/Opacity alone are not visibility signals. For a hidden
  tab, use TickerMode plus explicit awaited stop; serialize resumption yourself.
- Mount one bitmap preview per FrameSource. Unmount it before creating another
  view of that source, or move the existing widget with a GlobalKey. Do not
  share its readiness handle between simultaneous consumers.
- Build the preview in bounded constraints. Its RepaintBoundary isolates bitmap
  repaints; expensive parent layouts, animations, shaders, platform views and
  other image decodes can still consume frame time. Keep UI work outside camera
  callbacks and use previewStatus for status/corners instead of retaining frames.
- Do not queue frames or await slow storage/network from a status callback. Limit
  your own result/history image decodes. The package evicts/disposes only images
  it owns and never clears the host image cache or saved documents globally.
- Release callbacks, timers, subscriptions and capture on exit. Flutter cannot
  guarantee asynchronous cleanup after process termination/power loss or recover
  every driver/GPU hang. Keep operator recovery and physical soak tests.

The internal Windows-only BSD backend has distinct package/DLL/plugin/channel
names, so adding the original flutter_ffi_uvc dependency does not replace the
capture channels. This permits dependency coexistence, not simultaneous access
to the same camera. No dependency_overrides or private session pointers are used.
See [backend provenance](../adapters/windows_doc_capture_uvc_backend/README.md).

## Captured detail and operator guidance

Full-resolution capture re-detects that snapshot; old preview corners are not
used to crop new pixels. Outward crop padding remains .02 by default. Exact
integer axis-aligned rectangles copy inclusive source pixels without resampling;
fractional/perspective rectangles keep the existing bilinear warp and output
limit. No heuristic snapping, sharpening or artificial upscaling is applied.
Aligned output can be one pixel larger per dimension because both edge pixels
are retained. Original JPEG dimensions remain the full stream size.

Package JPEG default stays 90; example uses 92. The synthetic 1280×720 fine-print
benchmark measured 354022 / 378906 / 461853 bytes and luminance MSE
5.4484 / 3.6149 / 1.6681 at quality 90 / 92 / 95. This supports the example's
small size/detail tradeoff, not an optical-sharpness claim. Timings vary by
hardware/build; use tool/jpeg_quality_benchmark.dart on the target system.

The example displays actual camera dimensions/MP. For custom UI use
`capture.previewStatus.value.documentPixelSize(capture.previewSize)` for
estimated document edge lengths in native pixels. It works with portrait A4 and
landscape ID geometry; it is not a semantic document classifier or OCR score.
The example hints below a 300-pixel document short edge without blocking manual
or automatic capture. If blurry, improve lighting, hold still and verify working
distance/focus; fixed-focus webcams may get worse when moved too close. Autofocus
settings are not changed automatically.

## Run and diagnose

After this native-backend update, rebuild once from example:

```powershell
flutter clean
flutter pub get
flutter run -d windows --profile --dart-define=DOC_CAPTURE_LOGS=true
```

Example flags: DOC_CAPTURE_PREVIEW_PROFILE=lowResource|balanced|detail and
DOC_CAPTURE_PREVIEW_FPS=5..20 (lowResource capped at10). LOW_RESOURCE continues to
configure analysis/native FPS preference independently of capture resolution.
Change capture resolution before start or on the result screen, then retake.

Health logs add bitmapSize, bitmapLoadLevel, bitmapCadenceMs, bitmapDecodeMs and
appFrameCostMs alongside sampling cost, bitmapOfferedFps, native and analysis FPS.
Offers are not presented frames. Only safe numeric metadata is logged, never
pixels/document text/device identifiers. Compare profile/release with real host
animations and result transitions; look for CPU/raster spikes, memory growth,
mode fallback, stale geometry and cleanup failures. CI/synthetic tests do not
certify physical-camera sharpness, driver stability or 24/7 operation.
