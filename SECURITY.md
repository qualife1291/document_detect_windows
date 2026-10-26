# Security and privacy

The package has no telemetry or network service. It does not intentionally log
frame content, image bytes, capture filenames, device serial numbers or output
paths. Do not log callbacks or raw exceptions in an integrating application:
filesystem/platform errors may contain private paths or device identifiers.
Third-party camera backend logging is outside this package's complete control;
the UVC adapter requests error-only native logging.

`originalJpeg`, `croppedJpeg` and native/intermediate buffers contain sensitive
personal data. Dart garbage collection does not guarantee secure erasure.
Caller code owns retention, access control, encryption, upload and deletion.
Manual/auto capture with the UVC adapter and no `saveDirectory` writes no image
files. The example uses this configuration; only the explicit pair-export action
writes images. Disable/remove that diagnostic action in a kiosk that forbids
export. The existing `saveDirectory` opt-in is supplied by the caller; use an
ACL-protected local directory,
validate it against application policy, and avoid public/shared directories.
The package creates missing directories and does not enforce an allowed root.
Random filenames avoid document identifiers and exclusive creation prevents
replacing existing captures. The root persistence option saves only cropped
JPEG; the separate example pair-export action saves both original and crop. The optional desktop candidate creates a temporary full-frame image via
its dependency and removes it in `finally`; abrupt termination can leave it
behind. Assess this before production use.

Stopping closes device resources; it does not delete files already written.
No OCR, face recognition or document authenticity guarantee is provided. Treat
untrusted camera frames and filesystem destinations as application inputs.

Report a vulnerability privately to the repository owner through GitHub's
private reporting facility if enabled. Do not upload real identity documents,
keys, filenames or customer frames to public issues or CI artifacts. Use
synthetic images and redact identifying metadata in diagnostic evidence.

## Diagnostic output

Debug builds print bounded local metadata through `debugPrint`; profile/release
builds require explicit opt-in (`enableDebugLogging` / `DOC_CAPTURE_LOGS`). Logs
contain state/quality/geometry/performance metrics and safe error codes, not
image bytes, document text, device identifiers/names, file paths or raw exception
messages/details. No upload or file logging is performed by the package. The
integrating application's other logs and stream error handlers are outside this
redaction boundary. Disable diagnostics for normal unattended operation and
apply the app's retention policy to any console output captured to disk.
