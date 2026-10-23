# Camera / continuous-operation review — 2026-10-23

Linux validation passed on Flutter 3.32.8, 3.41.9 and 3.47.7: 89 package
tests, 3 example tests, benchmark and 30 s endurance per SDK. Both optional
desktop SDK analyzers also passed. Windows validation also passed on the same
three SDKs, including release builds and 60 s synthetic endurance per SDK at
source `ca13fd4`. Physical 24/7 acceptance remains
pending. This report distinguishes deterministic regression coverage from
camera/driver and document-dataset evidence that is not available in cloud CI.

| Finding | Change | Regression evidence |
| --- | --- | --- |
| Large frames sampled even when analysis cannot keep up | Optional adapter demand/backpressure, controller rate limit, no sampling during capture, longest-side size bound | Analyzer pending-frame bound; endurance bursts; portrait 8 MP geometry |
| Excess allocation in detector hot loops | Constant neighbor offsets, scalar polygon inclusion, integer contour points before quad fitting | Existing detector/crop tests plus document/light matrix and benchmark |
| Full JPEG bytes copied a second time | Keep encoder buffers directly; exiting worker transfers result ownership | Exact saved JPEG bytes and full 5/8 MP image dimensions |
| Stop waits for CPU crop/JPEG and late results can escape | Cancellable worker and snapshot wait, timeout, session result check | Kill busy worker; cancel actual 8 MP crop with empty output directory; hung/late native snapshot |
| Enumeration/start/dispose can race | Single controller lease in a Dart isolate and adapter native-operation queue | Competing controllers; unused controller dispose; stop during start; immediate dispose; queue error recovery |
| Concurrent dispose can return before cleanup | Shared disposal future installed before callbacks | Concurrent disposal identity/completion; native stop called once; graceful-window-exit widget test |
| An intermediate cleanup failure could skip later resources | Attempt subscription/analyzer/native cleanup independently, rethrow first failure | Existing native-stop-error/public-stream closure regression; repeated session teardown |
| Worker death or stall could hold busy state forever | Error/exit monitoring, 5 s analysis watchdog, fail closed | Analyzer start/dispose regression; capture worker error/timeout regression; CI pipeline exercises monitor lifecycle |
| Stale-frame reset rearmed the captured paper | Preserve cooldown and removal requirement across analysis expiry | Simulated multi-day monotonic transitions with same paper |
| Partially written `.jpg` visible during save/kill | Exclusive random `.part`, flush, same-directory rename; remove on cancellation | Exact saved bytes, unique names, IO error propagation, cancelled crop leaves no file |
| Camera-desktop initialization listener could survive an error | Explicit initialization subscription cancellation and bounded initialization/picture waits | Optional adapter analyzer and Windows release compilation; native failure paths still need hardware |
| Unawaited widget teardown errors / window close | Await disposal in graceful exit hook, handle fire-and-forget disposal error | Example exit waits on gated native stop, existing kiosk UI tests |

## Document and lighting scope

Synthetic geometry: 1.586 landscape/portrait cards, 1.42 legacy card, portrait A4,
square medical card and 2.7 wide slip. Diffuse and mild-shadow cases preserve a
quad. Under/overexposure, large localized glare and absent interior detail block
automatic capture. Weak contrast is rejected and reverse-polarity card detection
is exercised. Existing tests cover perspective, motion and incomplete framing.
Actual 2592x1944 and 3264x2448 buffers are detected/cropped/encoded; original JPEG
dimensions and full-coordinate corners are checked. Portrait 2448x3264 is also
analyzed. Names describe geometric fixtures, not recognition of real credentials.

No assertion certifies all document layouts, holograms, small glare patches,
severe shadows, textured desks, folds or occlusion. Those can still cause false
positives or rejected documents. A labelled physical dataset is required for
precision/recall, readability and threshold tuning.

## Endurance evidence and limits

[Development Linux run, 300 s](logs/hardening/linux-development-endurance-300s.txt)
used Flutter 3.47.7 in flutter-test mode: 110,460 offered frames, 7,364 reports,
103,096 dropped pending frames, at most one pending frame, peak process RSS
180,723,712 bytes (~172.4 MiB). RSS initially increased, then fluctuated around
165–171 MiB near the end. This is a development working-tree measurement,
not a 24 h leak test or an OS-independent memory threshold. Frame content is
reused synthetic RGBA; native 8 MP camera allocation/Texture delivery is absent.

Each final SDK validation also runs the endurance tool on the exact source under
test and records its own logs. See [HANDOVER](HANDOVER.md) for the source SHA,
workflow result and artifact provenance when the Windows matrix has completed.

Remaining release risks: upstream UVC full-frame readback still runs on the UI
isolate; desktop streams still transport full buffers; native driver operations
can take time to settle. No universal CPU, UI-frame-time or 24/7 guarantee is
made. Start with lower stream resolution/analysis rate on weak hardware and
measure on the target. Process kill/power loss cannot run dispose; stale app-owned
partial/temporary files and driver recovery must be exercised after relaunch.

The physical acceptance checklist and integration guidance are in
[continuous_operation.md](../continuous_operation.md). Hardware/accessibility
handover gates remain incomplete.

## Detector benchmark comparison

On the same Linux cloud machine, Flutter 3.47.7/flutter-test, identical benchmark
(5 warmup + 30 synthetic 640x480 images), run sequentially:

| Source | Mean | p95 | Throughput |
| --- | --- | --- | --- |
| Baseline `bf90e60` | 72.16 ms | 84.90 ms | 13.86 FPS |
| Optimized working tree | 52.05 ms | 67.61 ms | 19.21 FPS |

This sample reduces mean detector time by ~27.9%. It measures the detector only,
not native frame copying, UI smoothness, total CPU or physical-camera throughput.
A single hosted-machine comparison is not a guaranteed speedup on other CPUs.
Raw [baseline](logs/hardening/linux-baseline-benchmark.txt) and
[optimized](logs/hardening/linux-optimized-benchmark.txt) logs are retained.

## Windows endurance on the committed source

[Workflow](https://github.com/qualife1291/document_detect_windows/actions/runs/39909113059)
validated `ca13fd45e6bc96d37b2f551a86ccd68431de7232`. Each job also passed
89 package tests, 3 example tests, benchmark and release build. Endurance logs
are in the corresponding `logs/windows-*/endurance.txt` and artifact provenance
is in `logs/ci-provenance.json`.

| Flutter | Duration | Offered frames | Reports | Dropped pending frames | Peak process RSS bytes |
| --- | --- | --- | --- | --- | --- |
| 3.32.8 | 60 s | 19950 | 1330 | 18620 | 147017728 |
| 3.41.9 | 60 s | 26160 | 1744 | 24416 | 153059328 |
| 3.47.7 | 60 s | 21780 | 1452 | 20328 | 157982720 |

These Windows tests use synthetic RGBA under flutter-test, without a camera,
USB transport, native Texture or a kiosk's background workload. They verify
bounded pending-frame behavior and record memory; they are not a physical-camera
soak, a leak-free certificate or a Windows memory limit.

Diagnostics update: this source also includes 10 tests for JSON output,
redaction, coalescing, disabled logging, failing sinks and heartbeat teardown.
See [README](../../README.md#copy-diagnostic-logs-from-physical-testing).

Physical-test follow-up: cadence, clipped-background selection, weak-edge fallback,
white/custom frame styling, faster warp and opt-in filters are covered by 13
additional tests. See [physical log review](PHYSICAL_LOG_REVIEW.md).
