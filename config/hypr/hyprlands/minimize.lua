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

-- Hieu ung kieu macOS ("Scale"): cua so mo dan + co lai + bay ve dock (giua canh duoi man hinh),
-- khoi phuc thi phong to nguoc tu dock. Chi cho cua so float (cua so tile van thu nho ngay).
local ANIM_MS   = 280     -- thoi gian truoc khi an han (khop voi animation "windows")
local MINI_W    = 0.18    -- kich thuoc luc o dock, ti le theo cua so goc
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

-- Thu nho tung buoc (ease-in) vao o dock: moi buoc la mot lan resize ro rang, khong phu thuoc animation cua Hyprland.
-- Trong luc chay tat animation cua Hyprland (no_anim) de kich thuoc + do mo cap nhat ngay tung buoc,
-- cua so van thay ro luc co lai va chi mo han o cuoi. App co kich thuoc toi thieu (vd pavucontrol 294x142)
-- khong co duoc ve o dock nhung den buoc cuoi da trong suot -> khong con o nho chong len dock.
local MIN_STEPS = 16
local function genie_to(sel, x0, y0, w0, h0, x1, y1, w1, h1, done)
    local i = 0
    dsp(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = sel }))
    local function step()
        i = i + 1
        local t = i / MIN_STEPS
        local e = t * t
        set_geom(sel, math.floor(x0 + (x1 - x0) * e), math.floor(y0 + (y1 - y0) * e),
                 math.floor(w0 + (w1 - w0) * e), math.floor(h0 + (h1 - h0) * e))
        -- con dam trong nua dau, mo nhanh dan ve 0 o buoc cuoi
        local a = 1 - t ^ 2.5
        dsp(hl.dsp.window.set_prop({ prop = "opacity", value = string.format("%.2f", a), window = sel }))
        if i < MIN_STEPS then
            hl.timer(step, { timeout = math.floor(ANIM_MS / MIN_STEPS), type = "oneshot" })
        elseif done then
            done()
        end
    end
    step()
end

local function minimize(w)
    if not w or in_min(w) or busy[w.address] then return end
    local sel = "address:" .. w.address
    if not w.floating then
        no_warp(function() dsp(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel })) end)
        return
    end
    busy[w.address] = true
    saved[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    local x, y, tw, th = dock_rect(w)
    genie_to(sel, w.at.x, w.at.y, w.size.x, w.size.y, x, y, tw, th, function()
        busy[w.address] = nil
        -- no_anim van bat (tu genie_to) luc chuyen sang workspace an: neu khong, hieu ung fade
        -- cua Hyprland ve lai cua so nho ngay tren dock voi do dam day du -> loe len thanh 1 o nho
        no_warp(function() dsp(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel })) end)
    end)
end

local function restore(w)
    if not in_min(w) or busy[w.address] then return end
    local ws = hl.get_active_workspace()
    local sel = "address:" .. w.address
    local g = saved[w.address]
    no_warp(function()
        dsp(hl.dsp.window.move({ workspace = (ws and ws.id) or 1, follow = false, window = sel }))
        dsp(hl.dsp.focus({ window = sel }))
        -- dua len tren cung cac cua so dang mo (focus khong tu nang cua so float len)
        dsp(hl.dsp.window.alter_zorder({ mode = "top", window = sel }))
    end)
    if g then
        saved[w.address] = nil
        busy[w.address] = true
        -- 1 frame o dang nho tai dock roi phong to ve vi tri cu
        hl.timer(function()
            busy[w.address] = nil
            dsp(hl.dsp.window.set_prop({ prop = "opacity", value = "1.0", window = sel }))
            dsp(hl.dsp.window.set_prop({ prop = "no_anim", value = "0", window = sel }))
            set_geom(sel, g.x, g.y, g.w, g.h)
        end, { timeout = 30, type = "oneshot" })
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
    for _, cls in ipairs(CAEL_OWN_HEADER or {}) do
        if w.class == cls then return 0 end
    end
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

-- 3/4 man hinh, can giua vung lam viec (giong nhanh 3/4 cua cael_toggle_size)
local function set_34(w)
    local sel = "address:" .. w.address
    local x, y, ww, hh = work_area(w)
    local top = deco_top(w)
    local m = w.monitor
    local scale = (m and m.scale and m.scale > 0) and m.scale or 1
    local tw = math.floor((m and m.width or 1920) / scale * 0.75)
    local th = math.floor((m and m.height or 1080) / scale * 0.75)
    maxed[w.address] = nil
    set_geom(sel, math.floor(x + (ww - tw) / 2), math.floor(y + (hh - th) / 2 + top / 2), tw, th - top)
end

-- Phim Esc (bind non_consuming trong variable.lua, app van nhan Esc):
-- chi khi cua so dang fullscreen -> thoat fullscreen roi dua ve 3/4 o giua de keo/doi kich thuoc.
-- Cua so khong fullscreen: khong lam gi.
function cael_esc()
    local w = hl.get_active_window()
    if not w or in_min(w) or busy[w.address] then return end
    if not w.fullscreen or w.fullscreen == 0 then return end
    local addr = w.address
    local mode = (w.fullscreen == 1) and "maximized" or "fullscreen"
    dsp(hl.dsp.window.fullscreen({ mode = mode, action = "toggle", window = "address:" .. addr }))
    -- doi Hyprland tra cua so ve kich thuoc cu roi moi dat 3/4
    hl.timer(function()
        local v = find_window(addr)
        if v and v.floating and (v.fullscreen or 0) == 0 then set_34(v) end
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
function cael_activate(addr)
    local w = find_window(addr ~= "" and addr or nil)
    if not w then return end
    if in_min(w) then return restore(w) end
    local sel = "address:" .. w.address
    no_warp(function()
        dsp(hl.dsp.focus({ window = sel }))   -- tu chuyen sang workspace cua cua so neu can
        dsp(hl.dsp.window.alter_zorder({ mode = "top", window = sel }))
    end)
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

-- Vuot 3 ngon trai/phai: chuyen qua lai giua cac cua so ("tab") trong workspace hien tai.
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
