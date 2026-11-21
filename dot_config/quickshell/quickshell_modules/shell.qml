//@ pragma Env __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
//@ pragma Env QSG_RENDER_LOOP=basic
//@ pragma Env MALLOC_ARENA_MAX=2
// RAM: load only the Intel/Mesa GL driver (Hyprland renders on the iGPU), not
// NVIDIA's too (~25 MB). QT_QUICK_BACKEND=software would save more but breaks
// the Alt+Tab window previews (ScreencopyView needs GPU textures).
// basic render loop + 2 malloc arenas: no extra render thread / arenas.
// Quickshell modules, all in one process: `qs -c quickshell_modules -d`
// (started from ~/.config/hypr/hyprland.lua; ~/.local/bin/autostart.sh as fallback).
//   AltTab.qml  Alt+Tab window switcher (Hyprland global shortcuts alttab:*)
//   Wifi.qml    Wi-Fi menu (`qs -c quickshell_modules ipc call wifi toggle`)
//   DropZone.qml  drag-and-drop zone next to the LocalSend file picker
import Quickshell

ShellRoot {
    AltTab {}
    Wifi {}
    DropZone {}
}
