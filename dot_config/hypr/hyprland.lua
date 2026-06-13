-- Converted from hyprland.conf to Hyprland 0.55 Lua config.
-- Source config: /mnt/data/hyprland.conf
-- API reference style: attached hyprland.lua example.
---
------------------
---- MONITORS ----
------------------

local laptop_output   = "eDP-1"
local external_output = "HDMI-A-1"

local laptop_mode     = "1920x1080@60"
local external_mode   = "1920x1080@60"

local laptop_pos      = "0x0"
local external_pos    = "auto-right"

local laptop_scale    = 1
local external_scale  = 1

hl.monitor({
    output   = laptop_output,
    mode     = laptop_mode,
    position = laptop_pos,
    scale    = laptop_scale,
})

hl.monitor({
    output   = external_output,
    mode     = external_mode,
    position = external_pos,
    scale    = external_scale,
})
-------------------------------
---- DISPLAY ENV VARIABLES ----
-------------------------------

hl.env("LAPTOP_OUTPUT", "eDP-1")
hl.env("EXTERNAL_OUTPUT", "HDMI-A-1")
hl.env("LAPTOP_MODE", "1920x1080@60.1")
hl.env("EXTERNAL_MODE", "1920x1080@60.0")
hl.env("LAPTOP_POS", "0x0")
hl.env("EXTERNAL_POS_EXTEND", "1920x0")
hl.env("EXTERNAL_POS_MIRROR", "0x0")
hl.env("LAPTOP_SCALE", "1")
hl.env("EXTERNAL_SCALE", "1")

---------------------
---- MY PROGRAMS ----
---------------------

local terminal      = "foot"
local fileManager   = "thunar -w"
local menu          = "fuzzel-scale.sh"
local browser       = "vivaldi-stable"
local browser_second= "librewolf --new-window &"
local screenshot    = [[grim -g "$(slurp)" -| GTK_THEME=Adwaita:dark swappy -f -]]
local clipBoard     = "wofi-cliphist.sh"
local powermenu     = "fuzzel-powermenu.sh"
local calculator    = "qalc_floating.sh"
local colorPicker   = "$HOME/.config/hypr/scripts/hyprPicker.sh"
local displayPicker = "hyprmode"
local appSwitcher   = "hyprAppSwitcher.sh"
local passwordManager = "keepassxc"
local mediaPlayer = "flatpak run io.github.mpc_qt.mpc-qt"

-------------------
---- AUTOSTART ----
-------------------

local autostart_wrapper = "$HOME/.config/hypr/autostart-wrapper.sh"

hl.on("hyprland.start", function()
    local cmd = string.format([=[
bash -lc '
sleep 0.5

if hyprctl monitors | grep -q "^Monitor %s "; then
    hyprctl dispatch "hl.dsp.focus({ monitor = \"%s\" })"
fi

exec %s
'
]=], external_output, external_output, autostart_wrapper)

    hl.exec_cmd(cmd)
end)
---
-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 5,

        border_size = 2,

        col = {
            active_border   = "rgba(9198A1aa)",
            inactive_border = "rgba(2B2B2Baa)",
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding = 5,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = false,
    },
})

--------------------
---- ANIMATIONS ----
--------------------

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},   {0.32, 1}   } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}   } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},      {1, 1}      } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},  {0.75, 1.0} } })
hl.curve("quick",          { type = "bezier", points = { {0.2, 0.8},  {0.2, 1}    } })

-- Original config had animations:enabled = false. These definitions are preserved
-- so they are ready if you later switch animations.enabled back to true.
hl.animation({ leaf = "global",        enabled = true,  speed = 1.5,  bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 1.5,  bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 1.5,  bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 1.2,  bezier = "easeOutQuint",   style = "popin 100%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.2,  bezier = "linear",         style = "popin 100%" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 1.4,  bezier = "easeInOutCubic" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.2,  bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.0,  bezier = "easeInOutCubic" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 0.05, bezier = "linear" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 0.05, bezier = "linear" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 0.05, bezier = "linear" })
hl.animation({ leaf = "workspaces",    enabled = false })
hl.animation({ leaf = "workspacesIn",  enabled = false })
hl.animation({ leaf = "workspacesOut", enabled = false })

---------------
---- LAYOUT ----
---------------

hl.config({
    dwindle = {
        preserve_split        = true,
        force_split           = 2,
        use_active_for_splits = false,
        smart_resizing        = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "caps:swapescape",
        kb_rules   = "",

        follow_mouse       = 1,
        numlock_by_default = true,
        accel_profile      = "flat",

        touchpad = {
            natural_scroll = true,
            scroll_factor  = 0.2,
        },
    },
})

-- Old commented line kept as a reminder:
-- hl.on("hyprland.start", function() hl.exec_cmd("~/.config/hypr/scripts/setxkmap.sh") end)

hl.device({
    name        = "instant-usb-gaming-mouse-",
    sensitivity = -0.4,
})

hl.device({
    name        = "elan1200:00-04f3:3090-touchpad",
    sensitivity = 0.35,
})

hl.device({
    name        = "compx-2.4g-receiver-mouse",
    sensitivity = 0,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod   = "SUPER"
local secondMod = "ALT"
local mainAlt   = mainMod .. " + " .. secondMod

-- Applications
hl.bind(mainMod .. " + space",      hl.dsp.exec_cmd("fcitx5-remote -t"))
hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",          hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + O",          hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + B",          hl.dsp.exec_cmd(browser))
hl.bind(mainAlt .. " + B",          hl.dsp.exec_cmd(browser_second))
hl.bind(mainMod .. " + G",          hl.dsp.exec_cmd(screenshot))
hl.bind(mainAlt .. " + G",          hl.dsp.exec_cmd(colorPicker))
hl.bind(mainMod .. " + V",          hl.dsp.exec_cmd(clipBoard))
hl.bind(mainAlt .. " + P",          hl.dsp.exec_cmd(powermenu))
hl.bind(mainMod .. " + P",          hl.dsp.exec_cmd(displayPicker))
hl.bind(secondMod .. " + O",        hl.dsp.exec_cmd(calculator))
hl.bind(secondMod .. " + TAB",        hl.dsp.exec_cmd(appSwitcher))
hl.bind(mainMod .. " + CTRL + X",   hl.dsp.exec_cmd("chezmoi apply"))
hl.bind(mainAlt .. " + X",          hl.dsp.exec_cmd("$HOME/.config/waybar/scripts/restartWaybar.sh"))
hl.bind(mainAlt .. " + C",          hl.dsp.exec_cmd("hyprctl reload > /dev/null 2>&1"))
-- Window state
hl.bind(mainMod .. " + C", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Move focus with Vim-style keys
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Move active window
hl.bind(mainAlt .. " + H", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainAlt .. " + L", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainAlt .. " + K", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainAlt .. " + J", hl.dsp.window.move({ direction = "down" }))

-- Groups
hl.bind(mainMod .. " + N", hl.dsp.group.toggle())
hl.bind(mainAlt .. " + N", hl.dsp.window.move({ out_of_group = true }))
hl.bind(secondMod .. " + S",         hl.dsp.group.next())
hl.bind(secondMod .. " + D", hl.dsp.group.prev())

-- Workspace navigation
-- Apps / windows
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))
hl.bind(mainMod .. " + D", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + S", hl.dsp.focus({ workspace = "-1" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(secondMod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(secondMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
    hl.bind(secondMod .. " + CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Move active window to adjacent workspaces
hl.bind(mainAlt .. " + D", hl.dsp.window.move({ workspace = "+1" }))
hl.bind(mainAlt .. " + S", hl.dsp.window.move({ workspace = "-1" }))

-- Example special workspace kept from original comments.
-- hl.bind(mainMod .. " + S",          hl.dsp.workspace.toggle_special("magic"))
-- hl.bind(mainAlt .. " + S",          hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e+1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse:274", hl.dsp.window.close())

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),       { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 10%+"),                            { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"),                            { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Pavucontrol
hl.window_rule({
    name  = "pavucontrol-floating",
    match = { class = "org.pulseaudio.pavucontrol" },
    size  = {650, 400},
    move  = {1200, 640},
    float = true,
})

-- Blueman
hl.window_rule({
    name  = "blueman-manager-floating",
    match = { class = "blueman-manager" },
    size  = {529, 345},
    move  = {1368, 694},
    float = true,
})

-- Zenity / GTK files dialog
hl.window_rule({
    name  = "gtk-files-dialog-floating",
    match = { class = "xdg-desktop-portal-gtk", title = "Files" },
    size  = {700, 400},
    move  = {1200, 640},
    float = true,
})

-- AB download manager
hl.window_rule({
    name  = "ab-download-manager-floating",
    match = { class = "com-abdownloadmanager-desktop-AppKt" },
    float = true,
})

-- Zenity devices dialog
hl.window_rule({
    name  = "zenity-devices-floating",
    match = { class = "zenity", title = "Devices" },
    size  = {500, 400},
    move  = {1360, 640},
    float = true,
})

-- Mailspring
hl.window_rule({
    name  = "mailspring-floating",
    match = { class = "Mailspring" },
    size  = {1884, 1026},
    float = true,
    center= true
})

-- LocalSend
hl.window_rule({
    name  = "localsend-main-floating",
    match = { class = "localsend_app", title = "LocalSend" },
    size  = {558, 578},
    move  = {1340, 462},
    float = true,
})

hl.window_rule({
    name  = "localsend-open-file-floating",
    match = { class = "localsend_app", title = "Open File" },
    size  = {731, 578},
    move  = {1200, 462},
    float = true,
})

-- Zenity choose directory
hl.window_rule({
    name  = "gtk-choose-directory-floating",
    match = { class = "xdg-desktop-portal-gtk", title = "Choose Directory" },
    size  = {691, 514},
    move  = {1225, 522},
    float = true,
})

-- swayimg
hl.window_rule({
    name  = "swayimg-floating",
    match = { class = "swayimg" },
    float = true,
})

-- Xournal++ bookmark menu
hl.window_rule({
    name  = "xournalpp bookmark - new",
    match = { class = "com.github.xournalpp.xournalpp", title = "Xournalpp - New bookmark" },
    move  = {"cursor_x-(window_w*0.5)", "cursor_y-(window_h*0.5)"},
    float = true,
})

hl.window_rule({
    name  = "xournalpp bookmark - manager",
    match = { class = "com.github.xournalpp.xournalpp", title = "Xournalpp - Bookmarks Manager" },
    size  = {477,326},
    move  = {"cursor_x-(window_w*0.2)", "cursor_y-(window_h*0.5)"},
    float = true,
})
-- Ignore maximize requests from floating windows.
hl.window_rule({
    name           = "suppress-maximize-floating",
    match          = { float = true },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland.
hl.window_rule({
    name     = "fix-xwayland-empty-class-title",
    match    = { xwayland = true, class = "^$", title = "^$" },
    no_focus = true,
})

-- HyprMode - Lid switch handling window
hl.window_rule({
    name    = "hyprmode-floating",
    match   = { class = "^(hyprmode)$" },
    float   = true,
    center  = true,
    size    = {600, 530},
    opacity = "0.95",
})

-- xdg-desktop-portal-gtk for browser download dialogs
hl.window_rule({
    name  = "gtk-portal-floating",
    match = { class = "xdg-desktop-portal-gtk" },
    float = true,
})

-- File Roller extraction popup
hl.window_rule({
    name  = "file-roller-floating",
    match = { class = "org.gnome.FileRoller" },
    float = true,
})

-- Thunar popups
hl.window_rule({
    name  = "thunar-confirm-replace-floating",
    match = { class = "thunar", title = "Confirm to replace files" },
    float = true,
})

hl.window_rule({
    name  = "thunar-file-operation-progress-floating",
    match = { class = "thunar", title = "File Operation Progress" },
    float = true,
})

hl.window_rule({
    name = "Thunar rename",
    match = {
        class = "thunar",
        title = [[^Rename ".*"$]],
    },
    float = true,
    move = {
        "cursor_x-(window_w*0.5)",
        "cursor_y-(window_h*0.5)",
    },
})

-- Bitwarden extension popup
hl.window_rule({
    name  = "vivaldi-bitwarden-popups",
    match = { class = "vivaldi-stable", title = "Bitwarden - Vivaldi" },
    float = true,
})

-- vivaldi popup
hl.window_rule({
    name = "Vivaldi open file popup",
    match = {
        class = "vivaldi-stable",
        title = "Open File",
    },
    float = true,
    center = true
})
-- Generic KeePassXC window, but NOT the browser access dialog
hl.window_rule({
    name  = "Keepassxc",
    match = {
        class = "org.keepassxc.KeePassXC",
        title = "negative:KeePassXC - Browser Access Request",
    },
    center = true,
    size   = {1567, 929},
    float  = true,
})

-- KeePassXC browser access request dialog
hl.window_rule({
    name  = "Keepassxc browser access request",
    match = {
        class = "org.keepassxc.KeePassXC",
        title = "KeePassXC - Browser Access Request",
    },
    float = true,
    move = {
        "cursor_x-(window_w*0.5)",
        "cursor_y-(window_h*0.5)",
    },
})

-- MPC-qt
hl.window_rule({
    name = "mpc-qt-workspace",
    match = { class = "io.github.mpc_qt.mpc-qt" },
    workspace = "10 silent",
})

-- copyq menu
hl.window_rule({
    name = "CopyQ menu",
    match = {
        class = "com.github.hluk.copyq",
        title = "CopyQ",
    },
    float = true,
    move = {
        "cursor_x-(window_w*0)",
        "cursor_y-(window_h*0)",
    },

})

-- peazip
hl.window_rule({
    name = "Peazip",
    match = {
        class = "peazip"
    },
    float = true
})
