#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.Foundation.h>

#include "flutter/generated_plugin_registrant.h"

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
  appearance_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "music_time/appearance",
      &flutter::StandardMethodCodec::GetInstance());
  appearance_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "getSystemAccent") result->Success(SystemAccent());
    else result->NotImplemented();
  });
  try {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    appearance_apartment_initialized_ = true;
    ui_settings_ = winrt::Windows::UI::ViewManagement::UISettings();
    const HWND window = GetHandle();
    accent_changed_ = ui_settings_.ColorValuesChanged([window](const auto&, const auto&) {
      // UISettings events may arrive on a worker thread. Marshal to the runner.
      ::PostMessage(window, WM_APP + 77, 0, 0);
    });
  } catch (...) { ui_settings_ = nullptr; }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (ui_settings_) {
    try { ui_settings_.ColorValuesChanged(accent_changed_); } catch (...) {}
    ui_settings_ = nullptr;
  }
  appearance_channel_.reset();
  if (appearance_apartment_initialized_) {
    winrt::uninit_apartment();
    appearance_apartment_initialized_ = false;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_APP + 77) {
    if (appearance_channel_) {
      appearance_channel_->InvokeMethod("accentChanged",
          std::make_unique<flutter::EncodableValue>(SystemAccent()));
    }
    return 0;
  }
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

flutter::EncodableValue FlutterWindow::SystemAccent() noexcept {
  try {
    if (ui_settings_) {
      const auto color = ui_settings_.GetColorValue(
          winrt::Windows::UI::ViewManagement::UIColorType::Accent);
      const int64_t argb = 0xff000000LL | (static_cast<int64_t>(color.R) << 16) |
          (static_cast<int64_t>(color.G) << 8) | color.B;
      return flutter::EncodableValue(argb);
    }
  } catch (...) {}
  return flutter::EncodableValue();
}
