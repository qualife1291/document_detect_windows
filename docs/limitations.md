# Known limitations

- Experimental implementation. No physical Windows camera/backend comparison
  or final production backend selection has been made. No Windows native build
  or driver behavior is claimed from Linux tests.
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
- The example explicitly uses an experimental UVC candidate. Its API copies
  full RGBA for analysis before Dart downsampling. This additional allocation
  and UI-isolate sampling cost require Windows profiling/native downsampling
  before the performance targets can be accepted. Preview pixels themselves
  stay in native Texture. Camera-desktop's isolated still-image decode also needs
  profiling. Neither adapter currently exposes hardware-to-texture timestamps.
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
