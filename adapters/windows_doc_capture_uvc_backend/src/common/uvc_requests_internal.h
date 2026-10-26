// Backend-facing side of the request queue in uvc_requests.cpp. Not part
// of the Dart-facing ABI.
#ifndef WINDOWS_DOC_CAPTURE_UVC_BACKEND_REQUESTS_INTERNAL_H_
#define WINDOWS_DOC_CAPTURE_UVC_BACKEND_REQUESTS_INTERNAL_H_

#include "../include/windows_doc_capture_uvc_backend.h"

#ifdef __cplusplus
extern "C" {
#endif

// Queues teardown of the session and returns at once. The worker drains the
// queue, closes the device, and then calls uvc_session_finalize. Nothing
// here waits on another thread, so a caller that is a Dart isolate never
// blocks while a native thread is calling back into it. With notify zero
// the request listener is cleared first and nothing is reported, which is
// what a finalizer needs. A second call on the same session does nothing.
void uvc_requests_destroy(uvc_session_t *session, int notify);

// Implemented by the backend. Runs on the session worker once the queue has
// drained and the device is closed. Waits for outstanding acquire pins,
// clears the listener slots, and frees the session. The pointer is invalid
// afterwards.
void uvc_session_finalize(uvc_session_t *session);

#ifdef __cplusplus
}
#endif

#endif  // WINDOWS_DOC_CAPTURE_UVC_BACKEND_REQUESTS_INTERNAL_H_
