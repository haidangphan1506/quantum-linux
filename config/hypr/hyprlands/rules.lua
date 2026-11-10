-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    -- Nut phong to cua app duoc plugin cael-minimize chuyen sang cael_maximize() (minimize.lua)
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

-- Kieu macOS: MOI cua so deu float (cua so tile luon nam DUOI cua so float trong Hyprland,
-- nen click/mo app tile se bi terminal/Brave de len). Mo o giua, 3/4 man hinh;
-- hop thoai (modal) va Picture-in-Picture giu kich thuoc rieng. (Da bo Super+V: khong chuyen sang tile nua.)
hl.window_rule({
    name   = "float-all",
    match  = { class = ".+" },
    float  = true,
    center = true,
})
hl.window_rule({
    name  = "size-3-4-all",
    match = { class = ".+", modal = false, title = "negative:Picture(-| )in(-| )[Pp]icture" },
    size  = "(monitor_w*0.75) (monitor_h*0.75)",
})

-- «Acerca de este equipo»: ventana pequeña, 2/5 del ancho de la pantalla
hl.window_rule({
    name  = "size-about",
    match = { title = "^Acerca de este equipo$" },
    size  = "(monitor_w*0.4) (monitor_h*0.5)",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Terminal va Brave: mo dang noi (khong chia doi man hinh), 3/4 man hinh, o giua.
-- Cua so mo sau se nam de len cua so truoc, keo/doi kich thuoc tu do (SUPER + chuot trai/phai).
hl.window_rule({
    name  = "float-3-4-kitty",
    match = { class = "^(kitty)$" },

    float  = true,
    size   = "(monitor_w*0.75) (monitor_h*0.75)",
    center = true,
})

hl.window_rule({
    name  = "float-3-4-brave",
    -- bo qua cua so Picture-in-Picture (co rule rieng ben duoi)
    match = { class = "^(brave-browser)$", title = "negative:Picture(-| )in(-| )[Pp]icture" },

    float  = true,
    size   = "(monitor_w*0.75) (monitor_h*0.75)",
    center = true,
})

-- Browser Picture-in-Picture (Firefox, Chrome/Brave/Chromium all use this title)
hl.window_rule({
    name  = "browser-pip",
    match = { title = "Picture(-| )in(-| )[Pp]icture" },

    float             = true,
    pin               = true,
    keep_aspect_ratio = true,
    move              = "(monitor_w*0.98-window_w) (monitor_h*0.97-window_h)",
})
