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

-- 3 ngon trai/phai: chuyen giua cac cua so ("tab") trong cung workspace (cael_cycle, minimize.lua)
-- vuot sang trai = cua so ke tiep, sang phai = cua so truoc (giong lat trang)
hl.gesture({ fingers = 3, direction = "left",  action = function() cael_cycle(1) end })
hl.gesture({ fingers = 3, direction = "right", action = function() cael_cycle(-1) end })

-- 3 ngon len/xuong (Quantum Shell, Shell.swipe):
--   len   = dong Launchpad neu dang mo, neu khong thi mo Mission Control
--   xuong = dong Mission Control neu dang mo, neu khong thi mo Launchpad (danh sach app)
local quantum = require("variable").quantum
local function swipe(dir)
    return function() hl.dispatch(quantum("shell swipe " .. dir)) end
end
hl.gesture({ fingers = 3, direction = "up",   action = swipe("up") })
hl.gesture({ fingers = 3, direction = "down", action = swipe("down") })

