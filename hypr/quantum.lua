-- Cấu hình Hyprland (Lua) cho Quantum Shell: tự khởi chạy shell + phím tắt gọi IPC.
-- Cần Hyprland >= 0.55. Thêm vào hyprland.lua:  require("quantum")
local mainMod = "SUPER"
local qs = "qs -c caelestia ipc call "

require("minimize")

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1 || /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("qs -c caelestia")
    hl.exec_cmd("qs -p ~/.config/quickshell/caelestia/tools/idle -n -d")
end)

local function ipc(args) return hl.dsp.exec_cmd(qs .. args) end

hl.bind(mainMod .. " + SPACE",          ipc("shell launcher"))
hl.bind(mainMod .. " + V",              ipc("shell clipboard"))
hl.bind(mainMod .. " + A",              ipc("shell controlCenter"))
hl.bind(mainMod .. " + D",              ipc("shell dashboard"))
hl.bind(mainMod .. " + W",              ipc("shell wallpapers"))
hl.bind(mainMod .. " + comma",          ipc("shell personalize"))
hl.bind(mainMod .. " + L",              ipc("shell lock"))
hl.bind(mainMod .. " + ESCAPE",         ipc("shell session"))
hl.bind(mainMod .. " + TAB",            ipc("overview toggle"))
hl.bind(mainMod .. " + G",              ipc("launchpad toggle"))
hl.bind("ALT + TAB",                    ipc("switcher next"))
hl.bind("ALT + SHIFT + TAB",            ipc("switcher prev"))
hl.bind(mainMod .. " + C",              hl.dsp.exec_cmd("hyprctl eval \"cael_close('$(hyprctl activewindow -j | jq -r .address)')\""))
hl.bind(mainMod .. " + Q",              hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + E",              hl.dsp.exec_cmd("nautilus"))
hl.bind("CTRL + SHIFT + ESCAPE",        hl.dsp.exec_cmd("quantum-taskmgr"))
hl.bind(mainMod .. " + SHIFT + S",      hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd(qs .. "shell brightnessUp"),                       { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd(qs .. "shell brightnessDown"),                     { locked = true, repeating = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"),                           { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),                                 { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),                             { locked = true })
