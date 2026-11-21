// Quickshell modules, all in one process: `qs -c quickshell_modules -d`
// (started from ~/.config/hypr/hyprland.lua).
//   AltTab.qml  Alt+Tab window switcher (Hyprland global shortcuts alttab:*)
//   Wifi.qml    Wi-Fi menu (`qs -c quickshell_modules ipc call wifi toggle`)
import Quickshell

ShellRoot {
    AltTab {}
    Wifi {}
}
