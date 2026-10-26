# Example: export the original/crop comparison pair

User approved adding a result-screen export action after log 8 review showed that
pixel-level original/crop comparison is needed to diagnose remaining softness.
Scope: [spec](../../specs/export-capture-pair.md). Feature source `d6b64c9`,
SDK-compatible test finder `2a1644b`. Root/camera/backend/CI source trees are
unchanged from the prior validated `f4e215c` baseline.

## Delivered behavior

After manual or automatic capture, choose **Xuất cặp ảnh gốc + crop**, select a
folder in Windows, and wait for success. A unique `capture-<timestamp>-<suffix>`
subfolder contains `original.jpg` and `cropped.jpg` from that CapturedDocument.
The export path is selectable for copying. No prior save-checkbox selection is
needed; that checkbox keeps its earlier crop-only saving behavior.

Export writes existing JPEG bytes asynchronously, without decoding, resizing or
re-encoding. It starts only on the result screen, after camera stop. A busy guard
prevents double-clicks/retake/Esc; a cancelled picker writes nothing. Each export
uses a fresh staging folder and closes/flushes both files before publishing the
folder. Cancellation/error cleans only owned staging data. Completed exports
remain. Force termination, media removal or failed filesystem cleanup can leave
staging data; no unrelated files or prior exports are swept/deleted.

Unmount/late picker completion cannot start another write. Unmount cancels at
write boundaries; graceful exit awaits in-flight write cleanup. No camera calls,
frame queues, image-cache clears or additional preview listeners are introduced.
Safe `export_pair` logs contain start/success/cancelled/error, byte counts and
error type only, never paths/raw exception text/image contents. The example-only
Windows picker is pinned at file_selector_windows 0.9.3+5 for Flutter 3.32.8 support.

## Validation

18 example tests include the prior 7 and 11 new regressions: unchanged bytes from
one capture, repeated exports/no overwrite, Unicode/space paths, cancellation
before/either write, partial second-write failure, missing destination, picker
cancel/double-click/Esc, awaiting both files, errors/retry/redaction, unmount
before/during IO, and graceful exit. Native folder UI is replaced by an injected
picker in widget tests; manual Windows interaction still needs operator testing.

An intermediate floor run found that FilledButton.icon has a private subclass
on older Flutter; the test finder was updated to include subclasses, with no
assertions removed or runtime changes. CI 40297949185 is intermediate evidence,
not the final successful matrix. Source-linked SDK results are recorded in
[coverage metadata](logs/export-capture-pair/source.json).

Windows builds validate native plugin registration/linking. They do not certify
physical-camera clarity/focus, real folder-dialog interaction, driver stability,
Windows accessibility or 24–168 h hardware soak. Product HANDOVER stays CHUA DAT.


Final validation: [Windows run 40298617835](https://github.com/qualife1291/document_detect_windows/actions/runs/40298617835),
source `2a1644b06ca429c31a882a76dee1d59bde6fa279`, passed Flutter 3.32.8/3.41.9/3.47.8.
Each Windows SDK passed 116 root/11 UVC/18 example tests, 3 benchmarks/native CTest,
60s synthetic endurance and x64 release example build including file_selector_windows.
Stable also passed 58-file formatting and upstream/capture plugin coexistence build.
Linux 3.32.8/3.41.9/3.47.7 passed example pub get/analyze/18 tests and stable format.
No root/backend/adapter changes required reimplementation; their trees match the
prior validated baseline and the Windows full matrix reran them nonetheless.
Only documentation/metadata changed after the validated source.
