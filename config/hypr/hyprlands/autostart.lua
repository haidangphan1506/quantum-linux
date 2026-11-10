-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    hl.exec_cmd("fcitx5 -d")          -- Bo go tieng Viet (fcitx5)
    -- Shell: dung CLI caelestia neu co, khong thi chay thang Quickshell (config ~/.config/quickshell/caelestia)
    hl.exec_cmd("command -v caelestia >/dev/null && caelestia shell -d || qs -c caelestia -d")
    hl.exec_cmd("qs -p ~/.config/quickshell/caelestia/tools/idle -n -d")
    hl.exec_cmd("wl-paste --watch cliphist store")  -- lich su clipboard cho launcher
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
end)
