#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // Fenetre SANS les trois boutons systeme — demande du Product Owner,
  // 24/08/2026 : « enlever les trois boutons (fermer, reduire, agrandir) pour
  // eviter de fermer l'appli involontairement, surtout quand des paniers sont
  // ouverts ».
  //
  // Le risque est reel et il est metier : un panier ouvert n'est PAS envoye au
  // serveur — `paniers` n'est pas au registre `TABLES_SYNCHRONISABLES`. La
  // saisie du comptoir n'existe donc nulle part ailleurs que sur ce poste, et
  // un clic de trop sur la croix pendant le service perd une addition en
  // cours. Ce n'est pas une preference d'affichage, c'est la protection de la
  // seule copie d'une donnee.
  //
  // `WS_SYSMENU` porte les TROIS a la fois : le retirer supprime la croix, et
  // `WS_MINIMIZEBOX`/`WS_MAXIMIZEBOX` les deux autres. On conserve
  // `WS_CAPTION` (la barre de titre, qui reste saisissable pour deplacer la
  // fenetre) et `WS_THICKFRAME` (le redimensionnement, borne par
  // `WM_GETMINMAXINFO` ci-dessous).
  //
  // ## Ce que ce retrait emporte, et qu'il faut savoir
  //
  // Sans `WS_SYSMENU`, `DefWindowProc` cesse aussi de repondre a **Alt+F4** :
  // la fenetre deviendrait impossible a fermer autrement que par le
  // Gestionnaire des taches. Une application qu'on ne peut plus quitter n'est
  // pas plus sure, elle est cassee. La sortie deliberee est donc retablie a la
  // main dans `MessageHandler` — voir `WM_SYSKEYDOWN`.
  const DWORD style =
      WS_OVERLAPPEDWINDOW & ~(WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);

  HWND window = CreateWindow(
      window_class, title.c_str(), style,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  // Ouverture PLEIN ECRAN — demande du Product Owner, 24/08/2026.
  //
  // L'usage vise est le comptoir du Gite, sur un portable : l'ecran y est
  // entierement dedie a l'application, et ouvrir dans une fenetre de 1280x720
  // au milieu du bureau oblige a l'agrandir a chaque service. Le bouton
  // « agrandir » ayant ete retire pour proteger les paniers ouverts, la
  // fenetre ne s'agrandirait d'ailleurs plus d'un clic.
  //
  // `SW_MAXIMIZE` et non un plein ecran sans bordure : la barre des taches
  // reste accessible, et la barre de titre reste saisissable pour deplacer la
  // fenetre sur un second ecran. `WS_MAXIMIZEBOX` a beau etre absent du style,
  // il ne conditionne que le BOUTON — l'agrandissement par programme reste
  // possible, et c'est bien ce qu'on veut ici.
  return ShowWindow(window_handle_, SW_MAXIMIZE);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    // Taille minimale de la fenetre.
    //
    // Sans cette contrainte, la fenetre se reduit jusqu'a une largeur ou les
    // ecrans a trois colonnes du point de vente — sejours, catalogue, panier —
    // se chevauchent et deviennent inutilisables. L'usage vise est le comptoir :
    // l'ecran y est fixe, mais rien n'empeche un utilisateur de reduire la
    // fenetre par megarde, et de croire ensuite que l'application est cassee.
    //
    // 1024 x 640 correspond au palier `lg` du design system, celui a partir
    // duquel les grilles passent en plusieurs colonnes.
    //
    // ## La fenetre tient dans la ZONE DE TRAVAIL (demande du PO, 14/10/2026)
    //
    // Toasts et derniers boutons passaient SOUS la barre des taches. Deux
    // causes possibles, toutes deux fermees ici :
    //  1. la taille minimale de 640 px logiques depasse la hauteur utile d'un
    //     portable 1366 x 768 a 125 % (768 / 1,25 = 614, moins la barre des
    //     taches) : Windows impose alors une fenetre PLUS HAUTE que la zone de
    //     travail, et son bas passe sous la barre. Le minimum est donc borne a
    //     la zone de travail du moniteur courant ;
    //  2. la taille agrandie est posee EXPLICITEMENT sur la zone de travail
    //     (`rcWork`, hors barre des taches), cadre redimensionnable compris en
    //     debord comme le fait Windows, au lieu de s'en remettre au defaut.
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
      const double echelle = static_cast<double>(dpi) / 96.0;
      info->ptMinTrackSize.x = static_cast<LONG>(1024 * echelle);
      info->ptMinTrackSize.y = static_cast<LONG>(640 * echelle);

      HMONITOR moniteur = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO infos_moniteur = {};
      infos_moniteur.cbSize = sizeof(MONITORINFO);
      if (GetMonitorInfo(moniteur, &infos_moniteur)) {
        const RECT& travail = infos_moniteur.rcWork;
        const RECT& ecran = infos_moniteur.rcMonitor;
        const LONG cadre = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                           GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
        const LONG largeur_travail = travail.right - travail.left;
        const LONG hauteur_travail = travail.bottom - travail.top;
        info->ptMaxPosition.x = travail.left - ecran.left - cadre;
        info->ptMaxPosition.y = travail.top - ecran.top - cadre;
        info->ptMaxSize.x = largeur_travail + 2 * cadre;
        info->ptMaxSize.y = hauteur_travail + 2 * cadre;
        if (info->ptMinTrackSize.x > largeur_travail) {
          info->ptMinTrackSize.x = largeur_travail;
        }
        if (info->ptMinTrackSize.y > hauteur_travail) {
          info->ptMinTrackSize.y = hauteur_travail;
        }
      }
      return 0;
    }

    // La sortie deliberee, retablie a la main.
    //
    // Les trois boutons systeme ont ete retires (voir `CreateAndShow`), ce qui
    // prive aussi `DefWindowProc` de sa reponse a Alt+F4 : sans ce cas, la
    // fenetre ne se fermerait plus que par le Gestionnaire des taches.
    //
    // Alt+F4 est conserve parce qu'il ne se declenche pas par megarde — c'est
    // exactement la difference avec la croix, qui se trouve sous le curseur au
    // moment ou l'on vise autre chose. Le geste reste possible, il cesse
    // d'etre accidentel.
    //
    // ## Ce que ce cas ne fait PAS, et qui reste a faire
    //
    // Il ne consulte pas les paniers ouverts. La protection posee ici est
    // physique — on ne peut plus fermer d'un clic — et non metier : Alt+F4
    // ferme sans rien demander. La garde metier (« deux paniers sont ouverts,
    // voulez-vous vraiment quitter ? ») appartient au cote Dart, qui seul
    // connait l'etat des paniers ; elle n'existe pas encore et ne doit pas
    // etre supposee ici. Ecrire l'inverse ferait de ce commentaire un
    // indicateur affirmant un controle qui n'a pas lieu.
    case WM_SYSKEYDOWN:
      if (wparam == VK_F4 && (GetKeyState(VK_MENU) & 0x8000) != 0) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
        return 0;
      }
      break;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
