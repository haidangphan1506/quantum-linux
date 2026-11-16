------------------------------------
---- THANH TIEU DE KIEU macOS   ----
------------------------------------

-- Dung plugin hyprbars (hyprwm/hyprland-plugins), build cho dung Hyprland dang chay.
-- Nut ben trai: do = dong, vang = thu nho xuong dock (xem minimize.lua), xanh = toan man hinh.
-- Neu chua co file .so thi bo qua, Hyprland van chay binh thuong.
-- Build/cai .so: ~/.config/hypr/scripts/build-hyprbars.sh  (install.sh tu chay neu chua co)

------------------------------------------------------------
---- APP CO HEADER RIENG (nhu Brave)                       ----
------------------------------------------------------------
-- Cac app tu ve header (hang tab Chromium, headerbar GTK3/GTK4): KHONG co thanh hyprbars,
-- dung header cua app. Nut cua app thanh 3 cham do/vang/xanh ben trai nho
-- ~/.config/gtk-{3,4}.0/quantum-window-buttons.css + button-layout 'close,minimize,maximize:'.
-- Nut vang/xanh: dblclick.lua bat cu bam (Hyprland 0.57 bo qua minimize cua app, rules.lua
-- chan maximize). kind = vi tri nut trong header:
--   "gtk3": Chromium/Brave (theme GTK) va hop thoai GTK3 tu ve titlebar
--   "adw" : GTK4 / libadwaita (Nautilus, File Roller, app GNOME)
--   "own" : app tu ve nut kieu rieng (khong bat cu bam)
-- Kiem tra bang cach mo app: neu thay 2 hang nut (hyprbars + cua app) thi them vao day.
-- Brave: chon Theme "GTK" va TAT "Use system title bar and borders".
CAEL_OWN_HEADER_LIST = {
    { name = "brave",       re = "brave-browser",   lua = "^brave%-browser$",  kind = "gtk3" },
    { name = "chromium",    re = "chromium",        lua = "^chromium$",        kind = "gtk3" },
    { name = "chrome",      re = "google-chrome",   lua = "^google%-chrome$",  kind = "gtk3" },
    { name = "vivaldi",     re = "vivaldi-stable",  lua = "^vivaldi%-stable$", kind = "own"  },
    { name = "gnome",       re = "org\\.gnome\\..+", lua = "^org%.gnome%.",  kind = "adw"  },
    { name = "xfce4-about", re = "xfce4-about",     lua = "^xfce4%-about$",    kind = "gtk3" },
}
-- Muc trong danh sach cho class nay (nil = cua so co thanh hyprbars)
function cael_own_header(cls)
    if not cls then return nil end
    for _, e in ipairs(CAEL_OWN_HEADER_LIST) do
        if string.match(cls, e.lua) then return e end
    end
    return nil
end
CAEL_OWN_HEADER = {}                  -- (cu) nay dung cael_own_header()

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
hl.plugin.hyprbars.add_button({   -- xanh: zoom 3/4 man hinh <-> full (giong bam dup thanh tieu de)
    bg_color = "rgb(28c840)", fg_color = "rgb(004d00)", size = 13, icon = "+",
    action = "hyprctl eval 'cael_toggle_size()'",
})

CAEL_BAR_HEIGHT = 30                  -- = bar_height ben duoi

-- Rule: app co header rieng -> khong co thanh hyprbars, mo full vung lam viec
for _, e in ipairs(CAEL_OWN_HEADER_LIST) do
    hl.window_rule({
        name  = "own-header-" .. e.name,
        match = { class = "^(" .. e.re .. ")$" },
        ["hyprbars:no_bar"] = true,
    })
    -- khong co thanh hyprbars: mo full vung lam viec, khong chua 30px cho thanh tieu de
    -- (rule sau de len size/move cua rules.lua)
    hl.window_rule({
        name  = "own-header-size-" .. e.name,
        match = { class = "^(" .. e.re .. ")$", modal = false, title = "negative:Picture(-| )in(-| )[Pp]icture" },
        size  = "(monitor_w-24) (monitor_h-54)",
        move  = "12 42",
    })
end
