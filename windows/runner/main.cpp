#include <flutter/dart_project.h>
#include <shlobj.h>
#include <windows.h>

#include <string>

#include "desk_app.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  if (!DeskApp::AcquireSingleInstance()) return EXIT_SUCCESS;

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 창 위치·설정 저장 폴더: %APPDATA%\SerialTodo
  std::wstring data_dir = L".";
  PWSTR appdata = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                     &appdata))) {
    data_dir = std::wstring(appdata) + L"\\SerialTodo";
    CoTaskMemFree(appdata);
  }

  int code = EXIT_SUCCESS;
  {
    DeskApp app(data_dir);
    if (!app.Start()) {
      code = EXIT_FAILURE;
    } else {
      ::MSG msg;
      while (::GetMessage(&msg, nullptr, 0, 0)) {
        ::TranslateMessage(&msg);
        ::DispatchMessage(&msg);
      }
    }
  }
  ::CoUninitialize();
  return code;
}
