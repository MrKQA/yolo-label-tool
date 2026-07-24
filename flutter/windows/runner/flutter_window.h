#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterWindowBrandingChannel();
  bool ApplyWindowBranding(const std::string& display_name,
                           const std::string& icon_path,
                           std::string* error_message);
  void RestoreDefaultWindowIcons();
  void DestroyCustomWindowIcons();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_branding_channel_;
  HICON default_large_icon_ = nullptr;
  HICON default_small_icon_ = nullptr;
  HICON custom_large_icon_ = nullptr;
  HICON custom_small_icon_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
