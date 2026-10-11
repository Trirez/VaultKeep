#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
using WebAuthNGetApiVersionNumberFn = DWORD(WINAPI*)();
using WebAuthNIsUserVerifyingPlatformAuthenticatorAvailableFn =
    HRESULT(WINAPI*)(BOOL*);
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
  RegisterPasskeyChannel();
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

void FlutterWindow::RegisterPasskeyChannel() {
  passkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.vaultkeep/passkey_provider",
          &flutter::StandardMethodCodec::GetInstance());

  passkey_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "getPlatformCapabilities") {
          DWORD api_version = 0;
          BOOL uvpa_available = FALSE;
          HMODULE webauthn_dll = LoadLibraryW(L"webauthn.dll");
          if (webauthn_dll != nullptr) {
            auto get_ver = reinterpret_cast<WebAuthNGetApiVersionNumberFn>(
                GetProcAddress(webauthn_dll, "WebAuthNGetApiVersionNumber"));
            if (get_ver != nullptr) {
              api_version = get_ver();
            }
            auto is_uvpa = reinterpret_cast<
                WebAuthNIsUserVerifyingPlatformAuthenticatorAvailableFn>(
                GetProcAddress(
                    webauthn_dll,
                    "WebAuthNIsUserVerifyingPlatformAuthenticatorAvailable"));
            if (is_uvpa != nullptr) {
              BOOL available = FALSE;
              if (SUCCEEDED(is_uvpa(&available))) {
                uvpa_available = available;
              }
            }
            FreeLibrary(webauthn_dll);
          }

          flutter::EncodableMap map;
          map[flutter::EncodableValue("platform")] =
              flutter::EncodableValue("windows");
          map[flutter::EncodableValue("webauthnApiVersion")] =
              flutter::EncodableValue(static_cast<int32_t>(api_version));
          map[flutter::EncodableValue("uvSupported")] =
              flutter::EncodableValue(uvpa_available == TRUE);
          // Windows 11 22H2+ (API v4+) supports Conditional UI
          map[flutter::EncodableValue("conditionalGetSupported")] =
              flutter::EncodableValue(api_version >= 4);
          // Windows 11 23H2+ (API v6+) supports OS-wide Cross-Device Auth
          map[flutter::EncodableValue("hybridTransportSupported")] =
              flutter::EncodableValue(api_version >= 6);
          // Windows 11 25H2+ (API v7+) supports Native Third-Party Plugin API
          map[flutter::EncodableValue("pluginApiSupported")] =
              flutter::EncodableValue(api_version >= 7);
          result->Success(flutter::EncodableValue(map));
          return;
        }

        if (call.method_name() == "openPasskeySettings") {
          HINSTANCE inst = ShellExecuteW(
              nullptr, L"open", L"ms-settings:signinoptions", nullptr, nullptr,
              SW_SHOWNORMAL);
          bool launched = reinterpret_cast<INT_PTR>(inst) > 32;
          result->Success(flutter::EncodableValue(launched));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  passkey_channel_ = nullptr;
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
