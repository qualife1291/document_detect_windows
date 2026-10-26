# Kiosk integration and memory-only capture review

- Source: direct user request 2026-10-26 to review the package, push code/files,
  avoid saving captures on the machine and verify kiosk integration.
- Authorization: review, fixes, regression checks, commit and push main under
  the current conversation's explicit authorization.
- Scope: example captures manual/auto JPEGs in memory only; remove automatic
  save controls. Preserve the separately requested, explicit comparison export.
  Keep root saveDirectory as an existing caller opt-in API, but remove it from
  the default integration recipe and document that it writes when supplied.
- Lifecycle: hidden/paused/detached example windows stop camera, cancel pending
  capture and reject late results/start completions. Inactive alone must not stop
  a native folder dialog or a temporarily unfocused window. Foreground does not
  reopen automatically; serialize a new explicit start after cleanup.
- Review: ownership, queues, worker cancellation, image disposal, native/plugin
  coexistence, privacy and host integration guidance. No new frame history,
  global cache clearing, optical sharpening, quality threshold calibration,
  upload, real-image fixtures or deletion of previously exported files.
- Done: meaningful memory-only/lifecycle regressions, analyze and tests for
  affected projects, stable format, Windows matrix build/tests, review evidence
  and source commit pushed with all relevant repository files.
- Limits: Linux and Windows CI have no physical kiosk camera/GPU/driver. No claim
  of 24/7 readiness, focus quality, OS secure erasure or cleanup after forced kill.

## Completion

Done at source 0535530; Windows CI 40311068502 passed the three supported SDKs.
Review, evidence and remaining physical validation are documented in
[the review](../docs/progress/kiosk-memory-review.md). Product readiness remains
separate from task completion. Explicit export and caller opt-in persistence
remain documented; no automatic image file saving is configured in the example.
