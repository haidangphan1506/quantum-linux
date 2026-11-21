-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Caelestia: thu muc hinh nen (tinh: assets/pictures, dong: assets/pictures/Animated -> assets/videos)
hl.env("CAELESTIA_WALLPAPERS_DIR", os.getenv("HOME") .. "/caelestia/assets/pictures")

-- Fcitx5 (bo go tieng Viet)
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
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
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- 4 ngon trai/phai: chuyen workspace
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})

local quantum = require("variable").quantum

-- 3 ngon: MOT cu chi duy nhat (direction = "swipe"), Lua tu chot huong.
-- (Hyprland chot huong ngay khi ngon tay di duoc 5 don vi -> vuot hoi cheo la mo nham Switcher / Launchpad.)
--   Ngang = giu ALT + TAB (trinh chuyen cua so, modules/switcher):
--     chot huong ngang -> mo trinh chuyen, chon cua so dung truoc do (nhu bam ALT+TAB lan dau)
--     giu 3 ngon, keo sang phai/trai -> chon cua so ke tiep / truoc (moi SW_STEP don vi)
--     nhac ngon tay -> chuyen toi cua so dang chon (nhu tha ALT)
--   Len   = dong Launchpad neu dang mo, neu khong thi mo Mission Control  (Shell.swipe, khi nhac tay)
--   Xuong = dong Mission Control neu dang mo, neu khong thi mo Launchpad
-- Moi lenh IPC la mot tien trinh `qs` rieng nen co the toi sai thu tu: gui so buoc TUYET DOI
-- kem so thu tu (seq); Switcher bo qua lenh cu, va lenh ket thuc mang luon vi tri cuoi.
local SW_LOCK  = 30   -- quang duong (don vi touchpad) truoc khi chot huong
local SW_RATIO = 1.4  -- truc chinh phai lon hon truc kia ngan nay lan (khong thi cho them)
local SW_STEP  = 95   -- quang duong ngang cho moi lan doi cua so
local sw = nil        -- cu chi dang chay
local sw_count = 0

local function sw_send(fn, args)
    -- so buoc + 1000: qs coi "-1" la tuy chon dong lenh
    hl.dispatch(quantum("switcher " .. fn .. " " .. args))
end

hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = {
        start = function(_)
            sw_count = sw_count + 1
            -- update() duoc goi ngay sau start voi cung su kien: bat dau tu 0 de khong cong 2 lan
            sw = { id = os.time() .. "g" .. sw_count, x = 0, y = 0, axis = nil, ox = 0, steps = 0, seq = 0 }
        end,
        update = function(e)
            if not sw then return end
            local d = (e and e.delta) or {}
            sw.x = sw.x + (d.x or 0)
            sw.y = sw.y + (d.y or 0)
            if not sw.axis then
                local ax, ay = math.abs(sw.x), math.abs(sw.y)
                if math.max(ax, ay) < SW_LOCK then return end
                if ax >= ay * SW_RATIO or (ax > ay and ax > SW_LOCK * 3) then
                    sw.axis = "h"
                    sw.ox = sw.x
                    sw.seq = 1
                    sw_send("swipe", sw.id .. " 1 1000")
                elseif ay >= ax * SW_RATIO or ay > SW_LOCK * 3 then
                    sw.axis = "v"
                else
                    return -- vuot cheo: cho them cho ro huong
                end
            end
            if sw.axis == "h" then
                local rel = sw.x - sw.ox
                local steps = rel >= 0 and math.floor(rel / SW_STEP) or -math.floor(-rel / SW_STEP)
                if steps ~= sw.steps then
                    sw.steps = steps
                    sw.seq = sw.seq + 1
                    sw_send("swipe", sw.id .. " " .. sw.seq .. " " .. (steps + 1000))
                end
            end
        end,
        finish = function(e)
            if not sw then return end
            local cancelled = e and e.cancelled
            if sw.axis == "h" then
                sw.seq = sw.seq + 1
                sw_send("swipeEnd", sw.id .. " " .. sw.seq .. " " .. (sw.steps + 1000) .. " " .. (cancelled and "false" or "true"))
            elseif sw.axis == "v" and not cancelled then
                hl.dispatch(quantum("shell swipe " .. (sw.y < 0 and "up" or "down")))
            end
            sw = nil
        end,
    },
})

