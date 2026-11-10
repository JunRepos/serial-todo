#include "desk_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include "desk_app.h"
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr wchar_t kClassName[] = L"SERIAL_TODO_DESK_WINDOW";
constexpr char kRelayChannel[] = "serialtodo/relay";
constexpr char kDeskChannel[] = "serialtodo/desk";

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

}  // namespace

DeskWindow::DeskWindow(DeskApp* app, std::string id)
    : app_(app), id_(std::move(id)) {}

DeskWindow::~DeskWindow() { Destroy(); }

bool DeskWindow::Create(const flutter::DartProject& project,
                        const RECT& bounds, bool visible) {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc{};
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hIcon = LoadIcon(wc.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    wc.lpfnWndProc = DeskWindow::WndProc;
    RegisterClassW(&wc);
    registered = true;
  }
  want_visible_ = visible;

  // 소유자를 바탕화면 창(Progman)으로 두면 '바탕 화면 보기'에도 숨지 않는다.
  HWND desktop = FindWindowW(L"Progman", nullptr);
  const std::wstring title = id_ == "calendar" ? L"할일이많아 캘린더"
                                               : L"할일이많아 할 일";
  hwnd_ = CreateWindowExW(
      WS_EX_TOOLWINDOW, kClassName, title.c_str(),
      WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN, bounds.left, bounds.top,
      bounds.right - bounds.left, bounds.bottom - bounds.top, desktop, nullptr,
      GetModuleHandle(nullptr), this);
  if (!hwnd_) return false;

  // Windows 11: 둥근 모서리
  DWORD corner = 2;  // DWMWCP_ROUND
  DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                        sizeof(corner));

  RECT client;
  GetClientRect(hwnd_, &client);
  controller_ = std::make_unique<flutter::FlutterViewController>(
      client.right - client.left, client.bottom - client.top, project);
  if (!controller_->engine() || !controller_->view()) return false;
  RegisterPlugins(controller_->engine());

  child_ = controller_->view()->GetNativeWindow();
  SetParent(child_, hwnd_);
  MoveWindow(child_, 0, 0, client.right - client.left,
             client.bottom - client.top, TRUE);

  auto* messenger = controller_->engine()->messenger();
  messenger->SetMessageHandler(
      kRelayChannel, [this](const uint8_t* message, size_t size,
                            flutter::BinaryReply reply) {
        app_->Relay(this, message, size);
        reply(nullptr, 0);
      });

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kDeskChannel, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethod(call, std::move(result));
  });

  controller_->engine()->SetNextFrameCallback([this]() {
    if (want_visible_ && hwnd_) {
      ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
      SetWindowPos(hwnd_, HWND_BOTTOM, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
  });
  controller_->ForceRedraw();
  return true;
}

void DeskWindow::Destroy() {
  if (destroying_) return;
  destroying_ = true;
  channel_ = nullptr;
  controller_ = nullptr;
  if (hwnd_) {
    HWND h = hwnd_;
    hwnd_ = nullptr;
    DestroyWindow(h);
  }
}

void DeskWindow::SetVisible(bool visible) {
  want_visible_ = visible;
  if (!hwnd_) return;
  if (visible) {
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    SetWindowPos(hwnd_, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  } else {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

bool DeskWindow::IsVisible() const {
  return hwnd_ && IsWindowVisible(hwnd_);
}

void DeskWindow::NotifyLocked(bool locked) {
  if (channel_) {
    channel_->InvokeMethod(
        "locked", std::make_unique<flutter::EncodableValue>(locked));
  }
}

void DeskWindow::StartSysCommand(WPARAM command) {
  ReleaseCapture();
  // 이동·크기 조절 모달 루프. 끝날 때까지 돌아오지 않는다.
  SendMessageW(hwnd_, WM_SYSCOMMAND, command, 0);
  // 모달 루프가 마우스 떼기를 먹어 버리므로 Flutter에 알려 준다.
  if (child_) {
    POINT p;
    GetCursorPos(&p);
    ScreenToClient(child_, &p);
    PostMessageW(child_, WM_LBUTTONUP, 0, MAKELPARAM(p.x, p.y));
  }
  app_->SaveState();
}

void DeskWindow::HandleMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& m = call.method_name();
  if (m == "startDrag" || m == "startResize") {
    result->Success();
    if (!app_->locked() && hwnd_) {
      StartSysCommand(m == "startDrag" ? (SC_MOVE | HTCAPTION)
                                       : (SC_SIZE | 8 /* WMSZ_BOTTOMRIGHT */));
    }
  } else if (m == "hide") {
    result->Success();
    SetVisible(false);
    app_->SaveState();
  } else if (m == "show") {
    const auto* target = std::get_if<std::string>(call.arguments());
    result->Success();
    if (target) app_->ShowWindowById(*target);
  } else if (m == "openWeb") {
    result->Success();
    ShellExecuteW(nullptr, L"open", L"https://junrepos.github.io/serial-todo/",
                  nullptr, nullptr, SW_SHOWNORMAL);
  } else if (m == "isLocked") {
    result->Success(flutter::EncodableValue(app_->locked()));
  } else if (m == "activate") {
    // 입력창을 쓰려면 키보드 포커스가 필요하다.
    result->Success();
    if (hwnd_) {
      SetForegroundWindow(hwnd_);
      if (child_) SetFocus(child_);
    }
  } else {
    result->NotImplemented();
  }
}

LRESULT CALLBACK DeskWindow::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    auto* that = static_cast<DeskWindow*>(cs->lpCreateParams);
    that->hwnd_ = hwnd;
    EnableNonClientDpiScaling(hwnd);
  } else if (auto* that = reinterpret_cast<DeskWindow*>(
                 GetWindowLongPtr(hwnd, GWLP_USERDATA))) {
    return that->Handle(message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT DeskWindow::Handle(UINT message, WPARAM wparam,
                           LPARAM lparam) noexcept {
  HWND hwnd = hwnd_;
  if (controller_) {
    auto r = controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                   lparam);
    if (r) return *r;
  }
  switch (message) {
    case WM_NCCALCSIZE:
      // 크기 조절은 되지만 테두리는 그리지 않는다(클라이언트 = 창 전체).
      if (wparam) return 0;
      break;
    case WM_NCACTIVATE:
      // 비활성화될 때 테두리를 다시 그리지 않게
      return TRUE;
    case WM_WINDOWPOSCHANGING: {
      // 언제나 다른 창들 뒤에 머문다.
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      if (!(pos->flags & SWP_NOZORDER)) pos->hwndInsertAfter = HWND_BOTTOM;
      return 0;
    }
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      UINT dpi = hwnd ? GetDpiForWindow(hwnd) : 96;
      info->ptMinTrackSize.x = MulDiv(240, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(220, dpi, 96);
      return 0;
    }
    case WM_DPICHANGED: {
      auto* r = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(hwnd, nullptr, r->left, r->top, r->right - r->left,
                   r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE:
      if (child_) {
        RECT rc;
        GetClientRect(hwnd, &rc);
        MoveWindow(child_, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
      }
      return 0;
    case WM_ACTIVATE:
      if (child_ && LOWORD(wparam) != WA_INACTIVE) SetFocus(child_);
      return 0;
    case WM_EXITSIZEMOVE:
      app_->SaveState();
      break;
    case WM_CLOSE:
      // Alt+F4 등은 숨기기만 한다. 종료는 트레이 메뉴에서.
      SetVisible(false);
      app_->SaveState();
      return 0;
    case WM_FONTCHANGE:
      if (controller_) controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DESTROY:
      if (!destroying_) {
        // 탐색기가 다시 시작되면서 소유자(Progman)와 함께 사라진 경우
        destroying_ = true;
        channel_ = nullptr;
        controller_ = nullptr;
        hwnd_ = nullptr;
        app_->OnWindowLost(this);
      }
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
