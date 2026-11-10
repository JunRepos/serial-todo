#ifndef RUNNER_DESK_APP_H_
#define RUNNER_DESK_APP_H_

#include <windows.h>

#include <memory>
#include <string>

#include "desk_window.h"

// 바탕화면 위젯 두 개(캘린더·할 일)와 트레이 아이콘을 관리한다.
// 캘린더 창의 Flutter 엔진이 로그인·동기화를 맡고, 할 일 창은
// "serialtodo/relay" 채널로 데이터를 받아 그린다(두 엔진 사이를 여기서 이어 준다).
class DeskApp {
 public:
  explicit DeskApp(const std::wstring& data_dir);
  ~DeskApp();

  // 이미 실행 중이면 그쪽 창을 보이게 하고 false.
  static bool AcquireSingleInstance();

  bool Start();
  void Shutdown();

  bool locked() const { return locked_; }
  void Relay(DeskWindow* from, const uint8_t* message, size_t size);
  void ShowWindowById(const std::string& id);
  void SaveState();
  void OnWindowLost(DeskWindow* window);

 private:
  static LRESULT CALLBACK MessageProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) noexcept;
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  bool CreateDesk(int index);
  RECT DefaultBounds(int index) const;
  void AddTrayIcon();
  void ShowTrayMenu();
  void SetLocked(bool locked);
  bool AutoStartEnabled() const;
  void SetAutoStart(bool enabled);
  void LoadState();

  std::wstring data_dir_;
  std::wstring ini_path_;
  HWND msg_hwnd_ = nullptr;
  UINT taskbar_created_ = 0;
  bool locked_ = false;
  bool quitting_ = false;
  bool visible_[2] = {true, true};
  RECT bounds_[2] = {};
  bool has_bounds_[2] = {false, false};
  std::unique_ptr<DeskWindow> windows_[2];
};

#endif  // RUNNER_DESK_APP_H_
