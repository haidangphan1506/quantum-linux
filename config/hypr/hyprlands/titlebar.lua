------------------------------------
---- THANH TIEU DE KIEU macOS   ----
------------------------------------

-- Dung plugin hyprbars (hyprwm/hyprland-plugins), build cho dung Hyprland dang chay.
-- Nut ben trai: do = dong, vang = thu nho xuong dock (xem minimize.lua), xanh = toan man hinh.
-- Neu chua co file .so thi bo qua, Hyprland van chay binh thuong.

local SO = os.getenv("HOME") .. "/.local/lib/hyprland/hyprbars.so"

local function exists(path)
    local ok, f = pcall(io.open, path, "r")
    if ok and f then f:close() return true end
    return false
end

if not exists(SO) then return end
-- PHAI goi hl.plugin.load MOI LAN reload (khai bao, khong phai lenh mot lan).
-- Neu bo qua khi da nap, Hyprland tuong plugin bi go -> unload -> reload -> load...
-- de quy vo han -> tran stack -> Hyprland crash (vao safe mode).
local ok, err = pcall(hl.plugin.load, SO)
if not ok then
    hl.exec_cmd("notify-send -a Hyprland 'hyprbars khong nap duoc' '" .. tostring(err):gsub("'", "") .. "'")
    return
end
if not (hl.plugin.hyprbars and hl.plugin.hyprbars.add_button) then return end

-- Mau thanh tieu de theo che do sang/toi (caelestia viet scheme/current.lua; quantum-theme reload)
local light = false
pcall(function()
    package.loaded["scheme.current"] = nil
    local sc = require("scheme.current")
    local r = tonumber(string.sub(sc.surface or "000000", 1, 2), 16) or 0
    light = r > 128
end)
local BAR  = light and "rgba(ececf0ee)" or "rgba(1f1f28ee)"
local TEXT = light and "rgb(1d1d1f)"    or "rgb(e4e0ee)"
local IDLE = light and "rgba(00000026)" or "rgba(ffffff30)"

hl.config({
    plugin = {
        hyprbars = {
            bar_height            = 30,
            bar_color             = BAR,
            ["col.text"]          = TEXT,
            bar_text_size         = 11,
            bar_text_font         = "Sans",
            bar_text_weight       = "medium",
            bar_text_align        = "center",
            bar_blur              = true,
            bar_part_of_window    = true,
            bar_precedence_over_border = true,
            bar_buttons_alignment = "left",
            bar_padding           = 12,
            bar_button_padding    = 8,
            icon_on_hover         = true,      -- nhu macOS: ky hieu chi hien khi re chuot
            inactive_button_color = IDLE, -- cua so khong focus: nut xam
            -- Bam dup thanh tieu de: phong to / tra lai (van giu thanh tieu de)
            on_double_click = "hyprctl eval 'cael_toggle_size()'",   -- 3/4 man hinh <-> full (minimize.lua)
        },
    },
})

-- Nut can trai: nut them truoc nam ngoai cung ben trai
hl.plugin.hyprbars.add_button({   -- do: dong
    bg_color = "rgb(ff5f57)", fg_color = "rgb(4d0000)", size = 13, icon = "×",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
})
hl.plugin.hyprbars.add_button({   -- vang: thu nho xuong dock
    bg_color = "rgb(febc2e)", fg_color = "rgb(5a3e00)", size = 13, icon = "−",
    action = "hyprctl eval 'cael_minimize()'",
})
hl.plugin.hyprbars.add_button({   -- xanh: phong to / tra lai (chi cua so nay)
    bg_color = "rgb(28c840)", fg_color = "rgb(004d00)", size = 13, icon = "+",
    action = "hyprctl eval 'cael_maximize()'",
})

-- App co header rieng (tab bar, headerbar GTK): tat thanh hyprbars, dung header cua app luon.
-- Nut cua app lay theo gsettings org.gnome.desktop.wm.preferences button-layout
-- (dat 'close,minimize,maximize:' -> 3 nut ben trai nhu macOS). Nut thu nho cua app
-- gui yeu cau minimize -> minimize.lua xu ly nhu nut vang.
-- Brave KHONG nam trong danh sach: dung thanh hyprbars nhu terminal
-- (trong Brave bat "Use system title bar and borders" de Brave khong ve them nut rieng).
local OWN_HEADER = {
    "chromium", "google-chrome", "vivaldi-stable",
}
CAEL_OWN_HEADER = OWN_HEADER          -- minimize.lua dung de biet cua so nao co thanh hyprbars
CAEL_BAR_HEIGHT = 30                  -- = bar_height ben duoi
for _, cls in ipairs(OWN_HEADER) do
    hl.window_rule({
        name  = "own-header-" .. cls,
        match = { class = "^(" .. cls .. ")$" },
        ["hyprbars:no_bar"] = true,
    })
end
