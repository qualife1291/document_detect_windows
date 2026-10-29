# General package review

Source: direct user request 2026-10-29. Scope includes the root controller,
analysis/capture workers, preview/crop, UVC teardown/device routing, copied kiosk
single/batch widget, ownership, diagnostics, file policy and integration guide.

## Confirmed findings and fixes

| Priority | Trigger / previous behavior | Result |
| --- | --- | --- |
| P1 | Native stop/dispose failed; root released ownership and UVC discarded retry handles | Retain the owner, native handle and failed texture token until closure succeeds. Another owner fails closed; explicit stop/dispose can retry. Stopped sources cannot copy frames from retained handles. |
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

Final SDK matrix/source evidence is recorded alongside this review after the
checks complete. Synthetic/hosted CI does not validate physical focus, GPU/USB,
actual app load, accessibility or 24–168 hour operation. The product gate remains
[CHUA DAT](HANDOVER.md); build coexistence is not concurrent camera access.
