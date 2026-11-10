#ifndef RUNNER_DESK_WINDOW_H_
#define RUNNER_DESK_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

class DeskApp;

// 바탕화면에 붙어 있는 위젯 창 하나(캘린더 또는 할 일).
// - 테두리·작업 표시줄 버튼 없는 팝업 창
// - 소유자를 바탕화면(Progman)으로 두어 Win+D(바탕 화면 보기)에도 남는다
// - 항상 다른 창들 뒤(바탕화면 바로 위)에 머문다
class DeskWindow {
 public:
  DeskWindow(DeskApp* app, std::string id);
  ~DeskWindow();

  bool Create(const flutter::DartProject& project, const RECT& bounds,
              bool visible);
  void Destroy();

  HWND hwnd() const { return hwnd_; }
  const std::string& id() const { return id_; }
  flutter::FlutterViewController* controller() { return controller_.get(); }

  void SetVisible(bool visible);
  bool IsVisible() const;
  void NotifyLocked(bool locked);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam) noexcept;
  void HandleMethod(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartSysCommand(WPARAM command);

  DeskApp* app_;
  std::string id_;
  HWND hwnd_ = nullptr;
  HWND child_ = nullptr;
  bool want_visible_ = true;
  bool destroying_ = false;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESK_WINDOW_H_
