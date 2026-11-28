#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

// window_manager konumları mantıksal piksel olarak alır (fiziksel / ölçek).
double ScaleFor(HWND hwnd) {
  UINT dpi = hwnd ? ::GetDpiForWindow(hwnd) : 0;
  return (dpi ? dpi : 96) / 96.0;
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
  RegisterScreenChannel();
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

// macOS'taki kanalın karşılığı. Ana ekranın görev çubuğu hariç alanı
// ([x, y, genişlik, yükseklik]) ve imleç ([x, y]); sol üst köşe başlangıç.
void FlutterWindow::RegisterScreenChannel() {
  screen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "app_signal/screen",
          &flutter::StandardMethodCodec::GetInstance());
  screen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const double scale = ScaleFor(GetHandle());
        if (call.method_name() == "cursor") {
          POINT p;
          if (!::GetCursorPos(&p)) {
            result->Success();
            return;
          }
          result->Success(flutter::EncodableValue(
              std::vector<double>{p.x / scale, p.y / scale}));
        } else if (call.method_name() == "visibleFrame") {
          HMONITOR monitor =
              ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
          MONITORINFO info{sizeof(MONITORINFO)};
          if (!::GetMonitorInfo(monitor, &info)) {
            result->Success();
            return;
          }
          const RECT& r = info.rcWork;
          result->Success(flutter::EncodableValue(std::vector<double>{
              r.left / scale, r.top / scale, (r.right - r.left) / scale,
              (r.bottom - r.top) / scale}));
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::OnDestroy() {
  screen_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
