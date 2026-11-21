-- Shared variables, used by hyprlands/*.lua modules

local vars = {}

-- MY PROGRAMS
local HOME = os.getenv("HOME")
local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end

-- Terminal mac dinh: kitty chay fish (install.sh cung chsh -s fish)
vars.terminal    = "kitty fish"
-- thunar-themed la wrapper rieng (neu co), khong thi dung thunar
vars.fileManager = exists(HOME .. "/.local/bin/thunar-themed") and (HOME .. "/.local/bin/thunar-themed") or "thunar"

-- KEYBINDINGS
vars.mainMod = "SUPER" -- Sets "Windows" key as main modifier

local mainMod = vars.mainMod

-- Phim dieu khien Quantum Shell: goi thang IPC cua shell (qs -c caelestia ipc call <args>)
local function quantum(args)
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
    { key = mainMod .. " + Q", action = hl.dsp.exec_cmd(vars.terminal) },   -- SUPER+Q: mo terminal
    -- Copy/paste kieu macOS: cael_clip() gui CTRL+C/V (CTRL+SHIFT+C/V trong terminal)
    { key = mainMod .. " + C", action = function() cael_clip("c") end },   -- SUPER+C: copy
    { key = mainMod .. " + V", action = function() cael_clip("v") end },   -- SUPER+V: paste
    { key = mainMod .. " + X", action = hl.dsp.window.close() },           -- SUPER+X: dong rieng cua so dang focus (kill se giet ca tien trinh, dong het cua so Brave)
    { key = mainMod .. " + M", action = hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'") },
    { key = mainMod .. " + E", action = hl.dsp.exec_cmd(vars.fileManager) },
    { key = "CTRL + SHIFT + Escape", action = quantum("shell activityMonitor") }, -- Activity Monitor (thay Task Manager)
    { key = mainMod .. " + R", action = quantum("shell spotlight") }, -- Spotlight (thay hyprlauncher)
    { key = mainMod .. " + SPACE", action = quantum("shell spotlight") }, -- Spotlight (nhu Cmd+Space cua macOS)
    -- Esc: dang fullscreen -> thoat va dua cua so ve full vung lam viec (cael_esc trong minimize.lua).
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

    -- Quantum Shell (qs -c caelestia): cac phim shell. Da bo cac phim caelestia:* / caelth
    -- (shell hien tai khong dang ky global shortcut do, caelth khong co tren may).
    { key = mainMod .. " + SUPER_L", action = quantum("launchpad toggle"), opts = { release = true } }, -- Tap SUPER: Launchpad
    { key = mainMod .. " + A",         action = quantum("shell controlCenter") },  -- Trung tam dieu khien
    { key = mainMod .. " + N",         action = quantum("shell controlCenter") },  -- Thong bao
    { key = mainMod .. " + SHIFT + X", action = quantum("shell session") },        -- Menu tat may (SUPER+X da dung de dong app)
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

    -- Quay man hinh (gpu-screen-recorder): bam de bat dau, bam lai de dung va luu ~/Videos/Recordings
    { key = mainMod .. " + SHIFT + R", action = hl.dsp.exec_cmd("~/.config/hypr/scripts/screen-record.sh") },            -- toan man hinh
    { key = mainMod .. " + ALT + R",   action = hl.dsp.exec_cmd("~/.config/hypr/scripts/screen-record.sh --region") },   -- chon vung

    -- Scroll through existing workspaces with mainMod + scroll
    { key = mainMod .. " + mouse_down", action = hl.dsp.focus({ workspace = "e+1" }) },
    { key = mainMod .. " + mouse_up",   action = hl.dsp.focus({ workspace = "e-1" }) },

    -- Move/resize windows with mainMod + LMB/RMB and dragging
    { key = mainMod .. " + mouse:272", action = hl.dsp.window.drag(),   opts = { mouse = true } },
    { key = mainMod .. " + mouse:273", action = hl.dsp.window.resize(), opts = { mouse = true } },

    -- Screenshot (popup thong bao Open/Save sau khi chup, xem README caelestia-cli)
    { key = "Print",         action = hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-region.sh --full") },
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
    table.insert(vars.keybinds, { key = mainMod .. " + " .. key,         action = function() cael_goto_ws(i) end })
    table.insert(vars.keybinds, { key = mainMod .. " + SHIFT + " .. key, action = hl.dsp.window.move({ workspace = i }) })
end

return vars
