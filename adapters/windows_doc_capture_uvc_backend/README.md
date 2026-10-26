# Internal Windows capture backend

Windows-only derivative of flutter_ffi_uvc 1.1.2 (BSD-3-Clause). See LICENSE and
upstream.json for original file hashes. No mobile/libuvc/third-party binaries
are vendored. Native and Dart API retain upstream implementation except package,
DLL, plugin registration and channel namespaces, Windows-only platform guard,
and bounded native sampling (rgba_sampler.h + copyLatestSampledFrames).

Use through windows_doc_capture_uvc, not as a second camera owner. Independent
namespaces allow a host dependency on the original plugin without channel/DLL
replacement; that does not permit simultaneous access to the same physical camera.
Do not add dependency_overrides. Stop/await the host camera before capture and
await capture disposal before returning ownership. FFI buffers are call-scoped;
no external pointer escapes and snapshots use the original full-frame path.
