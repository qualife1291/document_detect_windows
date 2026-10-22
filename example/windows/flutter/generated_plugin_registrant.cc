//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_ffi_uvc/flutter_ffi_uvc_plugin_c_api.h>
#include <windows_doc_capture/windows_doc_capture_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterFfiUvcPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterFfiUvcPluginCApi"));
  WindowsDocCapturePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowsDocCapturePlugin"));
}
