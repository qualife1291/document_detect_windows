# Kiosk preview integration

User provided shared camera_preview_widget.dart, the ID/review flow and the
multi-document ATNUploadProofController (2026-10-27/28). Integration guide:
[GetX kiosk wiring](../integration/kiosk-getx.md). No full kiosk repository or
hardware/control service implementation is available; those hooks are explicit.

## Delivered scope

- Copyable Flutter/UVC widget in example/lib/integration. Optional controller
  retains capture()/Uint8List callback shape. No GetX dependency in the package.
- Batch is the default, matching the original shared widget: capture multiple
  JPEGs without reopening camera. Auto retains its removal/cooldown latch across
  parent rebuilds. No image history or capture files retained by this widget.
- Single mode stops camera and releases host hardware before callback; the ID
  callback can immediately open review/run existing image analysis safely.
- Optional acquire/release/configure/select hooks, awaited stop/shutdown, hidden
  lifecycle and route-active control. Remount with the same controller waits for
  the previous unmounted view's cleanup. Stale snapshot/acquire results rejected.
- Device selection never silently falls back when several cameras exist. Old
  fixed ROI/digital zoom/mirror and CameraPlatform.takePicture/XFile are removed
  from the replacement; this migration is explicit in the guide.
- Host coexistence fixture now compiles the copied widget in a separate Windows
  application along with root/UVC, camera_windows 0.2.6+4 (SDK-floor compatible
  fixture pin) and the original flutter_ffi_uvc plugin. This does not change the
  camera_windows version in the caller's project. Physical-device arbitration
  still requires awaited handoff; dependency coexistence does not grant access.

## Verification

Linux Flutter 3.47.7 example analyze and all 33 tests passed; stable format covers
60 files. Eleven new integration tests exercise manual/auto delivery, callback
priority, batch repeated capture, rejection/retry, batch auto removal latch after
cooldown/rebuilds, pending snapshot stop, late hardware acquisition, ambiguous
selection, app hidden behavior, Column layout without a fixed height, and
remount handoff. The handoff regression drives widget callbacks and real-isolate continuations
while a held stop delays reuse of the controller.

Validated source: `1f55c45433467ced173c26f8e4ad925c574770d9`.
[Windows CI 40730610952](https://github.com/qualife1291/document_detect_windows/actions/runs/40730610952) passed Flutter 3.32.8/3.41.9/3.47.8:
117 root, 11 UVC and 33 example tests per SDK, analyze, three benchmarks,
native sampler CTest, 60-second synthetic endurance and x64 release build.
Stable passed format60 and compiled an external application with the copied
widget, camera_windows0.2.6+4, original UVC and internal UVC: three DLLs,
license and independent registrations verified. This is dependency/build
coexistence; no physical cameras were opened by the build check.

Linux3.32.8/3.41.9 example analyze/33 tests are logged. Linux3.47.7 example
analyze/33 tests passed in the execution transcript before SDK switching; stable
package configs and format were restored. Root/native component tree hashes
match baseline2a7e31b; Windows reran the full suites. Evidence:
[source record](logs/kiosk-preview-integration/source.json),
[CI details](logs/kiosk-preview-integration/windows-ci.json) and nearby logs.
Root library, native adapters and ordinary example capture app remain unchanged.
Physical kiosk/hardware-control compatibility and 24–168 hour soak are not proven
by these synthetic tests. Product readiness remains CHUA DAT.
