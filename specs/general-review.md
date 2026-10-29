# General lifecycle/performance review

- Source: direct user request 2026-10-29 for another general review, with standing
  authorization to fix, test, commit and push document_detect_windows only.
- Review: root capture/analyzer/worker/preview/crop, UVC ownership and cleanup,
  copied kiosk single/batch callbacks, memory/file policy and integration docs.
- Confirmed fixes: failed native cleanup must retain the source handles and root
  ownership until closure succeeds; stop during failed startup must verify cleanup;
  failed terminal dispose may be retried without notifying disposed UI/streams;
  failed enumeration cleanup must not release ownership prematurely. Release
  session callbacks after cleanup. Copied widget must publish idle on explicit
  stop/hide and isolate callback failures from cleanup.
- Additional routing fix: UVC numeric IDs are process-local; expose normalized
  Windows symbolic-link IDs and resolve to the current numeric handle on open.
  Reject legacy numeric IDs rather than silently selecting a different camera;
  document required settings migration and USB/driver path-change limitations.
- Verification: reproduce failure paths first, targeted regressions, analyze and
  tests for affected root/UVC/example, supported SDKs and Windows matrix/release
  plus copied-host fixture. Reuse unchanged native sampler evidence where valid.
- No storage-policy/API threshold/warp changes, no upload/OCR, no app-global cache
  clear, no automatic restart loops or claimed physical 24/7 certification.
- Scope done requires review/evidence, updated handover and pushed commits.
