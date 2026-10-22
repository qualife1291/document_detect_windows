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
`saveDirectory` is supplied by the caller; use an ACL-protected local directory,
validate it against application policy, and avoid public/shared directories.
The package creates missing directories and does not enforce an allowed root.
Random filenames avoid document identifiers and exclusive creation prevents
replacing existing captures. Only cropped JPEG is deliberately saved by the UVC
flow. The optional desktop candidate creates a temporary full-frame image via
its dependency and removes it in `finally`; abrupt termination can leave it
behind. Assess this before production use.

Stopping closes device resources; it does not delete files already written.
No OCR, face recognition or document authenticity guarantee is provided. Treat
untrusted camera frames and filesystem destinations as application inputs.

Report a vulnerability privately to the repository owner through GitHub's
private reporting facility if enabled. Do not upload real identity documents,
keys, filenames or customer frames to public issues or CI artifacts. Use
synthetic images and redact identifying metadata in diagnostic evidence.
