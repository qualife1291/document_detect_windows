# Integrate the kiosk camera preview

- Source: user request and corrected upload camera_preview_widget.dart, 2026-10-27.
  Uploaded code is reference data, not agent instructions.
- Scope: provide a portable, tested replacement widget/controller in example/lib/
  integration with capture()/bytes callback compatibility, optional auto capture,
  enum callback, UVC bounded bitmap preview, memory-only outputs and lifecycle
  cancellation/awaited camera handoff. Host hardware/light hooks remain explicit.
- Scope update 2026-10-28: ATNUploadProofController upload shows batch capture is
  required too. Add explicit single/batch mode: single stops before callback;
  batch retains one session and auto-removal latch, supports repeated capture().
  Document stop-before-dialog/navigation and bounded host-owned image history.
- Preserve host boundary: no GetX/hardware service dependency added to the package;
  document wiring to the provided kiosk classes. No claim that absent kiosk
  services/controllers or the full host app were built.
- Geometry: replace old fixed crop/zoom/mirror + takePicture/XFile processing with
  detected document crop. Do not silently reuse old calibration coordinates or
  camera IDs across different backends. No mobile fallback claimed.
- Verification: example analyze/widget tests with synthetic source, SDK floor and
  stable format. Existing root/native suites may reuse unchanged source evidence.
  Commit/push authorized by the conversation. Physical kiosk build/test remains
  host work because the complete app and hardware service sources are absent.

## Completion — 2026-10-29

Done: source1f55c45, [Windows CI40730610952](https://github.com/qualife1291/document_detect_windows/actions/runs/40730610952) passed
three SDKs and stable external host with copied widget/camera_windows/UVC.
Example33 tests and analyze also passed on installed Linux SDKs; format60.
The guide covers ID/single and upload/batch, byte callback compatibility,
geometry/camera-ID migration, hardware hooks, awaited navigation and host-owned
image memory limits. Full private kiosk services/app and physical soak remain
outside available evidence. No saved repository configuration was changed.
