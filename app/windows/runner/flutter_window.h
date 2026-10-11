#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that hosts a Flutter view and manages Windows system integration.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterPasskeyChannel();
  void UpdateSystemTrayIcon(bool enabled);
  void RemoveSystemTrayIcon();
  void ShowTrayContextMenu();
  void UpdateStartupRegistryKey(bool enable);
  flutter::EncodableMap ReadSystemThemeInfo();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native Windows WebAuthn, Windows Hello, DPAPI, Theme & Tray channel.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> passkey_channel_;

  bool minimize_to_tray_ = false;
  bool hide_dock_icon_ = false;
  bool tray_icon_added_ = false;
  bool force_closing_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_


