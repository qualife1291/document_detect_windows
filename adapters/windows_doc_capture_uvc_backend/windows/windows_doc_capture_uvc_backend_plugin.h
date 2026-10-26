#ifndef FLUTTER_PLUGIN_WINDOWS_DOC_CAPTURE_UVC_BACKEND_PLUGIN_H_
#define FLUTTER_PLUGIN_WINDOWS_DOC_CAPTURE_UVC_BACKEND_PLUGIN_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <vector>

#include "uvc_mf_backend.h"

namespace windows_doc_capture_uvc_backend {

// Windows counterpart of the Android WindowsDocCaptureUvcBackendPlugin: implements the
// windows_doc_capture_uvc_backend/texture and windows_doc_capture_uvc_backend/usb method channels and the
// windows_doc_capture_uvc_backend/device_events event channel over the Media Foundation
// backend living in the same DLL.
class WindowsDocCaptureUvcBackendPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit WindowsDocCaptureUvcBackendPlugin(flutter::PluginRegistrarWindows* registrar);
  ~WindowsDocCaptureUvcBackendPlugin() override;

  WindowsDocCaptureUvcBackendPlugin(const WindowsDocCaptureUvcBackendPlugin&) = delete;
  WindowsDocCaptureUvcBackendPlugin& operator=(const WindowsDocCaptureUvcBackendPlugin&) = delete;

 private:
  // One registered Flutter texture. A texture is bound to at most one session
  // and a session to at most one texture. The session's frame listener
  // carries this struct as its user_data.
  struct PreviewTexture {
    WindowsDocCaptureUvcBackendPlugin* plugin = nullptr;
    int64_t texture_id = -1;
    // Registry id of the bound session, 0 when unbound. Read on the raster
    // thread by CopyPixelBuffer, written on the platform thread.
    std::atomic<int64_t> session{0};
    std::unique_ptr<flutter::TextureVariant> variant;
    FlutterDesktopPixelBuffer pixel_buffer{};
    std::vector<uint8_t> pixels;
  };

  void HandleTextureCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleUsbCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  const FlutterDesktopPixelBuffer* CopyPixelBuffer(PreviewTexture* texture);
  // Frame listener registered with the backend. user_data is a
  // PreviewTexture.
  static void OnNativeFrameAvailable(void* context, int64_t sequence);
  // Unbinds a texture from its session and clears the frame listener.
  void DetachTexture(PreviewTexture* texture);

  // Device attach/detach notifications via a hidden window. Created while the
  // event channel has a listener.
  void StartDeviceNotifications();
  void StopDeviceNotifications();
  void OnDeviceChange(WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK NotifyWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  flutter::TextureRegistrar* textures_ = nullptr;
  std::map<int64_t, std::unique_ptr<PreviewTexture>> preview_textures_;

  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      device_event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
      device_event_sink_;
  HWND notify_hwnd_ = nullptr;
  HDEVNOTIFY device_notify_ = nullptr;
};

}  // namespace windows_doc_capture_uvc_backend

#endif  // FLUTTER_PLUGIN_WINDOWS_DOC_CAPTURE_UVC_BACKEND_PLUGIN_H_
