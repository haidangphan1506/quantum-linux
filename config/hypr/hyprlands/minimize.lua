-----------------------------
---- THU NHO KIEU macOS  ----
-----------------------------

-- Hyprland khong co "minimize": chi phat su kien window.minimize khi app/dock yeu cau.
-- O day: thu nho = dua cua so vao workspace an "special:minimized" (khong chuyen man hinh),
-- khoi phuc = dua ve workspace dang xem va focus.
-- Dock cua Quantum Shell (profile dev) hien cac cua so nay va bam vao de khoi phuc.

local MIN_WS = "special:minimized"

-- Hyprland 0.57 bo qua yeu cau thu nho tu chinh app (xdg set_minimized, vd nut "_" cua Brave).
-- Plugin cael-minimize (nguon ~/dev/cael-minimize) chuyen yeu cau do thanh su kien window.minimize ben duoi.
-- Nhu hyprbars: PHAI goi hl.plugin.load moi lan reload.
do
    local so = os.getenv("HOME") .. "/.local/lib/hyprland/cael-minimize.so"
    local f = io.open(so, "r")
    if f then
        f:close()
        local ok, err = pcall(hl.plugin.load, so)
        if not ok then
            hl.exec_cmd("notify-send -a Hyprland 'cael-minimize khong nap duoc' '" .. tostring(err):gsub("'", "") .. "'")
        end
    end
end

local function in_min(w)
    return w and w.workspace and w.workspace.name == MIN_WS
end

-- Hieu ung (genie / scale) chi cho cua so float; cua so tile van thu nho ngay.
local saved     = {}      -- address -> { x, y, w, h } vi tri/kich thuoc goc
local busy      = {}      -- address -> true khi dang chay hieu ung

local function dsp(d) pcall(hl.dispatch, d) end

-- Giu nguyen con tro chuot: focus/chuyen workspace mac dinh "warp" chuot vao cua so.
-- Tat warp trong luc chay fn roi bat lai (cursor.no_warps mac dinh = false).
local function no_warp(fn)
    pcall(hl.config, { cursor = { no_warps = true } })
    local ok, err = pcall(fn)
    pcall(hl.config, { cursor = { no_warps = false } })
    if not ok then error(err) end
end

-- Super+1..0: chuyen workspace khong warp chuot (warp dua con tro vao cua so -> bar nhap nhay)
function cael_goto_ws(i)
    no_warp(function() dsp(hl.dsp.focus({ workspace = i })) end)
end

-- Dich thu nho = mot o nho nam GON trong dai dock o day man hinh (khong de cua so to chong len dock)
local DOCK_W, DOCK_H, DOCK_BOTTOM = 72, 44, 72   -- DOCK_BOTTOM: khoang cach tu day man hinh, nam tren pill dock (khong chong len dock)

local function dock_rect(w)
    local m = w.monitor
    if type(m) ~= "table" and type(m) ~= "userdata" then m = hl.get_active_monitor and hl.get_active_monitor() end
    local scale = (m and m.scale and m.scale > 0) and m.scale or 1
    local mx, my = m and m.x or 0, m and m.y or 0
    local mw, mh = (m and m.width or 1920) / scale, (m and m.height or 1080) / scale
    local tw, th = DOCK_W, DOCK_H
    return math.floor(mx + mw / 2 - tw / 2), math.floor(my + mh - th - DOCK_BOTTOM), tw, th
end

local function set_geom(sel, x, y, ww, hh)
    dsp(hl.dsp.window.resize({ x = ww, y = hh, window = sel }))
    dsp(hl.dsp.window.move({ x = x, y = y, window = sel }))
end

------------------------------------------------------------
-- HIEU UNG THU NHO / KHOI PHUC KIEU macOS (Cai dat -> Dock -> "Thu nho cua so bang"):
--   "genie": cua so cong lai nhu than den chui vao dock | "scale": ca cua so co deu (giu ti le) vao dock
-- Hyprland khong bien dang duoc cua so: Quantum Shell ve hieu ung (modules/effects/GenieFx.qml,
-- chup cua so roi ve tren lop overlay), o day chi goi no qua IPC roi an / hien cua so that.
-- Khong co shell (IPC loi) thi cua so van thu nho / khoi phuc ngay, khong hieu ung.
------------------------------------------------------------
local SETTINGS = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/quantum/settings.json"
local FX_MS = { genie = 600, scale = 360 }   -- thoi gian hieu ung (ms), gan voi macOS

-- Doc lai moi lan thu nho (file nho): doi trong Cai dat la ap dung ngay, khong can reload Hyprland
local function min_effect()
    local f = io.open(SETTINGS, "r")
    if not f then return "genie" end
    local txt = f:read("*a")
    f:close()
    local v = txt:match('"minimizeEffect"%s*:%s*"(%a+)"')
    return (v == "scale") and "scale" or "genie"
end

-- Chieu cao thanh tieu de hyprbars ve phia tren cua so (khong nam trong w.at / w.size)
local function bar_h(w)
    if not (hl.plugin and hl.plugin.hyprbars) or not CAEL_BAR_HEIGHT then return 0 end
    if cael_own_header and cael_own_header(w.class) then return 0 end
    return CAEL_BAR_HEIGHT
end

-- Goi hieu ung trong Quantum Shell. mode: min | restore. Toa do logic cua man hinh.
local function fx_play(addr, x, y, ww, hh, mode, eff, ms)
    local dx, dy = dock_rect({})
    hl.exec_cmd(string.format("qs -c caelestia ipc call genie play %s %d %d %d %d %d %d %s:%s %d",
        addr, math.floor(x), math.floor(y), math.floor(ww), math.floor(hh), dx + math.floor(DOCK_W / 2), dy + DOCK_H, eff, mode, ms))
end

local minimize
local function minimize_impl(w)
    if not w or in_min(w) or busy[w.address] then return end
    local sel = "address:" .. w.address
    -- Dang fullscreen (vd video): thoat fullscreen truoc, doi cua so ve kich thuoc cu roi moi thu nho.
    -- Neu khong, hieu ung/vi tri luu la cua man hinh day va cua so van giu trang thai fullscreen trong workspace an.
    if w.fullscreen and w.fullscreen ~= 0 then
        local addr = w.address
        local mode = (w.fullscreen == 1) and "maximized" or "fullscreen"
        busy[addr] = true
        dsp(hl.dsp.window.fullscreen({ mode = mode, action = "toggle", window = sel }))
        hl.timer(function()
            busy[addr] = nil
            for _, v in ipairs(hl.get_windows()) do
                if v.address == addr then
                    if v.fullscreen and v.fullscreen ~= 0 then
                        -- phong ho: van con fullscreen -> an luon khong hieu ung
                        no_warp(function() dsp(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel })) end)
                    else
                        minimize(v)
                    end
                    return
                end
            end
        end, { timeout = 250, type = "oneshot" })
        return
    end
    if not w.floating then
        no_warp(function() dsp(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel })) end)
        return
    end
    local addr = w.address
    busy[addr] = true
    saved[addr] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    local eff = min_effect()
    local ms = FX_MS[eff]
    -- no_anim: luc chuyen sang workspace an Hyprland khong chay hieu ung fade cua no
    dsp(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = sel }))
    -- chup ca thanh tieu de (hyprbars) phia tren cua so: hieu ung la chup man hinh
    local top = bar_h(w)
    fx_play(addr, w.at.x, w.at.y - top, w.size.x, w.size.y + top, "min", eff, ms)
    -- shell an cua so that (opacity 0) khi bat dau ve; xong thi dua vao workspace an
    hl.timer(function()
        busy[addr] = nil
        no_warp(function() dsp(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel })) end)
    end, { timeout = ms + 140, type = "oneshot" })
end

minimize = minimize_impl

local function restore(w)
    if not in_min(w) or busy[w.address] then return end
    local ws = hl.get_active_workspace()
    local sel = "address:" .. w.address
    local g = saved[w.address]
    -- co hieu ung: cua so phai van trong suot luc quay lai workspace (shell ve hieu ung roi moi hien no)
    if g then dsp(hl.dsp.window.set_prop({ prop = "opacity", value = "0.0", window = sel })) end
    if ws then
        for _, v in ipairs(hl.get_windows()) do
            if v.address ~= w.address and v.fullscreen and v.fullscreen ~= 0 and not in_min(v)
                and v.workspace and v.workspace.id == ws.id then
                local mode = (v.fullscreen == 1) and "maximized" or "fullscreen"
                dsp(hl.dsp.window.fullscreen({ mode = mode, action = "toggle", window = "address:" .. v.address }))
            end
        end
    end
    no_warp(function()
        dsp(hl.dsp.window.move({ workspace = (ws and ws.id) or 1, follow = false, window = sel }))
        dsp(hl.dsp.focus({ window = sel }))
        -- dua len tren cung cac cua so dang mo (focus khong tu nang cua so float len)
        dsp(hl.dsp.window.alter_zorder({ mode = "top", window = sel }))
    end)
    if g then
        local addr = w.address
        saved[addr] = nil
        busy[addr] = true
        local eff = min_effect()
        local ms = FX_MS[eff]
        -- cua so van trong suot (opacity 0) o vi tri cu; shell chup chinh cua so (toplevel) va ve
        -- hieu ung tu dock ra, xong thi hien cua so that (opacity 1)
        set_geom(sel, g.x, g.y, g.w, g.h)
        hl.timer(function()
            fx_play(addr, g.x, g.y, g.w, g.h, "restore", eff, ms)
        end, { timeout = 40, type = "oneshot" })
        -- phong ho: shell khong chay / khong chup duoc -> van hien lai cua so
        hl.timer(function()
            busy[addr] = nil
            dsp(hl.dsp.window.set_prop({ prop = "opacity", value = "1.0", window = sel }))
            dsp(hl.dsp.window.set_prop({ prop = "no_anim", value = "0", window = sel }))
        end, { timeout = ms + 900, type = "oneshot" })
    else
        -- mat thong tin (vd vua reload config): hien lai va dua ve 75% man hinh neu dang nho
        dsp(hl.dsp.window.set_prop({ prop = "opacity", value = "1.0", window = sel }))
        dsp(hl.dsp.window.set_prop({ prop = "no_anim", value = "0", window = sel }))
        if w.floating and w.size.x < 400 then
            local m = w.monitor
            local scale = (m and m.scale and m.scale > 0) and m.scale or 1
            local mw, mh = (m and m.width or 1920) / scale, (m and m.height or 1080) / scale
            local ww, hh = math.floor(mw * 0.75), math.floor(mh * 0.75)
            set_geom(sel, math.floor((m and m.x or 0) + (mw - ww) / 2), math.floor((m and m.y or 0) + (mh - hh) / 2), ww, hh)
        end
    end
end

-- Yeu cau tu app (nut "_" cua app) hoac tu dock (wlr-foreign-toplevel set_minimized)
hl.on("window.minimize", function(w, minimized)
    if minimized then minimize(w) else restore(w) end
end)

-- Goi tu nut tren thanh tieu de / phim tat:  hyprctl eval 'cael_minimize()'
function cael_minimize()
    minimize(hl.get_active_window())
end

-- Khoi phuc cua so thu nho gan nhat (phim tat)
function cael_restore_last()
    local last
    for _, w in ipairs(hl.get_windows()) do
        if in_min(w) and (not last or w.focus_history_id < last.focus_history_id) then last = w end
    end
    restore(last)
end

------------------------------------------------------------
-- PHONG TO chi rieng 1 cua so (nut xanh cua app / hyprbars / bam dup thanh tieu de)
-- Khong dung che do "maximized" cua Hyprland vi no la trang thai cua ca workspace:
-- cac cua so float khac bi che/an va focus cua so khac thi tu thu lai.
-- O day chi doi vi tri/kich thuoc cua so float -> cac cua so khac khong bi anh huong.
------------------------------------------------------------
local GAP    = 12     -- = general.gaps_out
local maxed  = {}     -- address -> { x, y, w, h } kich thuoc truoc khi phong to
local opened = {}     -- address -> thoi diem mo (giay), de bo qua yeu cau phong to luc app vua mo

-- Hyprland dung lai dia chi cua cua so da dong cho cua so moi: phai xoa trang thai cu,
-- neu khong cua so moi se "nho" kich thuoc cua cua so truoc (loi phong to/tra lai sai).
local function forget(w)
    if not w or not w.address then return end
    saved[w.address], maxed[w.address], busy[w.address], opened[w.address] = nil, nil, nil, nil
end
hl.on("window.open", function(w)
    forget(w)
    if w and w.address then opened[w.address] = os.time() end
end)
hl.on("window.close", forget)
hl.on("window.destroy", function(w) if type(w) == "table" or type(w) == "userdata" then pcall(forget, w) end end)

local function work_area(w)
    local m = w.monitor
    if type(m) ~= "table" and type(m) ~= "userdata" then m = hl.get_active_monitor and hl.get_active_monitor() end
    local scale = (m and m.scale and m.scale > 0) and m.scale or 1
    local r = (m and m.reserved) or {}
    local x = (m and m.x or 0) + (r.left or 0) + GAP
    local y = (m and m.y or 0) + (r.top or 0) + GAP
    local ww = (m and m.width or 1920) / scale - (r.left or 0) - (r.right or 0) - 2 * GAP
    local hh = (m and m.height or 1080) / scale - (r.top or 0) - (r.bottom or 0) - 2 * GAP
    return math.floor(x), math.floor(y), math.floor(ww), math.floor(hh)
end

-- Chieu cao thanh hyprbars ve PHIA TREN cua so (khong tinh vao w.at/w.size), 0 neu cua so khong co bar
local function deco_top(w)
    if not (hl.plugin and hl.plugin.hyprbars) or not CAEL_BAR_HEIGHT then return 0 end
    if cael_own_header and cael_own_header(w.class) then return 0 end   -- titlebar.lua
    return CAEL_BAR_HEIGHT
end

-- Cua so co kich thuoc co dinh (hop thoai "About"...) khong doi duoc kich thuoc:
-- sau khi thu, neu kich thuoc khong doi thi chi can giua cho gon.
local function center_if_fixed(sel, addr, old_w, old_h, tw, th)
    hl.timer(function()
        for _, w in ipairs(hl.get_windows()) do
            if w.address == addr then
                local reached = math.abs(w.size.x - tw) <= 4 and math.abs(w.size.y - th) <= 4
                local stuck   = math.abs(w.size.x - old_w) <= 2 and math.abs(w.size.y - old_h) <= 2
                if stuck and not reached then
                    maxed[addr] = nil
                    dsp(hl.dsp.window.center({ window = sel }))
                end
                return
            end
        end
    end, { timeout = 900, type = "oneshot" })
end

local function find_window(addr)
    if not addr then return hl.get_active_window() end
    for _, w in ipairs(hl.get_windows()) do
        if w.address == addr then return w end
    end
end

function cael_maximize(addr)
    -- Co addr = yeu cau tu chinh app (plugin cael-minimize), vd Brave: bam dup header va nut xanh
    -- gui cung 1 yeu cau, khong phan biet duoc -> dung kieu 3/4 <-> full nhu bam dup.
    if addr then
        -- nhieu app (kitty, Chromium...) tu xin phong to luc vua mo de khoi phuc trang thai cu:
        -- bo qua trong 2 giay dau, cua so mo o 3/4 man hinh theo rule
        local t = opened[addr]
        if t and os.time() - t < 2 then return end
        return cael_toggle_size(addr)
    end
    local w = find_window(addr)
    if not w or in_min(w) or busy[w.address] then return end
    local sel = "address:" .. w.address
    if not w.floating then
        -- cua so tile: dung che do maximized cua Hyprland nhu cu
        dsp(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = sel }))
        return
    end
    local g = maxed[w.address]
    if g then
        maxed[w.address] = nil
        set_geom(sel, g.x, g.y, g.w, g.h)
    else
        maxed[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
        local x, y, ww, hh = work_area(w)
        local top = deco_top(w)
        set_geom(sel, x, y + top, ww, hh - top)
        center_if_fixed(sel, w.address, w.size.x, w.size.y, ww, hh - top)
    end
end

-- BAM DUP thanh tieu de: chuyen qua lai giua 3/4 man hinh (o giua) va full vung lam viec.
-- Khac nut xanh (cael_maximize tra ve kich thuoc truoc do): luon la 1 trong 2 kich thuoc co dinh.
function cael_toggle_size(addr)
    if addr == "" then addr = nil end
    local w = find_window(addr)
    if not w or in_min(w) or busy[w.address] then return end
    local sel = "address:" .. w.address
    if not w.floating then
        dsp(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = sel }))
        return
    end
    local x, y, ww, hh = work_area(w)
    local top = deco_top(w)
    local fx, fy, fw, fh = x, y + top, ww, hh - top          -- kich thuoc full
    local is_full = math.abs(w.at.x - fx) <= 4 and math.abs(w.at.y - fy) <= 4
        and math.abs(w.size.x - fw) <= 4 and math.abs(w.size.y - fh) <= 4
    maxed[w.address] = nil
    if is_full then
        -- 3/4 kich thuoc man hinh, can giua vung lam viec
        local m = w.monitor
        local scale = (m and m.scale and m.scale > 0) and m.scale or 1
        local tw = math.floor((m and m.width or 1920) / scale * 0.75)
        local th = math.floor((m and m.height or 1080) / scale * 0.75)
        set_geom(sel, math.floor(x + (ww - tw) / 2), math.floor(y + (hh - th) / 2 + top / 2), tw, th - top)
    else
        maxed[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }  -- nut xanh van tra ve duoc
        set_geom(sel, fx, fy, fw, fh)
        center_if_fixed(sel, w.address, w.size.x, w.size.y, fw, fh)
    end
end

-- Full vung lam viec (giong nhanh full cua cael_toggle_size; nut xanh / bam dup van ve 3/4 duoc)
local function set_full(w)
    local sel = "address:" .. w.address
    local x, y, ww, hh = work_area(w)
    local top = deco_top(w)
    maxed[w.address] = nil
    set_geom(sel, x, y + top, ww, hh - top)
end

-- Phim Esc (bind non_consuming trong variable.lua, app van nhan Esc):
-- chi khi cua so dang fullscreen (vd video YouTube) -> thoat fullscreen roi dua ve kich thuoc
-- full vung lam viec cua browser/app (khong ve 3/4). Cua so khong fullscreen: khong lam gi.
function cael_esc()
    local w = hl.get_active_window()
    if not w or in_min(w) or busy[w.address] then return end
    if not w.fullscreen or w.fullscreen == 0 then return end
    local addr = w.address
    local mode = (w.fullscreen == 1) and "maximized" or "fullscreen"
    dsp(hl.dsp.window.fullscreen({ mode = mode, action = "toggle", window = "address:" .. addr }))
    -- doi Hyprland tra cua so ve kich thuoc cu roi moi dat full vung lam viec
    hl.timer(function()
        local v = find_window(addr)
        if v and v.floating and (v.fullscreen or 0) == 0 then set_full(v) end
    end, { timeout = 250, type = "oneshot" })
end

-- Ghi de: nhan them dia chi cua so (menu "Cua so" tren bar kieu macOS goi kem dia chi,
-- vi luc bam menu focus co the dang o bar).
function cael_minimize(addr)
    minimize(find_window(addr ~= "" and addr or nil))
end

-- Menu tren bar kieu macOS: "An ung dung khac" / "Hien tat ca"
function cael_hide_others(addr)
    local keep = find_window(addr ~= "" and addr or nil)
    local ws = hl.get_active_workspace()
    for _, w in ipairs(hl.get_windows()) do
        if w ~= nil and (not keep or w.address ~= keep.address) and not in_min(w)
            and w.workspace and ws and w.workspace.id == ws.id then
            minimize(w)
        end
    end
end

function cael_show_all()
    for _, w in ipairs(hl.get_windows()) do
        if in_min(w) then restore(w) end
    end
end

-- Dock bam vao app dang mo (khong thu nho): focus + dua len tren cung, KHONG keo con tro.
-- (wlr-foreign-toplevel activate cua Hyprland luon warp chuot nen dock goi ham nay thay the)
-- Cua so fullscreen (video YouTube...) che moi cua so khac cung workspace. Alt+Tab / dock sang app khac:
-- KHONG thoat fullscreen; app do noi len TREN video (alter_zorder top -> allowed_over_fullscreen). Phai goi
-- truoc focus, neu khong misc:on_focus_under_fullscreen = 2 se bo fullscreen cua video.
-- Quay lai cua so fullscreen: day cac cua so dang noi tren no xuong (alter_zorder bottom xoa
-- allowed_over_fullscreen) -> video lai phu kin man hinh. Rieng maximized (1) van bo maximized nhu cu.
local function prepare_fullscreen_stack(target)
    local sel = "address:" .. target.address
    -- Cua so app van dang fullscreen nhung Hyprland da nha man hinh (internal 0, client 2): tra lai fullscreen that
    -- (ban sua cu goi fullscreen_state lech internal/client -> Hyprland tat sync_fullscreen cua cua so, tu do
    --  YouTube bam F chi doi trang thai phia app; bat lai sync de fullscreen cua app lai phu kin man hinh)
    if (target.fullscreen or 0) == 0 and (target.fullscreen_client or 0) == 2 then
        dsp(hl.dsp.window.set_prop({ prop = "sync_fullscreen", value = "1", window = sel }))
        dsp(hl.dsp.window.fullscreen_state({ internal = 2, client = 2, action = "set", window = sel }))
    end
    local target_fs = (target.fullscreen or 0) == 2 or (target.fullscreen_client or 0) == 2
    local ws = target.workspace and target.workspace.id
    for _, v in ipairs(hl.get_windows()) do
        if v.address ~= target.address and not in_min(v) and v.workspace and v.workspace.id == ws then
            if v.fullscreen == 1 then
                dsp(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = "address:" .. v.address }))
            elseif target_fs and (v.fullscreen or 0) == 0 and v.allowed_over_fullscreen then
                dsp(hl.dsp.window.alter_zorder({ mode = "bottom", window = "address:" .. v.address }))
            end
        end
    end
    if not target_fs then dsp(hl.dsp.window.alter_zorder({ mode = "top", window = sel })) end
end

-- Nho vi tri con tro trong tung cua so (toa do tuong doi goc tren-trai cua so).
-- Truoc khi chuyen cua so: neu con tro dang nam trong cua so active thi luu lai;
-- khi Alt+Tab vao cua so khac: dat con tro ve dung ccho cu cua cua so do (chua co thi giua cua so).
local cursor_mem = {}
local function inside(w, c)
    return c.x >= w.at.x and c.x < w.at.x + w.size.x and c.y >= w.at.y and c.y < w.at.y + w.size.y
end
local function remember_cursor()
    local cur, c = hl.get_active_window(), hl.get_cursor_pos()
    if cur and c and cur.at and inside(cur, c) then
        cursor_mem[cur.address] = { x = c.x - cur.at.x, y = c.y - cur.at.y }
    end
end

-- warp = true (Alt+Tab): dua con tro vao cua so duoc chon, o vi tri con tro dung lan truoc.
function cael_activate(addr, warp)
    local w = find_window(addr ~= "" and addr or nil)
    if not w then return end
    if in_min(w) then return restore(w) end
    local sel = "address:" .. w.address
    if warp then pcall(remember_cursor) end
    prepare_fullscreen_stack(w)   -- zorder truoc focus: giu fullscreen cua video cung workspace
    no_warp(function()
        dsp(hl.dsp.focus({ window = sel }))   -- tu chuyen sang workspace cua cua so neu can
    end)
    if warp then
        -- Cho cua so len tren cung xong moi dat con tro (cua so chong nhau: neu dat ngay, pointer focus
        -- van o cua so cu), roi nhich 1px de Hyprland tinh lai cua so duoi con tro.
        hl.timer(function()
            pcall(function()
                local t = find_window(w.address) or w
                local m = cursor_mem[w.address]
                local x, y = t.at.x + t.size.x / 2, t.at.y + t.size.y / 2
                if m then
                    local mx, my = t.at.x + m.x, t.at.y + m.y
                    if inside(t, { x = mx, y = my }) then x, y = mx, my end
                end
                x, y = math.floor(x), math.floor(y)
                dsp(hl.dsp.cursor.move({ x = x + 1, y = y }))
                dsp(hl.dsp.cursor.move({ x = x, y = y }))
            end)
        end, { timeout = 60, type = "oneshot" })
    end
end

-- MO APP O CHE DO FULL (vung lam viec, van thay bar tren cung) theo mac dinh.
-- Rule size-3-4-all (rules.lua) dat cua so thuong o 3/4 man hinh; o day cua so nao dang dung
-- 3/4 (tuc la cua so thuong, khong phai hop thoai / kich thuoc co dinh) thi phong to len full.
-- Nut xanh / bam dup header -> ve 3/4.
local OPEN_FULL = true  -- true: app mo full vung lam viec; cua so Quantum Shell (org.quickshell: Tuy chinh, Acerca...) van mo 3/4

hl.on("window.open", function(w)
    -- Quantum Shell (Tuy chinh, Acerca de...) se queda en 3/4 al abrir: no se phong to
    if not OPEN_FULL or not w or not w.address or (w.class or "") == "" or w.class == "org.quickshell" then return end
    local addr = w.address
    hl.timer(function()
        local win = find_window(addr)
        if not win or not win.floating or in_min(win) then return end
        local m = win.monitor
        if type(m) ~= "table" and type(m) ~= "userdata" then return end
        local scale = (m.scale and m.scale > 0) and m.scale or 1
        local qw, qh = m.width / scale * 0.75, m.height / scale * 0.75
        -- chi cua so dang o dung 3/4 (do rule dat)
        if math.abs(win.size.x - qw) > qw * 0.04 or math.abs(win.size.y - qh) > qh * 0.04 then return end
        local x, y, ww, hh = work_area(win)
        local top = deco_top(win)
        maxed[addr] = { x = win.at.x, y = win.at.y, w = win.size.x, h = win.size.y }   -- nut xanh tra ve 3/4
        set_geom("address:" .. addr, x, y + top, ww, hh - top)
    end, { timeout = 60, type = "oneshot" })
end)

-- (Khong con gan cu chi: 3 ngon ngang gio mo trinh chuyen ALT+TAB, xem misc.lua.) Chuyen qua lai giua cac cua so trong workspace hien tai.
-- Thu tu = thu tu mo cua so (stable_id), vong tron; focus + dua len tren, khong keo chuot.
-- dir = 1 (cua so ke tiep) | -1 (cua so truoc)
function cael_cycle(dir)
    local ws = hl.get_active_workspace()
    if not ws then return end
    local list = {}
    for _, w in ipairs(hl.get_windows()) do
        if w and w.mapped ~= false and not in_min(w) and w.workspace and w.workspace.id == ws.id then
            list[#list + 1] = w
        end
    end
    if #list < 2 then return end
    local function key(w) return tonumber(w.stable_id or "", 16) or tonumber(w.stable_id or "") or 0 end
    table.sort(list, function(a, b) return key(a) < key(b) end)
    local cur = hl.get_active_window()
    local idx = 0
    for i, w in ipairs(list) do
        if cur and w.address == cur.address then idx = i break end
    end
    local nxt = list[((idx - 1 + dir) % #list) + 1]
    if idx == 0 then nxt = list[1] end
    cael_activate(nxt.address)
end
