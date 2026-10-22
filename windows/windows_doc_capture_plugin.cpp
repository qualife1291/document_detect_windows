#include "include/windows_doc_capture/windows_doc_capture_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>

namespace {
class WindowsDocCapturePlugin : public flutter::Plugin {
 public:
  explicit WindowsDocCapturePlugin(flutter::PluginRegistrarWindows* registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "windows_doc_capture/platform",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([](const auto& call, auto result) {
      if (call.method_name() != "architecture") {
        result->NotImplemented();
        return;
      }
#if defined(_M_X64) || defined(__x86_64__)
      result->Success(flutter::EncodableValue("x64"));
#elif defined(_M_ARM64) || defined(__aarch64__)
      result->Success(flutter::EncodableValue("arm64"));
#else
      result->Success(flutter::EncodableValue("unsupported"));
#endif
    });
  }
  ~WindowsDocCapturePlugin() override { channel_->SetMethodCallHandler(nullptr); }
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
}
void WindowsDocCapturePluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(std::make_unique<WindowsDocCapturePlugin>(windows_registrar));
}
