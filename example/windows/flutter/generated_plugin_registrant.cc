//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <file_selector_windows/file_selector_windows.h>
#include <windows_doc_capture/windows_doc_capture_plugin.h>
#include <windows_doc_capture_uvc_backend/windows_doc_capture_uvc_backend_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  WindowsDocCapturePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowsDocCapturePlugin"));
  WindowsDocCaptureUvcBackendPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowsDocCaptureUvcBackendPluginCApi"));
}
