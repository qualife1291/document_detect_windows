# General package review

Source: direct user request 2026-10-29. Scope includes the root controller,
analysis/capture workers, preview/crop, UVC teardown/device routing, copied kiosk
single/batch widget, ownership, diagnostics, file policy and integration guide.

## Confirmed findings and fixes

| Priority | Trigger / previous behavior | Result |
| --- | --- | --- |
| P1 | Native stop/dispose failed; root released ownership and UVC discarded retry handles | Retain the owner, native handle and failed texture token until closure succeeds. The same or another owner cannot reopen; explicit stop/dispose can retry. Stopped sources cannot copy frames from retained handles. |
| P1 | Stop overlapped failed startup or enumeration teardown | Retry/verify teardown instead of falsely granting the next owner access. Failed terminal dispose closes notifications once and can retry cleanup. |
| P1 | Saved numeric UVC ID after another process enumerated webcams in a different order | Expose normalized Windows symbolic links and resolve to the current native handle. Legacy numbers fail closed and require explicit reselection. USB-port/driver changes can still change paths. |
| P1 | Native closure failed while the kiosk released host hardware ownership | Keep the host release callback until native stop and idempotent release succeed; retry before acquiring again. Retain a retryable cleanup owner after unmount, removing it once successful. |
| P2 | Explicit stop/cancel during configure left the host enum at processing/clear | Emit idle for explicit pause; preserve error on camera failure until explicit recovery. Install the stop future before callbacks can reenter. Callback exceptions cannot interrupt teardown. |
| P2 | Session callbacks retained host/controller references after cleanup; dispose failure logged disposed | Release session callbacks; emit camera_cleanup_pending on failed closure and disposed only on success. Log safe metadata, not images/paths/raw messages. |

These failure paths were reproduced before fixes (failed ownership handoff, lost
UVC dispose handle and missing idle callback). Regression tests exercise observable
ownership, repeated cleanup, terminal state, enumeration/start races, camera
reordering, callback errors/reentrancy and unmount recovery.

## Performance and integration review

Existing bounded sampling/backpressure remain: analysis at most 640 px, adaptive
bitmap preview, one decode and one capture worker; stale results are rejected by
session epoch. No per-frame retry queue, busy loop, image history or app-global
image-cache clear was added. Retry is explicit. A failed driver operation may
retain resources deliberately until closure is confirmed; reporting success and
opening a competing camera would be unsafe.

No detector, native sampler, warp/JPEG algorithm or capture file policy changed.
Use UVC without saveDirectory for memory-only captures. The example export-pair
button remains an explicit diagnostic write; the optional desktop dependency
creates a temporary still and is unsuitable when capture files are prohibited.
The host still owns uploaded/history bytes, network work and camera_windows
arbitration. Its acquire/configure/release futures must complete/fail within its
service budget; this widget cannot cancel arbitrary host or OS driver code.

Migration and awaited handoff: [kiosk guide](../integration/kiosk-getx.md).
No private device paths or original user photos are included in evidence.

## Validation

Validated code: `2ef4de5a50c7bcd084c9901b70d69995e4bf8afb`.
[Windows CI 40813822587](https://github.com/qualife1291/document_detect_windows/actions/runs/40813822587) passed Flutter 3.32.8/3.41.9/3.47.8:
121 root, 16 UVC and 40 example tests per SDK, all analyze checks, three
benchmarks, native sampler CTest, synthetic endurance 60 s and x64 release build.
Stable also passed format 60 and compiled the copied widget in an external host
with camera_windows 0.2.6+4 plus original/internal UVC; three DLLs, license and
independent registration verified. No physical camera was opened by that fixture.

Linux Flutter 3.32.8/3.41.9/3.47.7 each passed clean/pub get/analyze/full tests
for root/UVC/example (121/16/40). Stable configs/format restored. Evidence:
[source record](logs/general-review/source.json),
[CI details](logs/general-review/windows-ci.json) and per-SDK logs nearby.
Native backend, detector, capture/warp and preview component tree hashes match
baseline 02ae500; Windows reran their full checks. Root controller/UVC adapter and
copied widget have new lifecycle/routing regressions on this validated source.

Synthetic/hosted CI does not validate physical focus, GPU/USB, actual app load,
accessibility or 24–168 hour operation. The product gate remains
[CHUA DAT](HANDOVER.md); build coexistence is not concurrent camera access.
