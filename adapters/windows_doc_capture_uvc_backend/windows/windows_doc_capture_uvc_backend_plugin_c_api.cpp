#include "include/windows_doc_capture_uvc_backend/windows_doc_capture_uvc_backend_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "windows_doc_capture_uvc_backend_plugin.h"

void WindowsDocCaptureUvcBackendPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  windows_doc_capture_uvc_backend::WindowsDocCaptureUvcBackendPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
