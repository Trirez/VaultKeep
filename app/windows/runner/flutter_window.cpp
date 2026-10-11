#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <shellapi.h>
#include <userconsentverifierinterop.h>
#include <wincred.h>
#include <windows.h>
#include <windows.security.credentials.ui.h>
#include <wincrypt.h>
#include <winstring.h>
#include <wrl/client.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

namespace {
using WebAuthNGetApiVersionNumberFn = DWORD(WINAPI*)();
using WebAuthNIsUserVerifyingPlatformAuthenticatorAvailableFn =
    HRESULT(WINAPI*)(BOOL*);

constexpr UINT kTrayIconMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1001;
constexpr UINT kMenuRestoreId = 2001;
constexpr UINT kMenuLockId = 2002;
constexpr UINT kMenuExitId = 2003;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), count);
  return wide;
}

bool VerifyWithWindowsHelloOrCredUI(HWND hwnd, const std::wstring& message) {
  // 1. Attempt native Windows Hello verification tied to |hwnd| via COM ABI.
  HSTRING class_id = nullptr;
  const wchar_t* kClassName =
      RuntimeClass_Windows_Security_Credentials_UI_UserConsentVerifier;
  HRESULT hr = WindowsCreateString(
      kClassName, static_cast<UINT32>(wcslen(kClassName)), &class_id);
  if (SUCCEEDED(hr) && class_id != nullptr) {
    Microsoft::WRL::ComPtr<IUserConsentVerifierInterop> interop;
    hr = RoGetActivationFactory(class_id, IID_PPV_ARGS(&interop));
    WindowsDeleteString(class_id);
    if (SUCCEEDED(hr) && interop != nullptr) {
      HSTRING msg_hstr = nullptr;
      hr = WindowsCreateString(
          message.c_str(), static_cast<UINT32>(message.size()), &msg_hstr);
      if (SUCCEEDED(hr) && msg_hstr != nullptr) {
        using VerifyResult =
            ABI::Windows::Security::Credentials::UI::UserConsentVerificationResult;
        using IAsyncVerifyOp =
            ABI::Windows::Foundation::IAsyncOperation<VerifyResult>;
        Microsoft::WRL::ComPtr<IAsyncVerifyOp> async_op;
        hr = interop->RequestVerificationForWindowAsync(
            hwnd, msg_hstr, IID_PPV_ARGS(&async_op));
        WindowsDeleteString(msg_hstr);
        if (SUCCEEDED(hr) && async_op != nullptr) {
          Microsoft::WRL::ComPtr<IAsyncInfo> async_info;
          if (SUCCEEDED(async_op.As(&async_info)) && async_info != nullptr) {
            AsyncStatus status = AsyncStatus::Started;
            // Pump pending window messages while waiting for the Windows Hello dialog.
            for (int i = 0; i < 1200; ++i) {
              if (FAILED(async_info->get_Status(&status)) ||
                  status != AsyncStatus::Started) {
                break;
              }
              MSG msg;
              while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
              }
              Sleep(50);
            }
            if (status == AsyncStatus::Completed) {
              VerifyResult verify_result = VerifyResult::
                  UserConsentVerificationResult_Canceled;
              if (SUCCEEDED(async_op->GetResults(&verify_result))) {
                if (verify_result ==
                    VerifyResult::UserConsentVerificationResult_Verified) {
                  return true;
                }
                if (verify_result ==
                        VerifyResult::UserConsentVerificationResult_Canceled ||
                    verify_result ==
                        VerifyResult::
                            UserConsentVerificationResult_RetriesExhausted) {
                  return false;
                }
              }
            }
          }
        }
      }
    }
  }

  // 2. Fallback to Windows Security Credential UI prompt if Windows Hello
  // device/PIN is not configured.
  CREDUI_INFOW credui = {};
  credui.cbSize = sizeof(credui);
  credui.hwndParent = hwnd;
  credui.pszMessageText = message.c_str();
  credui.pszCaptionText = L"VaultKeep — Windows Security";

  ULONG auth_package = 0;
  LPVOID out_auth_buffer = nullptr;
  ULONG out_auth_size = 0;
  BOOL save = FALSE;

  DWORD err = CredUIPromptForWindowsCredentialsW(
      &credui, 0, &auth_package, nullptr, 0, &out_auth_buffer, &out_auth_size,
      &save, CREDUIWIN_GENERIC);
  if (out_auth_buffer != nullptr) {
    SecureZeroMemory(out_auth_buffer, out_auth_size);
    CoTaskMemFree(out_auth_buffer);
  }
  return err == ERROR_SUCCESS;
}

std::string ProtectWithDpapi(const std::string& secret) {
  if (secret.empty()) return std::string();
  DATA_BLOB in_blob = {};
  in_blob.cbData = static_cast<DWORD>(secret.size());
  in_blob.pbData =
      reinterpret_cast<BYTE*>(const_cast<char*>(secret.data()));

  DATA_BLOB out_blob = {};
  if (!CryptProtectData(&in_blob, L"VaultKeepQuickUnlock", nullptr, nullptr,
                        nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out_blob)) {
    return std::string();
  }

  DWORD b64_len = 0;
  std::string result;
  if (CryptBinaryToStringA(
          out_blob.pbData, out_blob.cbData,
          CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &b64_len) &&
      b64_len > 0) {
    result.resize(b64_len);
    if (CryptBinaryToStringA(out_blob.pbData, out_blob.cbData,
                             CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                             result.data(), &b64_len)) {
      while (!result.empty() &&
             (result.back() == '\0' || result.back() == '\r' ||
              result.back() == '\n')) {
        result.pop_back();
      }
    } else {
      result.clear();
    }
  }
  LocalFree(out_blob.pbData);
  return result;
}

std::string UnprotectWithDpapi(const std::string& b64) {
  if (b64.empty()) return std::string();
  DWORD bin_len = 0;
  if (!CryptStringToBinaryA(b64.c_str(), static_cast<DWORD>(b64.size()),
                            CRYPT_STRING_BASE64, nullptr, &bin_len, nullptr,
                            nullptr) ||
      bin_len == 0) {
    return std::string();
  }
  std::vector<BYTE> cipher(bin_len);
  if (!CryptStringToBinaryA(b64.c_str(), static_cast<DWORD>(b64.size()),
                            CRYPT_STRING_BASE64, cipher.data(), &bin_len,
                            nullptr, nullptr)) {
    return std::string();
  }

  DATA_BLOB in_blob = {};
  in_blob.cbData = bin_len;
  in_blob.pbData = cipher.data();

  DATA_BLOB out_blob = {};
  if (!CryptUnprotectData(&in_blob, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &out_blob)) {
    return std::string();
  }

  std::string plaintext(reinterpret_cast<const char*>(out_blob.pbData),
                        out_blob.cbData);
  SecureZeroMemory(out_blob.pbData, out_blob.cbData);
  LocalFree(out_blob.pbData);
  return plaintext;
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
  RegisterPasskeyChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    const wchar_t* cmd_line = GetCommandLineW();
    if (cmd_line != nullptr && wcsstr(cmd_line, L"--minimized") != nullptr) {
      minimize_to_tray_ = true;
      UpdateSystemTrayIcon(true);
      ShowWindow(GetHandle(), SW_HIDE);
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

flutter::EncodableMap FlutterWindow::ReadSystemThemeInfo() {
  bool is_light = false;
  HKEY hkey = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
          0, KEY_READ, &hkey) == ERROR_SUCCESS) {
    DWORD val = 0;
    DWORD size = sizeof(val);
    if (RegQueryValueExW(hkey, L"AppsUseLightTheme", nullptr, nullptr,
                         reinterpret_cast<LPBYTE>(&val),
                         &size) == ERROR_SUCCESS) {
      is_light = (val != 0);
    }
    RegCloseKey(hkey);
  }

  int64_t argb_accent = 0;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\DWM", 0,
                    KEY_READ, &hkey) == ERROR_SUCCESS) {
    DWORD abgr = 0;
    DWORD size = sizeof(abgr);
    if (RegQueryValueExW(hkey, L"AccentColor", nullptr, nullptr,
                         reinterpret_cast<LPBYTE>(&abgr),
                         &size) == ERROR_SUCCESS &&
        abgr != 0) {
      // DWM AccentColor is stored as 0xAABBGGRR; convert to ARGB 0xFFRRGGBB.
      uint8_t r = static_cast<uint8_t>(abgr & 0xFF);
      uint8_t g = static_cast<uint8_t>((abgr >> 8) & 0xFF);
      uint8_t b = static_cast<uint8_t>((abgr >> 16) & 0xFF);
      argb_accent = (static_cast<int64_t>(0xFF) << 24) |
                    (static_cast<int64_t>(r) << 16) |
                    (static_cast<int64_t>(g) << 8) | static_cast<int64_t>(b);
    } else if (RegQueryValueExW(hkey, L"ColorizationColor", nullptr, nullptr,
                                reinterpret_cast<LPBYTE>(&abgr),
                                &size) == ERROR_SUCCESS &&
               abgr != 0) {
      argb_accent = static_cast<int64_t>(0xFF000000ULL | (abgr & 0x00FFFFFFULL));
    }
    RegCloseKey(hkey);
  }

  flutter::EncodableMap map;
  map[flutter::EncodableValue("isLight")] = flutter::EncodableValue(is_light);
  if (argb_accent != 0) {
    map[flutter::EncodableValue("accentColor")] =
        flutter::EncodableValue(argb_accent);
  }
  return map;
}

void FlutterWindow::UpdateStartupRegistryKey(bool enable) {
  HKEY hkey = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
          KEY_SET_VALUE, &hkey) != ERROR_SUCCESS) {
    return;
  }

  if (enable) {
    wchar_t exe_path[MAX_PATH] = {0};
    DWORD len = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
      std::wstring cmd = L"\"";
      cmd += exe_path;
      cmd += L"\" --minimized";
      RegSetValueExW(
          hkey, L"VaultKeep", 0, REG_SZ,
          reinterpret_cast<const BYTE*>(cmd.c_str()),
          static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
    }
  } else {
    RegDeleteValueW(hkey, L"VaultKeep");
  }
  RegCloseKey(hkey);
}

void FlutterWindow::UpdateSystemTrayIcon(bool enabled) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  if (enabled && !tray_icon_added_) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayIconId;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = kTrayIconMessage;
    nid.hIcon = LoadIcon(GetModuleHandle(nullptr),
                         MAKEINTRESOURCE(IDI_APP_ICON));
    if (nid.hIcon == nullptr) {
      nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    }
    wcscpy_s(nid.szTip, L"VaultKeep — Zero-Knowledge Password Manager");
    if (Shell_NotifyIconW(NIM_ADD, &nid)) {
      tray_icon_added_ = true;
    }
  } else if (!enabled && tray_icon_added_) {
    RemoveSystemTrayIcon();
  }
}

void FlutterWindow::RemoveSystemTrayIcon() {
  if (!tray_icon_added_) return;
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &nid);
  }
  tray_icon_added_ = false;
}

void FlutterWindow::ShowTrayContextMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;

  AppendMenuW(menu, MF_STRING, kMenuRestoreId, L"Open VaultKeep");
  AppendMenuW(menu, MF_STRING, kMenuLockId, L"Lock Vault");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExitId, L"Exit VaultKeep");

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd);
  UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0,
                            hwnd, nullptr);
  DestroyMenu(menu);

  if (cmd == kMenuRestoreId) {
    ShowWindow(hwnd, SW_SHOW);
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  } else if (cmd == kMenuLockId) {
    if (passkey_channel_) {
      passkey_channel_->InvokeMethod(
          "onTrayLockRequested",
          std::make_unique<flutter::EncodableValue>(true));
    }
  } else if (cmd == kMenuExitId) {
    force_closing_ = true;
    RemoveSystemTrayIcon();
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::RegisterPasskeyChannel() {
  passkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.vaultkeep/passkey_provider",
          &flutter::StandardMethodCodec::GetInstance());

  passkey_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
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
          map[flutter::EncodableValue("conditionalGetSupported")] =
              flutter::EncodableValue(api_version >= 4);
          map[flutter::EncodableValue("hybridTransportSupported")] =
              flutter::EncodableValue(api_version >= 6);
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

        if (call.method_name() == "getSystemThemeInfo") {
          result->Success(flutter::EncodableValue(ReadSystemThemeInfo()));
          return;
        }

        if (call.method_name() == "setStartupAndTrayConfig") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto it_startup =
                args->find(flutter::EncodableValue("openAtStartup"));
            if (it_startup != args->end()) {
              if (const bool* v = std::get_if<bool>(&it_startup->second)) {
                UpdateStartupRegistryKey(*v);
              }
            }
            auto it_tray =
                args->find(flutter::EncodableValue("minimizeToTray"));
            if (it_tray != args->end()) {
              if (const bool* v = std::get_if<bool>(&it_tray->second)) {
                minimize_to_tray_ = *v;
              }
            }
            auto it_hide =
                args->find(flutter::EncodableValue("hideDockIcon"));
            if (it_hide != args->end()) {
              if (const bool* v = std::get_if<bool>(&it_hide->second)) {
                hide_dock_icon_ = *v;
              }
            }
            auto it_light = args->find(flutter::EncodableValue("isLight"));
            if (it_light != args->end()) {
              if (const bool* v = std::get_if<bool>(&it_light->second)) {
                BOOL use_dark = (*v) ? FALSE : TRUE;
                HWND hwnd = GetHandle();
                if (hwnd != nullptr) {
                  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                                        &use_dark, sizeof(use_dark));
                }
              }
            }
            UpdateSystemTrayIcon(minimize_to_tray_ || hide_dock_icon_);
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "authenticateWindowsHello") {
          std::wstring message =
              L"Verify your identity with Windows Hello to unlock VaultKeep.";
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto it_msg = args->find(flutter::EncodableValue("message"));
            if (it_msg != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_msg->second)) {
                if (!s->empty()) {
                  message = Utf8ToWide(*s);
                }
              }
            }
          }
          bool verified = VerifyWithWindowsHelloOrCredUI(GetHandle(), message);
          result->Success(flutter::EncodableValue(verified));
          return;
        }

        if (call.method_name() == "protectSecretDpapi") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto it_sec = args->find(flutter::EncodableValue("secret"));
            if (it_sec != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_sec->second)) {
                std::string protected_b64 = ProtectWithDpapi(*s);
                if (!protected_b64.empty()) {
                  result->Success(flutter::EncodableValue(protected_b64));
                  return;
                }
              }
            }
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "unprotectSecretDpapi") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto it_blob = args->find(flutter::EncodableValue("blob"));
            if (it_blob != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_blob->second)) {
                std::string plain = UnprotectWithDpapi(*s);
                if (!plain.empty()) {
                  result->Success(flutter::EncodableValue(plain));
                  SecureZeroMemory(plain.data(), plain.size());
                  return;
                }
              }
            }
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  RemoveSystemTrayIcon();
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
  if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_MINIMIZE &&
      minimize_to_tray_) {
    UpdateSystemTrayIcon(true);
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (message == WM_CLOSE && !force_closing_ &&
      (minimize_to_tray_ || hide_dock_icon_)) {
    UpdateSystemTrayIcon(true);
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (message == kTrayIconMessage) {
    UINT mouse_msg = LOWORD(lparam);
    if (mouse_msg == WM_LBUTTONUP || mouse_msg == WM_LBUTTONDBLCLK) {
      ShowWindow(hwnd, SW_SHOW);
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
      return 0;
    }
    if (mouse_msg == WM_RBUTTONUP || mouse_msg == WM_CONTEXTMENU) {
      ShowTrayContextMenu();
      return 0;
    }
  }

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
    case WM_SETTINGCHANGE:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      if (passkey_channel_) {
        passkey_channel_->InvokeMethod(
            "onSystemThemeChanged",
            std::make_unique<flutter::EncodableValue>(ReadSystemThemeInfo()));
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

