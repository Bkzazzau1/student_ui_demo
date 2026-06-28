#include "exam_window_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

constexpr char kChannelName[] = "kslas.exam_window";

class ExamWindowController {
 public:
  void Attach(HWND window) { window_ = window; }

  flutter::EncodableMap Enter() {
    flutter::EncodableMap response;
    response[flutter::EncodableValue("supported")] = flutter::EncodableValue(window_ != nullptr);
    if (window_ == nullptr) {
      response[flutter::EncodableValue("active")] = flutter::EncodableValue(false);
      response[flutter::EncodableValue("message")] = flutter::EncodableValue(std::string("Windows exam window is not available."));
      return response;
    }

    if (!active_) {
      previous_style_ = GetWindowLongPtr(window_, GWL_STYLE);
      previous_ex_style_ = GetWindowLongPtr(window_, GWL_EXSTYLE);
      previous_placement_.length = sizeof(WINDOWPLACEMENT);
      GetWindowPlacement(window_, &previous_placement_);

      HMONITOR monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info;
      monitor_info.cbSize = sizeof(MONITORINFO);
      GetMonitorInfo(monitor, &monitor_info);

      LONG_PTR style = previous_style_;
      style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
      style |= WS_POPUP | WS_VISIBLE;
      SetWindowLongPtr(window_, GWL_STYLE, style);
      SetWindowLongPtr(window_, GWL_EXSTYLE, previous_ex_style_ | WS_EX_TOPMOST);
      SetWindowPos(
          window_, HWND_TOPMOST,
          monitor_info.rcMonitor.left,
          monitor_info.rcMonitor.top,
          monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
          monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
          SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      ShowWindow(window_, SW_SHOWMAXIMIZED);
      SetForegroundWindow(window_);
      active_ = true;
    }

    response[flutter::EncodableValue("active")] = flutter::EncodableValue(active_);
    response[flutter::EncodableValue("message")] = flutter::EncodableValue(std::string("Exam window mode is active."));
    return response;
  }

  flutter::EncodableMap Exit() {
    flutter::EncodableMap response;
    response[flutter::EncodableValue("supported")] = flutter::EncodableValue(window_ != nullptr);
    if (window_ != nullptr && active_) {
      SetWindowLongPtr(window_, GWL_STYLE, previous_style_);
      SetWindowLongPtr(window_, GWL_EXSTYLE, previous_ex_style_);
      SetWindowPlacement(window_, &previous_placement_);
      SetWindowPos(window_, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      active_ = false;
    }
    response[flutter::EncodableValue("active")] = flutter::EncodableValue(active_);
    response[flutter::EncodableValue("message")] = flutter::EncodableValue(std::string("Exam window mode is inactive."));
    return response;
  }

  flutter::EncodableMap Status() const {
    flutter::EncodableMap response;
    response[flutter::EncodableValue("supported")] = flutter::EncodableValue(window_ != nullptr);
    response[flutter::EncodableValue("active")] = flutter::EncodableValue(active_);
    response[flutter::EncodableValue("message")] = flutter::EncodableValue(active_ ? std::string("Exam window mode is active.") : std::string("Exam window mode is inactive."));
    return response;
  }

  bool active() const { return active_; }

 private:
  HWND window_ = nullptr;
  bool active_ = false;
  LONG_PTR previous_style_ = 0;
  LONG_PTR previous_ex_style_ = 0;
  WINDOWPLACEMENT previous_placement_{};
};

ExamWindowController& Controller() {
  static ExamWindowController controller;
  return controller;
}

}  // namespace

void RegisterExamWindowChannel(flutter::BinaryMessenger* messenger, HWND window) {
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  Controller().Attach(window);
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("enter") == 0) {
          result->Success(flutter::EncodableValue(Controller().Enter()));
          return;
        }
        if (call.method_name().compare("exit") == 0) {
          result->Success(flutter::EncodableValue(Controller().Exit()));
          return;
        }
        if (call.method_name().compare("status") == 0) {
          result->Success(flutter::EncodableValue(Controller().Status()));
          return;
        }
        result->NotImplemented();
      });
}

bool ExamWindowHandleMessage(UINT message, WPARAM wparam) {
  (void)message;
  (void)wparam;
  return false;
}

bool ExamWindowIsActive() {
  return Controller().active();
}
