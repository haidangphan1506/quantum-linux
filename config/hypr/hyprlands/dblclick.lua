------------------------------------------------------------
---- BAM DUP VUNG HEADER CUA APP (browser, app tu ve tab/headerbar) ----
------------------------------------------------------------
-- Hyprbars chi ve thanh tieu de o NGOAI cua so; cac app tu ve header (Brave/Chromium: hang tab,
-- GTK headerbar) thi click vao header la click vao client nen Hyprland khong biet.
-- Giai phap: bat chuot trai (non_consuming: app van nhan click binh thuong), neu 2 cu bam
-- nhanh lien tiep deu nam trong vung header dau cua so -> cael_toggle_size (3/4 <-> full).

-- App co header tu ve: danh sach o titlebar.lua (cael_own_header). Firefox van co hyprbars
-- nhung hang tab cung bam dup duoc.
local EXTRA_HEADER = { ["firefox"] = true }

-- Vi tri nut va chieu cao header theo kieu (tinh tu goc tren-trai cua so, do bang anh chup):
--   gtk3: Brave/Chromium/hop thoai GTK3 -> do x 9-24, vang 38-51, xanh 65-80, y 12-30
--   adw : GTK4/libadwaita (Nautilus...)   -> do x 10-19, vang ~31, xanh 51-62, y 17-28
local KINDS = {
    gtk3 = { header = 42, y0 = 4, y1 = 40, yellow = { 31, 58 }, green = { 58, 87 } },
    adw  = { header = 46, y0 = 6, y1 = 40, yellow = { 24, 44 }, green = { 44, 68 } },
    own  = { header = 42 },
}
local function kind_of(w)
    if not w or not w.class then return nil end
    local e = cael_own_header and cael_own_header(w.class)
    if e then return KINDS[e.kind] end
    if EXTRA_HEADER[w.class] then return KINDS.own end
    return nil
end
local DBL_MS     = 350  -- khoang thoi gian toi da giua 2 cu bam

local pending = nil     -- cu bam dau tien dang cho cu thu hai (token duy nhat)

local function in_header(w)
    if not w or not w.at or not w.size then return false end
    local k = kind_of(w)
    if not k then return false end
    if (w.fullscreen or 0) ~= 0 then return false end
    local c = hl.get_cursor_pos()
    if not c then return false end
    return c.x >= w.at.x and c.x < w.at.x + w.size.x
       and c.y >= w.at.y and c.y < w.at.y + k.header
end

------------------------------------------------------------
---- NUT VANG / XANH VE TRONG HANG TAB (Brave, Chromium)   ----
------------------------------------------------------------
-- Voi theme GTK + button-layout 'close,minimize,maximize:' Brave ve 3 cham do/vang/xanh
-- (~/.config/gtk-3.0/quantum-window-buttons.css). Nut do: app tu dong cua so.
-- Nut vang/xanh: app gui yeu cau minimize/maximize nhung Hyprland 0.57 bo qua minimize
-- (khong co plugin cael-minimize) va rules.lua chan maximize -> xu ly cu bam o day.
-- Toa do theo kieu header: KINDS o tren.
local function traffic_button(w)
    if not w or not w.at then return nil end
    local k = kind_of(w)
    if not k or not k.yellow then return nil end
    if (w.fullscreen or 0) ~= 0 then return nil end
    local c = hl.get_cursor_pos()
    if not c then return nil end
    local rx, ry = c.x - w.at.x, c.y - w.at.y
    if ry < k.y0 or ry > k.y1 then return nil end
    if rx >= k.yellow[1] and rx < k.yellow[2] then return "minimize" end
    if rx >= k.green[1] and rx < k.green[2] then return "zoom" end
    return nil
end

hl.bind("mouse:272", function()
    local w = hl.get_active_window()
    local b = traffic_button(w)
    if b then
        pending = nil
        local addr = w.address
        -- doi app nhan cu bam xong (non_consuming) roi moi thu nho / doi kich thuoc
        hl.timer(function()
            if b == "minimize" then cael_minimize(addr) else cael_toggle_size(addr) end
        end, { timeout = 60, type = "oneshot" })
        return
    end
    if not in_header(w) then
        pending = nil
        return
    end
    if pending then
        -- cu bam thu hai trong thoi gian cho -> double click
        pending = nil
        cael_toggle_size(w.address)
        return
    end
    local token = {}
    pending = token
    hl.timer(function()
        if pending == token then pending = nil end
    end, { timeout = DBL_MS, type = "oneshot" })
end, { non_consuming = true })
