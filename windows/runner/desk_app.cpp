#include "desk_app.h"

#include <flutter/dart_project.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "resource.h"

namespace {

constexpr wchar_t kMsgClass[] = L"SERIAL_TODO_DESK_HOST";
constexpr wchar_t kMutexName[] = L"Local\\SerialTodoDesk";
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"SerialTodoDesk";
constexpr char kRelayChannel[] = "serialtodo/relay";

constexpr UINT WM_TRAY = WM_APP + 1;
constexpr UINT WM_SHOW_ALL = WM_APP + 2;
constexpr UINT_PTR kRecreateTimer = 1;

enum MenuId : UINT {
  kMenuCalendar = 1,
  kMenuTodo,
  kMenuLock,
  kMenuAutoStart,
  kMenuWeb,
  kMenuQuit,
};

const char* const kIds[2] = {"calendar", "todo"};
const wchar_t* const kSections[2] = {L"calendar", L"todo"};

int ReadInt(const std::wstring& ini, const wchar_t* section,
            const wchar_t* key, int fallback) {
  return static_cast<int>(
      GetPrivateProfileIntW(section, key, fallback, ini.c_str()));
}

void WriteInt(const std::wstring& ini, const wchar_t* section,
              const wchar_t* key, int value) {
  WritePrivateProfileStringW(section, key, std::to_wstring(value).c_str(),
                             ini.c_str());
}

}  // namespace

DeskApp::DeskApp(const std::wstring& data_dir) : data_dir_(data_dir) {
  CreateDirectoryW(data_dir_.c_str(), nullptr);
  ini_path_ = data_dir_ + L"\\desk.ini";
}

DeskApp::~DeskApp() { Shutdown(); }

bool DeskApp::AcquireSingleInstance() {
  CreateMutexW(nullptr, TRUE, kMutexName);
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND other = FindWindowExW(HWND_MESSAGE, nullptr, kMsgClass, nullptr);
    if (other) PostMessageW(other, WM_SHOW_ALL, 0, 0);
    return false;
  }
  return true;
}

bool DeskApp::Start() {
  WNDCLASSW wc{};
  wc.lpfnWndProc = DeskApp::MessageProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kMsgClass;
  RegisterClassW(&wc);
  msg_hwnd_ = CreateWindowExW(0, kMsgClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                              nullptr, GetModuleHandle(nullptr), this);
  if (!msg_hwnd_) return false;
  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");

  LoadState();
  AddTrayIcon();
  // 캘린더(로그인·동기화 담당)를 먼저 띄운다.
  if (!CreateDesk(0)) return false;
  CreateDesk(1);
  return true;
}

void DeskApp::Shutdown() {
  if (quitting_) return;
  quitting_ = true;
  SaveState();
  for (auto& w : windows_) w = nullptr;
  if (msg_hwnd_) {
    NOTIFYICONDATAW nid{sizeof(nid)};
    nid.hWnd = msg_hwnd_;
    nid.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &nid);
    DestroyWindow(msg_hwnd_);
    msg_hwnd_ = nullptr;
  }
}

bool DeskApp::CreateDesk(int index) {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(
      {std::string("--desk=") + kIds[index]});
  auto window = std::make_unique<DeskWindow>(this, kIds[index]);
  RECT r = has_bounds_[index] ? bounds_[index] : DefaultBounds(index);
  if (!window->Create(project, r, visible_[index])) return false;
  windows_[index] = std::move(window);
  windows_[index]->NotifyLocked(locked_);
  return true;
}

RECT DeskApp::DefaultBounds(int index) const {
  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  HMONITOR mon = MonitorFromPoint({work.left, work.top}, MONITOR_DEFAULTTOPRIMARY);
  const double s = FlutterDesktopGetDpiForMonitor(mon) / 96.0;
  const int margin = static_cast<int>(24 * s);
  const int cal_w = static_cast<int>(520 * s), cal_h = static_cast<int>(460 * s);
  const int todo_w = static_cast<int>(340 * s), todo_h = cal_h;
  const int cal_x = work.right - margin - cal_w;
  const int top = work.top + margin;
  if (index == 0) return {cal_x, top, cal_x + cal_w, top + cal_h};
  const int x = cal_x - margin - todo_w;
  return {x, top, x + todo_w, top + todo_h};
}

void DeskApp::LoadState() {
  locked_ = ReadInt(ini_path_, L"desk", L"locked", 0) != 0;
  for (int i = 0; i < 2; i++) {
    visible_[i] = ReadInt(ini_path_, kSections[i], L"visible", 1) != 0;
    const int w = ReadInt(ini_path_, kSections[i], L"w", 0);
    const int h = ReadInt(ini_path_, kSections[i], L"h", 0);
    if (w > 0 && h > 0) {
      const int x = ReadInt(ini_path_, kSections[i], L"x", 0);
      const int y = ReadInt(ini_path_, kSections[i], L"y", 0);
      RECT r{x, y, x + w, y + h};
      // 모니터 구성이 바뀌어 화면 밖이면 기본 위치로
      if (MonitorFromRect(&r, MONITOR_DEFAULTTONULL)) {
        bounds_[i] = r;
        has_bounds_[i] = true;
      }
    }
  }
}

void DeskApp::SaveState() {
  if (ini_path_.empty()) return;
  WriteInt(ini_path_, L"desk", L"locked", locked_ ? 1 : 0);
  for (int i = 0; i < 2; i++) {
    auto& w = windows_[i];
    if (!w || !w->hwnd()) continue;
    RECT r;
    GetWindowRect(w->hwnd(), &r);
    bounds_[i] = r;
    has_bounds_[i] = true;
    visible_[i] = w->IsVisible();
    WriteInt(ini_path_, kSections[i], L"x", r.left);
    WriteInt(ini_path_, kSections[i], L"y", r.top);
    WriteInt(ini_path_, kSections[i], L"w", r.right - r.left);
    WriteInt(ini_path_, kSections[i], L"h", r.bottom - r.top);
    WriteInt(ini_path_, kSections[i], L"visible", visible_[i] ? 1 : 0);
  }
}

void DeskApp::Relay(DeskWindow* from, const uint8_t* message, size_t size) {
  for (auto& w : windows_) {
    if (!w || w.get() == from || !w->controller()) continue;
    w->controller()->engine()->messenger()->Send(kRelayChannel, message, size);
  }
}

void DeskApp::ShowWindowById(const std::string& id) {
  for (int i = 0; i < 2; i++) {
    if (id == kIds[i] && windows_[i]) {
      windows_[i]->SetVisible(true);
      visible_[i] = true;
    }
  }
  SaveState();
}

void DeskApp::OnWindowLost(DeskWindow* window) {
  if (quitting_) return;
  // 탐색기 재시작 등으로 창이 사라졌다. 바탕화면이 다시 생긴 뒤 새로 만든다.
  SetTimer(msg_hwnd_, kRecreateTimer, 1500, nullptr);
  (void)window;
}

void DeskApp::AddTrayIcon() {
  NOTIFYICONDATAW nid{sizeof(nid)};
  nid.hWnd = msg_hwnd_;
  nid.uID = 1;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = WM_TRAY;
  nid.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  wcscpy_s(nid.szTip, L"할일이많아");
  Shell_NotifyIconW(NIM_ADD, &nid);
}

void DeskApp::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  auto check = [](bool on) { return MF_STRING | (on ? MF_CHECKED : 0); };
  const bool cal = windows_[0] && windows_[0]->IsVisible();
  const bool todo = windows_[1] && windows_[1]->IsVisible();
  AppendMenuW(menu, check(cal), kMenuCalendar, L"캘린더 보이기");
  AppendMenuW(menu, check(todo), kMenuTodo, L"할 일 목록 보이기");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, check(locked_), kMenuLock, L"위치 고정");
  AppendMenuW(menu, check(AutoStartEnabled()), kMenuAutoStart,
              L"Windows 시작 시 실행");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuWeb, L"웹에서 열기");
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"종료");

  POINT p;
  GetCursorPos(&p);
  SetForegroundWindow(msg_hwnd_);
  const UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON |
                                            TPM_BOTTOMALIGN,
                                  p.x, p.y, 0, msg_hwnd_, nullptr);
  DestroyMenu(menu);

  switch (cmd) {
    case kMenuCalendar:
    case kMenuTodo: {
      const int i = cmd == kMenuCalendar ? 0 : 1;
      if (windows_[i]) windows_[i]->SetVisible(!windows_[i]->IsVisible());
      SaveState();
      break;
    }
    case kMenuLock:
      SetLocked(!locked_);
      break;
    case kMenuAutoStart:
      SetAutoStart(!AutoStartEnabled());
      break;
    case kMenuWeb:
      ShellExecuteW(nullptr, L"open",
                    L"https://junrepos.github.io/serial-todo/", nullptr,
                    nullptr, SW_SHOWNORMAL);
      break;
    case kMenuQuit:
      Shutdown();
      PostQuitMessage(0);
      break;
  }
}

void DeskApp::SetLocked(bool locked) {
  locked_ = locked;
  for (auto& w : windows_) {
    if (w) w->NotifyLocked(locked);
  }
  SaveState();
}

bool DeskApp::AutoStartEnabled() const {
  wchar_t buf[MAX_PATH * 2];
  DWORD size = sizeof(buf);
  return RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                      nullptr, buf, &size) == ERROR_SUCCESS;
}

void DeskApp::SetAutoStart(bool enabled) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return;
  }
  if (enabled) {
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const std::wstring cmd = L"\"" + std::wstring(exe) + L"\"";
    RegSetValueExW(key, kRunValue, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(cmd.c_str()),
                   static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteValueW(key, kRunValue);
  }
  RegCloseKey(key);
}

LRESULT CALLBACK DeskApp::MessageProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    static_cast<DeskApp*>(cs->lpCreateParams)->msg_hwnd_ = hwnd;
  } else if (auto* that = reinterpret_cast<DeskApp*>(
                 GetWindowLongPtr(hwnd, GWLP_USERDATA))) {
    return that->HandleMessage(message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT DeskApp::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    AddTrayIcon();
    return 0;
  }
  switch (message) {
    case WM_TRAY:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
        case WM_LBUTTONDBLCLK:
          ShowWindowById("calendar");
          ShowWindowById("todo");
          break;
      }
      return 0;
    case WM_SHOW_ALL:
      ShowWindowById("calendar");
      ShowWindowById("todo");
      return 0;
    case WM_TIMER:
      if (wparam == kRecreateTimer) {
        if (!FindWindowW(L"Progman", nullptr)) return 0;  // 아직 준비 안 됨
        KillTimer(msg_hwnd_, kRecreateTimer);
        for (int i = 0; i < 2; i++) {
          if (!windows_[i] || !windows_[i]->hwnd()) {
            windows_[i] = nullptr;
            CreateDesk(i);
          }
        }
      }
      return 0;
  }
  return DefWindowProc(msg_hwnd_, message, wparam, lparam);
}
