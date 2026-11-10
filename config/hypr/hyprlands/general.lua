hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 12,

        border_size = 2,

        col = {
            -- Mau theo scheme "caelestia" (inversePrimary/outlineVariant)
            active_border   = "rgba(336764ee)",
            inactive_border = "rgba(3f4a49aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    }
})

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

-- Màn hình OLED (Samsung ATNA40CT03) báo hỗ trợ HDR: với cm_auto_hdr = 1, video toàn
-- màn hình (Brave/YouTube) làm Hyprland chuyển tấm nền sang HDR10 (Colorspace BT2020 +
-- metadata PQ) -> nội dung SDR bị tối hẳn. Tắt để luôn giữ chế độ SDR.
hl.config({
    render = {
        cm_auto_hdr = 0,
    },
})
