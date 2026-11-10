-- Shared variables, used by hyprlands/*.lua modules

local vars = {}

-- MY PROGRAMS
local HOME = os.getenv("HOME")
local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end

-- Terminal mac dinh: kitty chay fish (install.sh cung chsh -s fish)
vars.terminal    = "kitty fish"
-- thunar-themed la wrapper rieng (neu co), khong thi dung thunar
vars.fileManager = exists(HOME .. "/.local/bin/thunar-themed") and (HOME .. "/.local/bin/thunar-themed") or "thunar"
vars.menu        = "hyprlauncher"

-- KEYBINDINGS
vars.mainMod = "SUPER" -- Sets "Windows" key as main modifier

local mainMod = vars.mainMod

-- Phim cho profile "dev" (Quantum Shell): chi chay khi caelth dang o profile dev,
-- o profile upstream thi khong lam gi (phim caelestia:* lo phan do).
-- Khong co caelth (profile switcher) thi goi thang IPC cua shell: qs -c caelestia ipc call <args>
local CAELTH = HOME .. "/.local/bin/caelth"
local function quantum(args)
    if exists(CAELTH) then return hl.dsp.exec_cmd(CAELTH .. " ipc-if dev " .. args) end
    return hl.dsp.exec_cmd("qs -c caelestia ipc call " .. args)
end
vars.quantum = quantum

local terminal_classes = { ["kitty"] = true, ["herdr-app"] = true }
function cael_clip(k)
    local w = hl.get_active_window()
    local cls = w and w.class or ""
    local mods = terminal_classes[cls] and "CTRL SHIFT" or "CTRL"
    hl.dispatch(hl.dsp.send_shortcut({ mods = mods, key = k }))
end

-- Each entry: { key = "<bind string>", action = <hl.dsp dispatcher>, opts = <optional hl.bind opts> }
-- Consumed by hyprlands/keybinds.lua, which just loops over this list and calls hl.bind.
vars.keybinds = {
    -- Mo terminal (kitty + fish)
    { key = mainMod .. " + RETURN",         action = hl.dsp.exec_cmd(vars.terminal) },
    { key = "CTRL + ALT + T",               action = hl.dsp.exec_cmd(vars.terminal) },
    { key = mainMod .. " + SHIFT + RETURN", action = hl.dsp.exec_cmd(vars.terminal .. " -e btop") }, -- terminal chay btop
    { key = mainMod .. " + Q", action = hl.dsp.window.close() },
    -- Copy/Paste kieu macOS: SUPER+C / SUPER+V gui Ctrl+C / Ctrl+V cho cua so dang focus.
    -- Terminal (kitty, herdr) dung Ctrl+Shift+C/V de Ctrl+C van la ngat tien trinh.
    { key = mainMod .. " + C", action = function() cael_clip("c") end },
    { key = mainMod .. " + V", action = function() cael_clip("v") end },
    { key = mainMod .. " + M", action = hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'") },
    { key = mainMod .. " + E", action = hl.dsp.exec_cmd(vars.fileManager) },
    { key = "CTRL + SHIFT + Escape", action = hl.dsp.exec_cmd(HOME .. "/.local/bin/quantum-taskmgr") }, -- Task Manager (nhu Windows)
    { key = mainMod .. " + R", action = hl.dsp.exec_cmd(vars.menu) },
    -- Esc: dang fullscreen -> thoat va dua cua so ve 3/4 o giua (cael_esc trong minimize.lua).
    -- non_consuming = app van nhan Esc (vim, hop thoai...); khong fullscreen thi khong lam gi.
    { key = "Escape", action = function() if cael_esc then cael_esc() end end, opts = { non_consuming = true } },
    -- ALT+TAB: chuyen cua so trong workspace hien tai (kieu Cmd+Tab cua macOS, Quantum Shell).
    -- Giu ALT bam TAB de chon cua so ke tiep, tha ALT de chuyen toi.
    -- Tha ALT chi goi shell khi trinh chuyen dang mo (co cael_sw_open).
    { key = "ALT + TAB", action = function()
        cael_sw_open = true
        hl.dispatch(quantum("switcher next"))
    end },
    { key = "ALT + ALT_L", action = function()
        if cael_sw_open then cael_sw_open = false; hl.dispatch(quantum("switcher commit")) end
    end, opts = { release = true, non_consuming = true } },
    { key = "ALT + ALT_R", action = function()
        if cael_sw_open then cael_sw_open = false; hl.dispatch(quantum("switcher commit")) end
    end, opts = { release = true, non_consuming = true } },
    { key = mainMod .. " + P", action = hl.dsp.window.pseudo() },
    { key = mainMod .. " + J", action = hl.dsp.layout("togglesplit") }, -- dwindle only

    -- Caelestia Shell global shortcuts (requires xdg-desktop-portal-hyprland)
    -- See README.md "Phim tat va IPC" for the full list of shortcut names.
    { key = mainMod .. " + SUPER_L", action = hl.dsp.global("caelestia:launcher"), opts = { release = true } }, -- Tap SUPER alone
    { key = mainMod .. " + SPACE",   action = hl.dsp.global("caelestia:utilities") }, -- Utilities popup (toggles, incl. wallpaper)
    { key = mainMod .. " + W",       action = hl.dsp.global("caelestia:wallpaperToggle") }, -- Toggle wallpaper on/off
    { key = mainMod .. " + SHIFT + W", action = hl.dsp.exec_cmd("caelestia wallpaper -r") }, -- Random wallpaper
    { key = mainMod .. " + I",       action = hl.dsp.global("caelestia:nexus") },
    { key = mainMod .. " + SHIFT + E", action = hl.dsp.global("caelestia:settings") }, -- Settings popup (giong nut Mo cai dat trong popup bar)
    { key = mainMod .. " + D",       action = hl.dsp.global("caelestia:dashboard") },
    { key = mainMod .. " + TAB",         action = hl.dsp.global("caelestia:spaceSwitcher") }, -- Switch workspace (island)
    { key = mainMod .. " + SHIFT + TAB", action = hl.dsp.global("caelestia:appSwitcher") },
    { key = mainMod .. " + A",       action = hl.dsp.global("caelestia:sidebar") },
    { key = mainMod .. " + X",       action = hl.dsp.global("caelestia:session") },
    { key = mainMod .. " + L",       action = hl.dsp.global("caelestia:lock") },
    { key = mainMod .. " + T",       action = hl.dsp.global("caelestia:themeToggle") }, -- Toggle dark/light

    -- Caelestia profile (caelth): SUPER+SHIFT+S doi qua lai upstream <-> dev, CTRL+SUPER+ALT+P chon bang menu
    -- Dung duong dan day du vi PATH cua phien Hyprland co the khong co ~/.local/bin
    { key = mainMod .. " + SHIFT + S",         action = hl.dsp.exec_cmd(CAELTH .. " next") },
    { key = "CTRL + " .. mainMod .. " + ALT + P", action = hl.dsp.exec_cmd(CAELTH .. " pick") },

    -- Quantum Shell (profile dev): cung phim voi caelestia de dung giong nhau o 2 profile
    { key = mainMod .. " + SUPER_L", action = quantum("shell launcher"), opts = { release = true } }, -- Menu app
    { key = mainMod .. " + A",         action = quantum("shell controlCenter") },  -- Trung tam dieu khien
    { key = mainMod .. " + N",         action = quantum("shell controlCenter") },  -- Thong bao
    { key = mainMod .. " + D",         action = quantum("shell dashboard") },      -- Lich + hieu nang
    { key = mainMod .. " + X",         action = quantum("shell session") },        -- Menu tat may
    { key = mainMod .. " + L",         action = quantum("lock lock") },            -- Khoa man hinh
    { key = mainMod .. " + W",         action = quantum("shell wallpapers") },     -- Chon hinh nen
    { key = mainMod .. " + I",         action = quantum("shell personalize") },    -- Personalizar
    { key = mainMod .. " + SHIFT + V", action = quantum("shell clipboard") },      -- Lich su clipboard

    -- Move focus with mainMod + arrow keys
    { key = mainMod .. " + left",  action = hl.dsp.focus({ direction = "left" }) },
    { key = mainMod .. " + right", action = hl.dsp.focus({ direction = "right" }) },
    { key = mainMod .. " + up",    action = hl.dsp.focus({ direction = "up" }) },
    { key = mainMod .. " + down",  action = hl.dsp.focus({ direction = "down" }) },

    -- ALT + A/S/D/W: focus window left/down/right/up
    { key = "ALT + A", action = hl.dsp.focus({ direction = "left" }) },
    { key = "ALT + D", action = hl.dsp.focus({ direction = "right" }) },
    { key = "ALT + W", action = hl.dsp.focus({ direction = "up" }) },
    { key = "ALT + S", action = hl.dsp.focus({ direction = "down" }) },

    -- ALT + SHIFT + A/S/D/W: move window left/down/right/up
    { key = "ALT + SHIFT + A", action = hl.dsp.window.move({ direction = "left" }) },
    { key = "ALT + SHIFT + D", action = hl.dsp.window.move({ direction = "right" }) },
    { key = "ALT + SHIFT + W", action = hl.dsp.window.move({ direction = "up" }) },
    { key = "ALT + SHIFT + S", action = hl.dsp.window.move({ direction = "down" }) },

    -- Screenshot vung chon (SUPER+S). Scratchpad "magic" cu da bo phim nay.
    { key = mainMod .. " + S", action = hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-region.sh") },

    -- Quay man hinh: nhan de bat dau, nhan lai de dung (toggle)
    { key = mainMod .. " + SHIFT + R", action = hl.dsp.exec_cmd("caelestia record") },

    -- Quay 1 vung man hinh: dung slurp de chon vung truoc khi quay
    { key = mainMod .. " + ALT + R", action = hl.dsp.exec_cmd("caelestia record -r") },

    -- Scroll through existing workspaces with mainMod + scroll
    { key = mainMod .. " + mouse_down", action = hl.dsp.focus({ workspace = "e+1" }) },
    { key = mainMod .. " + mouse_up",   action = hl.dsp.focus({ workspace = "e-1" }) },

    -- Move/resize windows with mainMod + LMB/RMB and dragging
    { key = mainMod .. " + mouse:272", action = hl.dsp.window.drag(),   opts = { mouse = true } },
    { key = mainMod .. " + mouse:273", action = hl.dsp.window.resize(), opts = { mouse = true } },

    -- Screenshot (popup thong bao Open/Save sau khi chup, xem README caelestia-cli)
    { key = "Print",         action = hl.dsp.exec_cmd("caelestia screenshot") },
    { key = "SHIFT + Print", action = hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-region.sh") },

    -- Laptop multimedia keys for volume and LCD brightness
    { key = "XF86AudioRaiseVolume",  action = hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), opts = { locked = true, repeating = true } },
    { key = "XF86AudioLowerVolume",  action = hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      opts = { locked = true, repeating = true } },
    { key = "XF86AudioMute",         action = hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     opts = { locked = true, repeating = true } },
    { key = "XF86AudioMicMute",      action = hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   opts = { locked = true, repeating = true } },
    { key = "XF86MonBrightnessUp",   action = hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  opts = { locked = true, repeating = true } },
    { key = "XF86MonBrightnessDown", action = hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  opts = { locked = true, repeating = true } },

    -- Requires playerctl
    { key = "XF86AudioNext",  action = hl.dsp.exec_cmd("playerctl next"),       opts = { locked = true } },
    { key = "XF86AudioPause", action = hl.dsp.exec_cmd("playerctl play-pause"), opts = { locked = true } },
    { key = "XF86AudioPlay",  action = hl.dsp.exec_cmd("playerctl play-pause"), opts = { locked = true } },
    { key = "XF86AudioPrev",  action = hl.dsp.exec_cmd("playerctl previous"),   opts = { locked = true } },
}

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    table.insert(vars.keybinds, { key = mainMod .. " + " .. key,         action = hl.dsp.focus({ workspace = i }) })
    table.insert(vars.keybinds, { key = mainMod .. " + SHIFT + " .. key, action = hl.dsp.window.move({ workspace = i }) })
end

return vars
