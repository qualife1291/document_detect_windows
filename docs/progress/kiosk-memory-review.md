# Kiosk integration and memory-only capture review

Review requested 2026-10-26 after visual inspection of two exported image pairs.
Validated source: `05355304ed3974677c225bdddb04f9abec5ccb3a` (main).
[Windows CI 40311068502](https://github.com/qualife1291/document_detect_windows/actions/runs/40311068502)
passed Flutter 3.32.8, 3.41.9 and 3.47.8. Per SDK: root analyze/117 tests,
UVC analyze/11 tests, example analyze/22 tests, backend analyze/native CTest,
three synthetic benchmarks, 60-second synthetic endurance and x64 release build.
Stable additionally passed format (58 files) and the separate host build with
both upstream/internal plugins, distinct DLLs/license/registrations.

Linux 3.32.8/3.41.9 root/example analyze and 117/22 tests passed with logs.
Linux 3.47.7 root/example analyze and 117/22 tests passed before SDK switching
in the execution transcript; stable package configs and format were restored
afterward. Unchanged adapter/tool/CI trees were verified against 6e7929b; the
Windows matrix reran all suites. Evidence: [source record](logs/kiosk-memory-review/source.json),
[CI details](logs/kiosk-memory-review/windows-ci.json), logs in the same folder.
Subsequent changes in this task are documentation/evidence only.

## Findings and changes

| Area | Review result |
| --- | --- |
| Capture storage | UVC snapshot/crop/JPEG processing is in memory unless saveDirectory is explicitly supplied. Removed the example's automatic save controls and directory field; manual/auto capture no longer configures persistence. Explicit pair export remains available for diagnostics. |
| Hidden kiosk | Previously only bitmap demand stopped, leaving native camera/analysis active. Example now awaits stop on hidden/paused/detached, cancels startup/capture and rejects late results using an operation epoch. Foreground requires explicit restart after cleanup. |
| Focus/dialogs | Inactive alone leaves the camera session intact; hidden/paused/detached stop it. Returning before an old picker completes cannot resurrect that export. |
| Concurrent UI operations | Start/enumerate/capture/export/retake are blocked during cleanup and enumeration. Corrected old save-error and orange-frame guidance. |
| Memory and CPU | Existing bounded sampling, one decoder, capture worker cancellation and owned-image eviction remain intact. No new per-frame work, queues, retained result history or global cache operations. Full native 5/8 MP stream conversion/snapshot still has a hardware-dependent cost. |
| Integration and ownership | One controller owner per isolate; native operations serialized. Other isolates/processes/plugins require host coordination. Existing Windows CI host verifies the upstream and internal plugins coexist without registration/DLL collisions. |
| Optional desktop backend | Its dependency creates a temporary still image; it cannot satisfy no-capture-files. Recommend UVC with no saveDirectory. |
| Diagnostics/privacy | Numeric/state/error-type diagnostics only. Real uploaded image pairs/logs are not repository fixtures. Previously exported files remain caller-owned. |

## Regressions

- Root default pipeline returns decodable original/cropped JPEGs with savedPath
  null while file/directory/temp-directory access in the caller isolate throws.
  Code review verifies the capture worker performs only memory processing; this
  IO override test does not instrument native drivers or another isolate.
- Automatic controller result also asserts savedPath null.
- Widget tests cover hidden cleanup with a held native stop, no automatic reopen,
  explicit restart, inactive focus, hide during native startup, snapshot
  cancellation/late result, and permanent export cancellation across hide/resume.
- Existing capture/result/retake cycles, scoped image-cache eviction, graceful
  exit, export partial-write cleanup and failure/retry tests remain enabled.
- The new lifecycle harness uses legal Flutter transitions and a real-async
  startup gate; it waits for teardown instead of assuming one fixed scheduling
  interval. A completed one-operation stop gate is released before restarting.

## Integration contract and remaining validation

Use the UVC adapter, omit saveDirectory and consume/copy JPEG bytes in memory.
Only mount one preview per source. Host route/tab hiding must explicitly await
stop even if the application lifecycle remains resumed; removing a widget alone
cannot await native handoff. Cancel subscriptions instead of pausing them for
hours. Release host-owned JPEG/history/network work when no longer needed.

The visual pairs show soft small text already in the original 1280x720 frame;
crop interpolation adds some softening. No sharpness thresholds or interpolation
were changed during this lifecycle/storage review. Regional readability gates
and different warp filters need varied ID/medical/fine-print fixtures, calibration
and weak-device CPU measurements before changing auto-capture behavior.

Physical kiosk/camera/USB/GPU tests, camera-focus/exposure comparison, real OS
accessibility and 24–168 hour soak remain outstanding. Product gate: CHUA DAT.
An explicit export creates files by design; hide/remove it in production UI when
operators must not export. OS paging/crash dumps are outside package control.
