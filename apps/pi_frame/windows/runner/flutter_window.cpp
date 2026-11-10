#include "flutter_window.h"
#include "flutter/generated_plugin_registrant.h"

#include <windows.h>
#include <shobjidl.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

namespace {
constexpr UINT_PTR kTaskbarAnimationTimer = 42;
constexpr int kAnswerButton = 201;
constexpr int kOpenButton = 202;
constexpr int kCancelButton = 203;
constexpr int kAnswerEdit = 204;
constexpr int kAnswerCombo = 205;
HMENU ControlId(int id) { return reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)); }
HWND g_question_popup = nullptr;
HWND g_question_edit = nullptr;
HWND g_question_combo = nullptr;
HBRUSH g_question_background = nullptr;
flutter::MethodChannel<flutter::EncodableValue>* g_taskbar_channel = nullptr;
std::string g_question_session;
std::string g_question_request;
std::string g_question_method;
std::wstring g_question_title;
std::wstring g_question_message;
std::vector<std::wstring> g_question_options;
bool g_question_can_answer = false;

std::wstring Utf8ToWide(const std::string& input) {
  if (input.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring output(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, output.data(), length);
  output.resize(length - 1);
  return output;
}

void SendQuestionAction(const wchar_t* method, const wchar_t* value = nullptr) {
  if (!g_taskbar_channel) return;
  flutter::EncodableMap args;
  args[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(g_question_session);
  args[flutter::EncodableValue("requestId")] = flutter::EncodableValue(g_question_request);
  if (wcscmp(method, L"answer") == 0 && g_question_method == "confirm") {
    args[flutter::EncodableValue("confirmed")] = flutter::EncodableValue(true);
  } else if (wcscmp(method, L"cancel") == 0) {
    args[flutter::EncodableValue("cancelled")] = flutter::EncodableValue(true);
  } else if (wcscmp(method, L"answer") == 0 && value != nullptr) {
    const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    std::string utf8(length > 1 ? length : 0, '\0');
    if (length > 1) WideCharToMultiByte(CP_UTF8, 0, value, -1, utf8.data(), length, nullptr, nullptr);
    if (length > 1) utf8.resize(length - 1);
    args[flutter::EncodableValue("value")] = flutter::EncodableValue(utf8);
  }
  g_taskbar_channel->InvokeMethod(method == nullptr ? "" :
      (wcscmp(method, L"open") == 0 ? "openQuestion" : "answerQuestion"),
      std::make_unique<flutter::EncodableValue>(args));
}

LRESULT CALLBACK QuestionPopupProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      CreateWindowW(L"STATIC", g_question_title.c_str(), WS_CHILD | WS_VISIBLE,
                    16, 14, 360, 25, hwnd, nullptr, nullptr, nullptr);
      CreateWindowW(L"STATIC", g_question_message.c_str(), WS_CHILD | WS_VISIBLE | SS_EDITCONTROL,
                    16, 45, 360, 72, hwnd, nullptr, nullptr, nullptr);
      if (g_question_method == "input" || g_question_method == "editor") {
        g_question_edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 16, 126, 360, 27, hwnd,
            ControlId(kAnswerEdit), nullptr, nullptr);
      } else if (g_question_method == "select" && g_question_can_answer) {
        g_question_combo = CreateWindowW(L"COMBOBOX", L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
            16, 126, 360, 150, hwnd, ControlId(kAnswerCombo), nullptr, nullptr);
        for (const auto& option : g_question_options) SendMessageW(g_question_combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(option.c_str()));
        SendMessageW(g_question_combo, CB_SETCURSEL, 0, 0);
      }
      if (g_question_method == "confirm") {
        CreateWindowW(L"BUTTON", L"Conferma", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
            16, 166, 105, 30, hwnd, ControlId(kAnswerButton), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Annulla", WS_CHILD | WS_VISIBLE,
            129, 166, 90, 30, hwnd, ControlId(kCancelButton), nullptr, nullptr);
      } else if (g_question_can_answer) {
        CreateWindowW(L"BUTTON", L"Rispondi", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
            16, 166, 105, 30, hwnd, ControlId(kAnswerButton), nullptr, nullptr);
      }
      CreateWindowW(L"BUTTON", L"Apri PiFrame", WS_CHILD | WS_VISIBLE,
          230, 166, 105, 30, hwnd, ControlId(kOpenButton), nullptr, nullptr);
      return 0;
    }
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wparam);
      SetTextColor(dc, RGB(235, 238, 244));
      SetBkMode(dc, TRANSPARENT);
      return reinterpret_cast<LRESULT>(g_question_background);
    }
    case WM_COMMAND: {
      const int id = LOWORD(wparam);
      if (id == kOpenButton) {
        SendQuestionAction(L"open");
        DestroyWindow(hwnd);
        return 0;
      }
      if (id == kCancelButton) {
        SendQuestionAction(L"cancel");
        DestroyWindow(hwnd);
        return 0;
      }
      if (id == kAnswerButton) {
        if (g_question_method == "select" && g_question_combo) {
          const int selected = static_cast<int>(SendMessageW(g_question_combo, CB_GETCURSEL, 0, 0));
          if (selected >= 0) {
            wchar_t value[512]{};
            SendMessageW(g_question_combo, CB_GETLBTEXT, selected, reinterpret_cast<LPARAM>(value));
            SendQuestionAction(L"answer", value);
          }
        } else if (g_question_method == "confirm") {
          SendQuestionAction(L"answer");
        } else if (g_question_edit) {
          wchar_t value[2048]{};
          GetWindowTextW(g_question_edit, value, 2048);
          SendQuestionAction(L"answer", value);
        }
        DestroyWindow(hwnd);
        return 0;
      }
      break;
    }
    case WM_CLOSE:
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      if (g_question_popup == hwnd) {
        g_question_popup = nullptr;
        g_question_edit = nullptr;
        g_question_combo = nullptr;
      }
      return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void ShowQuestionPopup(const flutter::EncodableList& questions,
                       flutter::MethodChannel<flutter::EncodableValue>* channel,
                       HWND owner) {
  g_taskbar_channel = channel;
  if (questions.empty()) {
    if (g_question_popup) DestroyWindow(g_question_popup);
    return;
  }
  const auto* question = std::get_if<flutter::EncodableMap>(&questions.front());
  if (!question) return;
  auto get_string = [question](const char* key) -> std::string {
    auto it = question->find(flutter::EncodableValue(key));
    if (it == question->end()) return {};
    if (const auto* value = std::get_if<std::string>(&it->second)) return *value;
    return {};
  };
  const auto session = get_string("sessionId");
  const auto request = get_string("requestId");
  if (request.empty()) return;
  if (g_question_popup && request == g_question_request) return;
  if (g_question_popup) DestroyWindow(g_question_popup);
  g_question_session = session;
  g_question_request = request;
  g_question_method = get_string("method");
  const auto title = get_string("title");
  const auto session_name = get_string("sessionName");
  const auto message = get_string("message");
  g_question_title = Utf8ToWide(session_name.empty() ? title : session_name + " - " + title);
  g_question_message = Utf8ToWide(message.empty() ? "L'agente attende una risposta." : message);
  g_question_options.clear();
  bool multi_select = false;
  auto multi_it = question->find(flutter::EncodableValue("multiSelect"));
  if (multi_it != question->end()) {
    if (const auto* value = std::get_if<bool>(&multi_it->second)) multi_select = *value;
  }
  auto options_it = question->find(flutter::EncodableValue("options"));
  if (options_it != question->end()) {
    if (const auto* options = std::get_if<flutter::EncodableList>(&options_it->second)) {
      for (const auto& option : *options) {
        if (const auto* value = std::get_if<std::string>(&option)) g_question_options.push_back(Utf8ToWide(*value));
      }
    }
  }
  g_question_can_answer = g_question_method == "confirm" ||
      g_question_method == "input" || g_question_method == "editor" ||
      (g_question_method == "select" && !multi_select && !g_question_options.empty());
  if (g_question_method == "select" && multi_select) g_question_method = "unsupported";
  static bool registered = false;
  if (!g_question_background) g_question_background = CreateSolidBrush(RGB(35, 39, 47));
  if (!registered) {
    WNDCLASSW wc{};
    wc.lpfnWndProc = QuestionPopupProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"PiFrameQuestionPopup";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = g_question_background;
    RegisterClassW(&wc);
    registered = true;
  }
  g_question_popup = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
      L"PiFrameQuestionPopup", L"PiFrame · Richiesta in attesa",
      WS_POPUP | WS_CAPTION | WS_SYSMENU, 0, 0, 400, 240, owner, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (!g_question_popup) return;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST), &monitor);
  const int x = monitor.rcWork.right - 414;
  const int y = monitor.rcWork.bottom - 254;
  SetWindowPos(g_question_popup, HWND_TOPMOST, x, y, 400, 240, SWP_NOACTIVATE);
  ShowWindow(g_question_popup, SW_SHOWNOACTIVATE);
}

HICON CreateTaskbarBadge(bool working, int notifications, int errors, int animation_frame) {
  constexpr int size = 32;
  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = size;
  bitmap_info.bmiHeader.biHeight = -size;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HDC dc = CreateCompatibleDC(nullptr);
  HBITMAP color = CreateDIBSection(dc, &bitmap_info, DIB_RGB_COLORS,
                                  &pixels, nullptr, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
  if (!dc || !color || !mask || !pixels) {
    if (dc) DeleteDC(dc);
    if (color) DeleteObject(color);
    if (mask) DeleteObject(mask);
    return nullptr;
  }
  auto old = SelectObject(dc, color);
  RECT bounds{0, 0, size, size};
  // GDI does not preserve alpha while drawing. Start with a transparent
  // surface, then mark only the colored pixels opaque before creating the icon.
  std::fill_n(static_cast<DWORD*>(pixels), size * size, 0u);

  if (working && errors == 0) {
    // A 270-degree arc advances in small steps for a slower, smoother spin.
    HPEN spinner = CreatePen(PS_SOLID, 3, RGB(66, 133, 232));
    auto old_pen = SelectObject(dc, spinner);
    constexpr double pi = 3.14159265358979323846;
    constexpr int frame_count = 24;
    constexpr int arc_segments = 18;
    constexpr double step = (2.0 * pi) / frame_count;
    for (int segment = 0; segment < arc_segments; ++segment) {
      const double a = (animation_frame + segment) * step;
      const double b = (animation_frame + segment + 1) * step;
      MoveToEx(dc, 12 + static_cast<int>(9 * std::cos(a)), 20 + static_cast<int>(9 * std::sin(a)), nullptr);
      LineTo(dc, 12 + static_cast<int>(9 * std::cos(b)), 20 + static_cast<int>(9 * std::sin(b)));
    }
    SelectObject(dc, old_pen);
    DeleteObject(spinner);
  }

  // Keep the unread count visible even while the blue working arc is moving.
  if (errors > 0 || notifications > 0) {
    const int count = errors > 0 ? errors : notifications;
    const COLORREF fill = errors > 0 ? RGB(220, 45, 55) : RGB(244, 183, 35);
    HBRUSH badge = CreateSolidBrush(fill);
    HPEN outline = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
    auto old_pen = SelectObject(dc, outline);
    auto old_brush = SelectObject(dc, badge);
    Ellipse(dc, 15, 0, 32, 17);
    SelectObject(dc, old_brush);
    SelectObject(dc, old_pen);
    DeleteObject(badge);
    DeleteObject(outline);

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    HFONT font = CreateFontW(count > 9 ? 9 : 11, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    auto previous_font = SelectObject(dc, font);
    std::wstring label = count > 9 ? L"9+" : std::to_wstring(count);
    RECT text_bounds{15, 0, 32, 16};
    DrawTextW(dc, label.c_str(), -1, &text_bounds,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    SelectObject(dc, previous_font);
    DeleteObject(font);
  }
  auto* bgra = static_cast<DWORD*>(pixels);
  for (int i = 0; i < size * size; ++i) {
    const BYTE blue = static_cast<BYTE>(bgra[i] & 0xff);
    const BYTE green = static_cast<BYTE>((bgra[i] >> 8) & 0xff);
    const BYTE red = static_cast<BYTE>((bgra[i] >> 16) & 0xff);
    bgra[i] = (blue == 0 && green == 0 && red == 0) ? 0u : (bgra[i] | 0xff000000u);
  }
  SelectObject(dc, old);
  DeleteDC(dc);
  ICONINFO info{};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(color);
  DeleteObject(mask);
  return icon;
}

void SetTaskbarStatus(HWND window, bool working, int notifications, int errors, int animation_frame) {
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&taskbar)))) return;
  if (SUCCEEDED(taskbar->HrInit())) {
    HICON icon = (working || notifications > 0 || errors > 0)
                     ? CreateTaskbarBadge(working, notifications, errors, animation_frame)
                     : nullptr;
    taskbar->SetOverlayIcon(window, icon,
                            errors > 0 ? L"PiFrame: errori in sessione"
                                : (notifications > 0 ? L"PiFrame: richieste in attesa"
                                                     : (working ? L"PiFrame: in elaborazione" : L"")));
    if (icon) DestroyIcon(icon);
  }
  taskbar->Release();
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
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  taskbar_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "dev.piframe/taskbar",
      &flutter::StandardMethodCodec::GetInstance());
  taskbar_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setStatus") {
          result->NotImplemented();
          return;
        }
        bool working = false;
        int notifications = 0;
        int errors = 0;
        flutter::EncodableList questions;
        if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto working_it = args->find(flutter::EncodableValue("working"));
          if (working_it != args->end()) {
            if (const auto* value = std::get_if<bool>(&working_it->second)) working = *value;
          }
          const auto notifications_it = args->find(flutter::EncodableValue("notifications"));
          if (notifications_it != args->end()) {
            if (const auto* value = std::get_if<int32_t>(&notifications_it->second)) notifications = *value;
            if (const auto* value = std::get_if<int64_t>(&notifications_it->second)) notifications = static_cast<int>(*value);
          }
          const auto errors_it = args->find(flutter::EncodableValue("errors"));
          if (errors_it != args->end()) {
            if (const auto* value = std::get_if<int32_t>(&errors_it->second)) errors = *value;
            if (const auto* value = std::get_if<int64_t>(&errors_it->second)) errors = static_cast<int>(*value);
          }
          const auto questions_it = args->find(flutter::EncodableValue("questions"));
          if (questions_it != args->end()) {
            if (const auto* value = std::get_if<flutter::EncodableList>(&questions_it->second)) questions = *value;
          }
        }
        taskbar_working_ = working;
        if (working && notifications == 0 && errors == 0) {
          SetTimer(GetHandle(), kTaskbarAnimationTimer, 50, nullptr);
        } else {
          KillTimer(GetHandle(), kTaskbarAnimationTimer);
          taskbar_animation_frame_ = 0;
        }
        SetTaskbarStatus(GetHandle(), working, std::max(0, notifications),
                         std::max(0, errors), taskbar_animation_frame_);
        ShowQuestionPopup(questions, taskbar_channel_.get(), GetHandle());
        result->Success();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  taskbar_channel_.reset();
  if (flutter_controller_) flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kTaskbarAnimationTimer) {
    taskbar_animation_frame_ = (taskbar_animation_frame_ + 1) % 24;
    SetTaskbarStatus(hwnd, taskbar_working_, 0, 0, taskbar_animation_frame_);
    return 0;
  }
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) return *result;
  }
  if (message == WM_FONTCHANGE) flutter_controller_->engine()->ReloadSystemFonts();
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
