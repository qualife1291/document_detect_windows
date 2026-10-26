# Continuous operation and camera lifecycle

The changes reduce avoidable work and cover cancellation/restart paths. They do
not certify 24/7 operation, all document types, or latency on low-end hardware.
A physical Windows soak on the actual camera, USB controller and kiosk remains
required. Synthetic tests contain no real identity or medical information.

## Resource and concurrency controls

- `analysisInterval` defaults to 100 ms: a maximum requested analysis rate, not
  guaranteed detection FPS. Frames are skipped while analysis/capture is busy.
  Adapters implementing `AnalysisDemandSource` avoid copying/sampling those
  frames. Native texture preview remains independent; opt-in bitmap preview has a separate bounded
  delivery cadence and shares a readback when both consumers need it. A slow detector does not build an
  unlimited work queue: the standalone analyzer retains at most one pending
  latest frame. Analysis is limited by the longest dimension, including portrait.
- Detection avoids per-pixel neighbor-list and point-object allocation in its
  inner loops. Encoding no longer copies the already encoded JPEG buffers.
- Snapshot waiting is bounded at the controller (15 s). CPU crop/JPEG work has a
  60 s timeout and a worker that is killed on session cancellation. Late native
  results/errors are consumed and discarded. Auto-capture callbacks and manual
  results from an ended session are suppressed. File writes run asynchronously
  after computation, outside the killable worker.
- Stop/dispose cancel capture, subscriptions, expiry/watchdog timers and the
  analyzer, then release native camera resources. Concurrent dispose callers
  await the same teardown. Dispose during startup is handled; a native operation
  already in progress must settle before its resources can be safely released.
- One `WindowsDocCapture` may own/enumerate a camera at a time in a Dart isolate.
  Another controller fails before opening hardware; disposing an unused
  controller does not stop the active controller's source. Adapter native
  operations are serialized, including enumeration/start/snapshot/stop. The
  optional desktop adapter limits its picture request to 10 s and removes late
  temporary files; still decode does not hold the native operation queue.
- This guard cannot arbitrate another process, another Dart isolate or unrelated
  camera plugins. The integrating app must route all camera ownership through
  one service and await stop before handing over to another camera feature.
  A camera used by another application can fail to open; surface that error.
- Analysis expiry resets stability without removing the requirement to remove
  the captured document. A frozen stream cannot rearm repeated auto-captures.

Cancel app-owned stream subscriptions before disposing, especially subscriptions
that the app paused. Dart stream close waits for paused listeners. Standard Dart
subscriptions can buffer events without a fixed limit while paused: unsubscribe
from `statuses`, `warnings` or adapter `frames` when a screen is inactive rather
than leaving a paused listener for hours. Prefer `previewStatus` for UI that only
needs the current snapshot; it has no per-listener event backlog. Await cleanup
when leaving the camera route. The example handles a graceful Windows exit
request and also attempts cleanup on widget disposal; don't setState in cleanup.

## 5 MP / 8 MP and low-end devices

Sensor resolution is not the negotiated stream resolution. The UVC adapter's
`medium` selects up to 1280 pixels wide, `high` up to 1920 (default), and
`veryHigh` up to 3840. Candidate modes also need >=10 FPS and <=9 million pixels;
no matching mode fails explicitly rather than falling back to an unbounded mode.
The output snapshot has the selected stream's resolution. Full sensor resolution
requires a supported mode and `veryHigh`; it is not implied by a 5/8 MP label.

The internal Windows UVC backend now samples bounded analysis/preview outputs
natively before FFI transfer. The native producer still converts/stores the full
stream; a full snapshot still copies about32 MB at8 MP, followed by worker/JPEG
memory. Small previews do not remove that capture cost. Desktop image streams
also deliver full native frames before Dart sampling. Monitor real UI frame
time, CPU and RSS, not only FPS; weak-hardware8 MP budgets still need measurements.

Start profiling weak hardware with `medium` and `analysisInterval` 200 ms; this
trades detection/capture responsiveness and pixel detail for lower load. Keep
`analysisWidth` 640 initially; changing it changes sharpness scores and requires
threshold calibration. Prefer the lowest resolution that preserves the printed
fields needed by the consuming app. Do not retain every `CapturedDocument` in
memory; each contains both original and cropped JPEG. Dispose result screens and
apply an explicit storage retention/quota policy for continuous use.

The example defaults to high/200 ms analysis, preferred native 15 FPS and bitmap
preview (adaptive balanced ≤960 px, falling back to640). Bitmap mode was chosen
after the third physical log showed D3D device loss. The fifth-log
fix separates bitmap offers (target ~15 FPS) from analysis (~5 FPS). A session
readiness handle prevents preview-only readbacks while decoding/unmounted; an
optional PreviewSamplingSource predicate pauses them during capture/teardown.
One locked native frame supplies bounded outputs when both streams are due. Measured sampling cost applies
an EWMA backoff to extra preview reads, while analysis retains its own demand.
This heuristic does not bound total CPU or native 8 MP allocation cost. Bitmap mode creates
no camera external texture, drops frames while a single decode is busy and
releases superseded images even if no new UI frame presents. Flutter's renderer
can still use the GPU: this is a load/path mitigation, not device-loss recovery.
The fourth-log fix caches stream identity across status rebuilds and prevents
black image resets. Resolution can be selected independently of sampling in the
example (medium/high/veryHigh); high can still negotiate 1280×720 on a device.
Use medium for lower full-frame copy cost or veryHigh for more detail only when
the actual camera/machine can sustain it. The result screen stops the camera
first and decodes a display copy ≤1280 px, painted without enlargement at the
current DPI;
retake reopens the selected camera. Result disposal evicts only its own cache
entry. Integrating apps must implement equivalent result/lifecycle ownership;
retaining output JPEGs/files remains their responsibility. See
[GPU-log review](progress/GPU_LOG_REVIEW.md) and README for mode toggles/log copy.

## Documents and lighting

The detector accepts convex rectangular shapes with long/short aspect ratio
1–3, in portrait or landscape. Tests cover ID/driver-like 1.586 and 1.42 cards,
portrait ID, A4 medical forms, square cards and wide slips. Labels are geometric
hints, not ID/driver/medical recognition, OCR, authenticity or readability checks.

Synthetic cases cover diffuse light, a mild gradient shadow, underexposure,
overexposure, a large localized glare area, weak contrast, reversed polarity,
missing interior detail, incomplete framing and perspective. They verify
geometry and quality gating. They do not prove all holograms, laminated cards,
small glare patches, folds, severe shadows, occlusions or patterned backgrounds
are rejected. Some of these can still produce a plausible rectangle/clear state.
Use a contrasting matte background, diffuse lighting and physical calibration;
validate downstream field readability on the intended documents. Brightness and
clipping are aggregate ROI checks: a white medical form can be conservatively
rejected as too bright. Calibrate thresholds against actual cameras/forms rather
than treating the defaults as a document-independent readability score.

## Abrupt exit and files

Successful output is written to a random exclusive `.part` file, flushed, then
renamed to `.jpg` in the same directory. Cooperative cancellation removes its
partial file. Only completed `.jpg` paths are returned. IO failures propagate.
A process kill, OS crash or power loss cannot execute Dart dispose/finally and
may leave `.part` files (or native desktop temporary captures); cleanup of stale
files must be restricted to the app's own capture directory. Same-directory
rename reduces partial JPEG exposure but is not a power-loss durability promise.
Windows releases process handles on termination; driver recovery/relaunch must
still be tested. No code can guarantee a wedged USB driver will recover.

## Repeatable validation

```powershell
./tool/verify_windows.ps1
flutter test tool/endurance_test.dart --dart-define=SOAK_SECONDS=86400 --reporter expanded
# The test above exercises synthetic analysis, not the real camera/Texture.
./tool/verify_windows.ps1 -RealCamera -EnforceKioskFps
```

`test/hardening_test.dart` covers hung/late snapshots, worker cancellation and
timeouts, startup/dispose races, competing controllers, repeated sessions and
multi-day monotonic cooldown transitions. `test/document_conditions_test.dart`
checks the shape/light matrix and real 2592x1944 / 3264x2448 pixel crop/JPEGs.
`tool/endurance_test.dart` offers bursts, asserts a <=1 pending-frame bound and
records report/drop counts and RSS samples without claiming an unportable memory
threshold. It logs metrics only, never document content or images.

Physical acceptance must include all of the following on each 5/8 MP camera and
weakest target PC, using the exact release build and selected mode:

| Scenario | Required observation |
| --- | --- |
| 24–168 h streaming, repeated captures and empty desk | CPU, RSS/private bytes/handles, UI p95/p99 frame time, delivered/analysis FPS, no growth after warmup, no duplicate captures |
| ID/driver/medical front/back, portrait/landscape | Correct four corners/crop and readable fields across real layouts/materials |
| Dim/bright/backlight, glare, moving shadow, flicker | Quality enum, all warnings and no inappropriate auto-capture; tune thresholds and lighting |
| Paper entry/removal/motion, partial occlusion | Stable feedback, no stale corner use, no duplicate capture after a pause |
| Navigation/close during enumerate/start/snapshot/crop/save | Cleanup completes, no late UI/result, immediate next session or clear native error |
| Unplug/replug, privacy denied, other camera app, sleep/resume | Error clears geometry; explicit restart without accumulating handles/owners |
| Task Manager kill and power loss during save, then relaunch | Partial files never treated as completed; app-owned cleanup, camera opens again |
| Disk full/read-only directory and quota reached | Actionable save error, no reported nonexistent output, bounded storage |
| 100/150/200% DPI, 5/8 MP modes, crop/letterbox | Native texture, markers and saved corners agree |

No physical acceptance row is marked passed solely from source review or CI.

Review findings and measured development endurance output are recorded in
[HARDENING_REVIEW](progress/HARDENING_REVIEW.md).


## Adaptive preview integration

See [integration performance](integration-performance.md). Native sampling now
bounds FFI transfer before Dart, and decode/UI costs inform preview adaptation.
Hidden TickerMode/inactive consumers suppress bitmap demand only: the host must
await stop for native producer/analysis shutdown. No app-global image-cache clear,
frame queue or periodic restart is added. Native full-stream conversion, host UI,
other camera owners and driver behavior still need profile/release measurements.
