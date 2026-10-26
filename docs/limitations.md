# Known limitations

- 24/7 and low-end 5/8 MP operation are not certified. See
  [continuous operation](continuous_operation.md) for controls, synthetic
  coverage and required physical soak/exit scenarios.
- Experimental implementation. No physical Windows camera/backend comparison
  or final production backend selection has been made. Windows x64 native
  builds and synthetic tests have Windows CI evidence; physical camera/driver
  behavior is still unverified.
- The detector finds contrasting convex quadrilaterals, not document semantics.
  Rectangular non-documents may trigger it; weak contrast, patterned backgrounds,
  shadows, occlusion and specular glare can defeat it. The operator must validate
  output for the intended documents/background. A4/ID card labels are geometric
  guesses, not identity/authenticity checks.
- No OCR, ML classification, IP/RTSP cameras, multi-camera sessions, Windows ARM,
  mobile, web, macOS or Linux runtime support.
- No dartcv4 dependency is installed. The detector facade is the extension point
  for a future SDK-compatible backend; conditional dependency selection across
  SDK versions is not implemented or claimed.
- The example explicitly uses an experimental UVC candidate with bounded native
  sampling before FFI transfer: analysis <=640, bitmap profiles <=640/960/1280.
  Balanced preview defaults to 960 and reduces to 640 under load. Native camera
  conversion/storage and full-resolution snapshots still have full-frame cost;
  5/8 MP targets require physical Windows profiling. The adapter defaults to
  texture; the example explicitly selects bitmap to avoid camera external-texture
  registration. Flutter can still use the GPU. Device loss (`0x887A0006` / EGL
  Context Lost) requires physical driver validation and may require an app restart.
  Neither adapter exposes hardware-to-texture timestamps. The optional desktop
  adapter creates a temporary full-frame still image, so use UVC without
  saveDirectory when capture must not write images to disk.
- Poll timestamps describe receipt in Dart, not sensor exposure time. Thus age
  checks cannot prove hardware capture latency. No preview latency or CPU
  threshold is certified. Synthetic test speed is not kiosk throughput.
- Full-resolution JPEG/perspective correction can exceed 300 ms, especially at
  4K. The worker avoids blocking preview but does not guarantee target latency.
- Coordinate mapping uses one unmirrored, unrotated, top-left-origin space and
  matching aspect ratio. Real 4K/DPI/driver orientation still needs verification.
- Manual capture requires a quad but deliberately bypasses quality gating.
- UI text, keyboard behavior and semantics are unit/widget tested. Windows
  accessibility inspection, contrast verification on the compiled app and all
  ten Nielsen judgments remain pending.
- No login is implemented. The specification mentions a Login step without an
  authentication contract; the local example has a start action only.
- No secure memory erasure, capture retention, disk encryption, saved-directory
  allowlist or kiosk OS lockdown is supplied. See SECURITY.md.
- No release no-op switch exists: `start()` intentionally opens camera in both
  debug and release. It never opens a socket. A no-op-specific test is therefore
  not applicable; release camera behavior still needs physical verification.
