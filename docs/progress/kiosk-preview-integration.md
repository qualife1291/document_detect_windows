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

Linux Flutter 3.47.7 example analyze and all 32 tests passed; stable format covers
60 files. Ten new integration tests exercise manual/auto delivery, callback
priority, batch repeated capture, rejection/retry, batch auto removal latch after
cooldown/rebuilds, pending snapshot stop, late hardware acquisition, ambiguous
selection, app hidden behavior and remount handoff. Test handoff pumps widget and
real-isolate continuations; no assertion was removed to bypass a scheduling issue.

Additional supported-SDK/Windows evidence will be recorded after CI completes.
Root library, native adapters and ordinary example capture app remain unchanged.
Physical kiosk/hardware-control compatibility and 24–168 hour soak are not proven
by these synthetic tests. Product readiness remains CHUA DAT.
