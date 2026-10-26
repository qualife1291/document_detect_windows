# Adaptive preview/detail implementation review

Direct request: implement the accepted sharpness/preview proposal and account
for a host application's other sources of lag. Runtime source 668fffd, SDK test
harness 66b553e, strict MSVC fixture correction fd0894a; deterministic-clock regression b6076ff. See
[scope](../../specs/adaptive-preview-detail.md) and
[integration instructions](../integration-performance.md).

## Behavior and review

- Cadence uses sampling start and never replays missed slots. A regression uses
  a 10 ms native read cost; this caught the earlier additive-period drift.
- Native sampling now creates bounded outputs before FFI transfer. Analysis
  nearest <=640 preserves threshold intent; preview bilinear 640/960/1280 improves
  sampling detail without upscaling. Both can share the same locked frame/seq.
  Full native camera conversion/storage and full snapshot costs remain.
- The controlled Windows-only BSD derivative has a separate package, DLL,
  registration and channel namespace; original per-file hashes and exact license
  are retained. No pub-cache modification/private session address/override.
- A session governor considers actual sampling, decoder and host build/raster
  costs, expires stale observations, reduces one level/second and requires 10
  healthy seconds per recovery step. Native-copy cost independently backs off
  reads. This cannot bound total host CPU or fix arbitrary driver/GPU problems.
- One native call/decoder in flight; no retry/frame queue. TickerMode-disabled or
  inactive consumers suppress bitmap demand. Session changes invalidate pending
  decodes even with a reused stream. Timing observers/subscriptions/images are
  removed/disposed; render objects retain their own clones until repaint.
- Snapshot still uses full negotiated stream, fresh detection and cancellable
  worker. Exact aligned crop includes both edge pixels and skips interpolation;
  fractional/perspective crop, margin and output caps remain. No geometry snap,
  sharpening, fake MP or change to quality thresholds.
- JPEG90 stays the API default. Example 92 follows the fine-print benchmark:
  MSE 5.4484→3.6149 (~34% decrease), 354022→378906 bytes (~7% increase). 95 is larger
  again 461853 bytes. Synthetic grayscale compression, not an optical test.
- UI exposes actual camera dimensions/MP and an aspect-aware document pixel
  estimate. Small-document/focus hints do not add capture gates. Host apps own
  camera handoff, hidden-route stop and retention/cache policies.

## Regression coverage

116 root tests include previous lifecycle/lighting/document-shape/5–8MP cases,
new pixel-exact crop, hidden/inactive demand, late session decode, host UI load
and slow recovery.11 adapter tests include bounded8MP profiles/full snapshots,
cadence with expensive reads, busy/unmount/capture pause and cleanup/restart.
7 example tests retain capture/retake, reduced-motion/DPI/result cache behavior.
Native C++ checks bounds/canaries, null/short buffers, RGBA interpolation,
portrait/landscape 5/8 MP, identity pixels and no upscale. Native tests run with
warnings-as-errors; the fixture's explicit byte conversion fixes MSVC C4244
rather than lowering the warning level. An SDK 3.32 test guard issue was fixed
by collecting async samples and making assertions after the awaited pump.

## Validation

Final source-linked results and commands are recorded in
[coverage metadata](logs/adaptive-preview-detail/source.json). Windows matrix
builds the example, and stable additionally builds a host containing both the
original and internal plugins; no physical camera is opened by that fixture.
Linux is supplemental, not a Windows camera/driver test.

CI runs 40281840343/40282224168 failed strict fixture compilation; run
40282426987 passed native/build/coexistence on stable and the 3.41.9 job but
exposed a wall-clock-sensitive cadence assertion on 3.32.8. These intermediate
runs are not the final matrix evidence. The regression now models 13 exact slots
and a 10 ms copy; restoring completion-based cadence demonstrably produces 7
frames instead of 13. No elapsed-time tolerance was loosened. The final record must name the successful
source/run explicitly. No tests/assertions/warning levels were disabled.

Physical preview FPS/latency, optical clarity/focus, GPU stability, Windows
accessibility and 24–168 h hardware soak remain unverified after this change.
Product [HANDOVER](HANDOVER.md) stays CHUA DAT.


Final Windows matrix passed:
[run40283388912](https://github.com/qualife1291/document_detect_windows/actions/runs/40283388912),
source `b6076ff9d8a07c07535fd3ee3d0e53c40b23b398`, Flutter 3.32.8/3.41.9/3.47.8.
Each SDK passed 116 root + 11 adapter + 7 example tests, 3 benchmarks, native CTest,
60s synthetic endurance and release example build. Stable also passed 56-file
format and the host-with-both-plugins release build/license/registration checks.
Linux 3.32.8/3.41.9/3.47.7 passed 116/11/7, 3 benchmarks/native test/endurance 30 s;
the final clock seam was independently re-analyzed/tested on every SDK. Root and
example baseline trees exactly match the final source (git tree hashes recorded).
Historical aggregate evidence folders were preserved; this task has its own
logs/source record. Only documentation/metadata changed after the validated source.
