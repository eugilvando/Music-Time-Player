#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cwchar>
#include <cstdlib>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // A maintenance restart waits for the previous process before opening its DB.
  const wchar_t* restart_arg = wcsstr(command_line, L"--restart-after=");
  if (restart_arg) {
    const DWORD previous_pid = static_cast<DWORD>(wcstoul(restart_arg + 16, nullptr, 10));
    if (previous_pid == 0 || previous_pid == GetCurrentProcessId()) return EXIT_FAILURE;
    HANDLE previous_process = OpenProcess(SYNCHRONIZE, FALSE, previous_pid);
    if (previous_process) {
      const DWORD result = WaitForSingleObject(previous_process, 30000);
      CloseHandle(previous_process);
      if (result != WAIT_OBJECT_0) return EXIT_FAILURE;
    }
  }
  // A second launch restores the existing player instead of opening another DB writer.
  const bool validation = wcsstr(command_line, L"--validation-profile") != nullptr;
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, validation ? L"Local\\MusicTime.Validation" : L"Local\\MusicTime.Desktop");
  if (!instance_mutex) return EXIT_FAILURE;
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Music Time");
    if (existing) {
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(validation ? L"Music Time (Validacao)" : L"Music Time", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
