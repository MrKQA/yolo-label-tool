#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

const std::string* StringArgument(const flutter::EncodableMap& arguments,
                                  const char* name) {
  const auto iterator =
      arguments.find(flutter::EncodableValue(std::string(name)));
  if (iterator == arguments.end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&iterator->second);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  default_large_icon_ = reinterpret_cast<HICON>(
      SendMessage(GetHandle(), WM_GETICON, ICON_BIG, 0));
  default_small_icon_ = reinterpret_cast<HICON>(
      SendMessage(GetHandle(), WM_GETICON, ICON_SMALL, 0));
  if (!default_large_icon_) {
    default_large_icon_ =
        reinterpret_cast<HICON>(GetClassLongPtr(GetHandle(), GCLP_HICON));
  }
  if (!default_small_icon_) {
    default_small_icon_ =
        reinterpret_cast<HICON>(GetClassLongPtr(GetHandle(), GCLP_HICONSM));
  }
  RegisterWindowBrandingChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_branding_channel_.reset();
  RestoreDefaultWindowIcons();
  DestroyCustomWindowIcons();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterWindowBrandingChannel() {
  window_branding_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "yolo_label_tool/window_branding",
          &flutter::StandardMethodCodec::GetInstance());
  window_branding_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "update") {
          result->NotImplemented();
          return;
        }
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!arguments) {
          result->Error("invalid_arguments",
                        "Window branding arguments must be a map.");
          return;
        }
        const std::string* display_name =
            StringArgument(*arguments, "displayName");
        const std::string* icon_path = StringArgument(*arguments, "iconPath");
        if (!display_name || !icon_path) {
          result->Error("invalid_arguments",
                        "displayName and iconPath must be strings.");
          return;
        }
        std::string error_message;
        if (!ApplyWindowBranding(*display_name, *icon_path, &error_message)) {
          result->Error("window_branding_failed", error_message);
          return;
        }
        result->Success();
      });
}

bool FlutterWindow::ApplyWindowBranding(const std::string& display_name,
                                        const std::string& icon_path,
                                        std::string* error_message) {
  const std::wstring wide_name = Utf8ToWide(display_name);
  if (wide_name.empty()) {
    *error_message = "The display name is empty or invalid UTF-8.";
    return false;
  }

  HICON new_large_icon = nullptr;
  HICON new_small_icon = nullptr;
  if (!icon_path.empty()) {
    const std::wstring wide_icon_path = Utf8ToWide(icon_path);
    if (wide_icon_path.empty()) {
      *error_message = "The icon path contains invalid UTF-8.";
      return false;
    }
    new_large_icon = reinterpret_cast<HICON>(LoadImageW(
        nullptr, wide_icon_path.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
        GetSystemMetrics(SM_CYICON), LR_LOADFROMFILE));
    new_small_icon = reinterpret_cast<HICON>(LoadImageW(
        nullptr, wide_icon_path.c_str(), IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
        LR_LOADFROMFILE));
    if (!new_large_icon || !new_small_icon) {
      if (new_large_icon) {
        DestroyIcon(new_large_icon);
      }
      if (new_small_icon) {
        DestroyIcon(new_small_icon);
      }
      *error_message =
          "Windows could not load the selected .ico file. Error " +
          std::to_string(GetLastError()) + ".";
      return false;
    }
  }

  if (!SetWindowTextW(GetHandle(), wide_name.c_str())) {
    if (new_large_icon) {
      DestroyIcon(new_large_icon);
    }
    if (new_small_icon) {
      DestroyIcon(new_small_icon);
    }
    *error_message = "Windows could not update the window title.";
    return false;
  }

  if (icon_path.empty()) {
    RestoreDefaultWindowIcons();
  } else {
    SendMessage(GetHandle(), WM_SETICON, ICON_BIG,
                reinterpret_cast<LPARAM>(new_large_icon));
    SendMessage(GetHandle(), WM_SETICON, ICON_SMALL,
                reinterpret_cast<LPARAM>(new_small_icon));
  }
  DestroyCustomWindowIcons();
  custom_large_icon_ = new_large_icon;
  custom_small_icon_ = new_small_icon;
  return true;
}

void FlutterWindow::RestoreDefaultWindowIcons() {
  if (!GetHandle()) {
    return;
  }
  SendMessage(GetHandle(), WM_SETICON, ICON_BIG,
              reinterpret_cast<LPARAM>(default_large_icon_));
  SendMessage(GetHandle(), WM_SETICON, ICON_SMALL,
              reinterpret_cast<LPARAM>(default_small_icon_));
}

void FlutterWindow::DestroyCustomWindowIcons() {
  if (custom_large_icon_) {
    DestroyIcon(custom_large_icon_);
    custom_large_icon_ = nullptr;
  }
  if (custom_small_icon_) {
    DestroyIcon(custom_small_icon_);
    custom_small_icon_ = nullptr;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
