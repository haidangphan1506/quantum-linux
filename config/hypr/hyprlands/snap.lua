-----------------------------
---- CHIA DOI CUA SO (SNAP) ----
-----------------------------
-- Moi cua so deu float (rules.lua) nen Hyprland khong tu chia o. O day tu xep:
--  * SUPER + mui ten: trai/phai = nua man hinh, tren/duoi = nua tren/duoi; bam 2 phim de ra goc 1/4,
--    bam nguoc huong de tro ve full.
--  * Keo cua so (SUPER+chuot trai hoac keo thanh tieu de) toi sat canh man hinh roi tha: canh = nua,
--    goc = 1/4.
-- Cua so tile (neu co) dung window.move theo huong cua Hyprland.

local GAP      = 12    -- = general.gaps_out, cung la khe giua 2 cua so
local EDGE     = 6     -- px: con tro cach canh man hinh <= EDGE thi tinh la "keo vao canh"
local CORNER   = 0.18  -- phan man hinh tu goc tinh la vung goc (1/4)
local TOL      = 10    -- px sai so khi nhan biet cua so dang o o nao

local function dsp(d) pcall(hl.dispatch, d) end

local function mon_of(w)
    local m = w and w.monitor
    if type(m) ~= "table" and type(m) ~= "userdata" then m = hl.get_active_monitor and hl.get_active_monitor() end
    return m
end

local function work_area(m)
    local scale = (m and m.scale and m.scale > 0) and m.scale or 1
    local r = (m and m.reserved) or {}
    local x = (m and m.x or 0) + (r.left or 0) + GAP
    local y = (m and m.y or 0) + (r.top or 0) + GAP
    local ww = (m and m.width or 1920) / scale - (r.left or 0) - (r.right or 0) - 2 * GAP
    local hh = (m and m.height or 1080) / scale - (r.top or 0) - (r.bottom or 0) - 2 * GAP
    return x, y, ww, hh
end

-- Thanh tieu de hyprbars nam PHIA TREN cua so (khong tinh vao w.at / w.size)
local function bar_top(w)
    if not (hl.plugin and hl.plugin.hyprbars) or not CAEL_BAR_HEIGHT then return 0 end
    if cael_own_header and cael_own_header(w.class) then return 0 end
    if (w.title or "") == "Quantum Learn" then return 0 end
    return CAEL_BAR_HEIGHT
end

-- Dat cua so vao o (x0..x1, y0..y1) la phan so 0..1 cua vung lam viec
local function place(w, x0, x1, y0, y1)
    local m = mon_of(w)
    local ax, ay, aw, ah = work_area(m)
    local top = bar_top(w)
    local px0, px1 = (x0 == 0 and 0 or aw / 2 + GAP / 2), (x1 == 1 and aw or aw / 2 - GAP / 2)
    local py0, py1 = (y0 == 0 and 0 or ah / 2 + GAP / 2), (y1 == 1 and ah or ah / 2 - GAP / 2)
    local x, y = math.floor(ax + px0), math.floor(ay + py0 + top)
    local ww, hh = math.floor(px1 - px0), math.floor(py1 - py0 - top)
    local sel = "address:" .. w.address
    dsp(hl.dsp.window.resize({ x = ww, y = hh, window = sel }))
    dsp(hl.dsp.window.move({ x = x, y = y, window = sel }))
end

-- Cua so dang o o nao: tra ve x0,x1,y0,y1 (0|0.5|1 theo cach place dung). Khong khop thi coi la full.
local function current_cell(w)
    local m = mon_of(w)
    local ax, ay, aw, ah = work_area(m)
    local top = bar_top(w)
    local function near(a, b) return math.abs(a - b) <= TOL end
    local function span(pos, size, a0, alen)
        local lo, hi = pos - a0, pos - a0 + size
        local left_edge  = near(lo, 0)
        local right_edge = near(hi, alen)
        local half_l = near(hi, alen / 2 - GAP / 2)
        local half_r = near(lo, alen / 2 + GAP / 2)
        if left_edge and half_l then return 0, 0.5 end
        if right_edge and half_r then return 0.5, 1 end
        return 0, 1
    end
    local x0, x1 = span(w.at.x, w.size.x, ax, aw)
    local y0, y1 = span(w.at.y - top, w.size.y + top, ay, ah)
    return x0, x1, y0, y1
end

local function find_window(addr)
    if not addr or addr == "" then return hl.get_active_window() end
    for _, w in ipairs(hl.get_windows()) do
        if w.address == addr then return w end
    end
end

local function in_min(w)
    return w and w.workspace and w.workspace.name == "special:minimized"
end

-- Nua doi dien cua nua vua chon
local OPPOSITE = { left = "right", right = "left", top = "bottom", bottom = "top" }
local CELLS = {
    left = { 0, 0.5, 0, 1 }, right = { 0.5, 1, 0, 1 }, top = { 0, 1, 0, 0.5 }, bottom = { 0, 1, 0.5, 1 },
}

-- Gap doi: ghi cua so partner vao nua con lai, ha cac cua so khac xuong day, dua 2 cua so len tren.
function cael_snap_pair(anchor_addr, partner_addr, partner_side)
    local a, p = find_window(anchor_addr), find_window(partner_addr)
    local c = CELLS[partner_side]
    if not a or not p or not c or in_min(a) or in_min(p) then return end
    place(p, c[1], c[2], c[3], c[4])
    local ws = a.workspace and a.workspace.id
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped ~= false and w.floating and not in_min(w) and w.workspace and w.workspace.id == ws
            and w.address ~= a.address and w.address ~= p.address then
            dsp(hl.dsp.window.alter_zorder({ mode = "bottom", window = "address:" .. w.address }))
        end
    end
    dsp(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. p.address }))
    dsp(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. a.address }))
    if cael_activate then cael_activate(a.address) end
end

-- Sau khi cua so ve 1 nua man hinh: 1 cua so khac -> tu chia nua con lai; tu 2 tro len -> mo bang chon.
local function after_half(w, x0, x1, y0, y1)
    local side
    if y0 == 0 and y1 == 1 and x1 - x0 == 0.5 then side = (x0 == 0) and "right" or "left"
    elseif x0 == 0 and x1 == 1 and y1 - y0 == 0.5 then side = (y0 == 0) and "bottom" or "top" end
    if not side then return end
    local others = {}
    for _, v in ipairs(hl.get_windows()) do
        if v.mapped ~= false and v.floating and not in_min(v) and v.address ~= w.address
            and v.workspace and w.workspace and v.workspace.id == w.workspace.id
            and (v.class or "") ~= "" then
            others[#others + 1] = v
        end
    end
    if #others == 1 then
        cael_snap_pair(w.address, others[1].address, side)
    elseif #others >= 2 then
        hl.exec_cmd("qs -c caelestia ipc call switcher pick " .. w.address .. " " .. side)
    end
end

local function snap_to(w, x0, x1, y0, y1)
    place(w, x0, x1, y0, y1)
    after_half(w, x0, x1, y0, y1)
end

-- SUPER + mui ten
function cael_snap(dirn)
    local w = find_window()
    if not w or (w.fullscreen and w.fullscreen ~= 0) then return end
    if not w.floating then
        dsp(hl.dsp.window.move({ direction = dirn }))
        return
    end
    local x0, x1, y0, y1 = current_cell(w)
    if dirn == "left" then
        if x0 == 0.5 then x0, x1 = 0, 1 else x0, x1 = 0, 0.5 end
    elseif dirn == "right" then
        if x1 == 0.5 then x0, x1 = 0, 1 else x0, x1 = 0.5, 1 end
    elseif dirn == "up" then
        if y0 == 0.5 then y0, y1 = 0, 1 else y0, y1 = 0, 0.5 end
    elseif dirn == "down" then
        if y1 == 0.5 then y0, y1 = 0, 1 else y0, y1 = 0.5, 1 end
    end
    snap_to(w, x0, x1, y0, y1)
end

-- Keo-tha vao canh: ghi lai cua so + vi tri luc bam chuot trai, luc nha so sanh
local press = nil

function cael_snap_press()
    local w = hl.get_active_window()
    if w and w.floating and w.address then
        press = { addr = w.address, x = w.at.x, y = w.at.y, sx = w.size.x, sy = w.size.y }
    else
        press = nil
    end
end

function cael_snap_release()
    local p = press
    press = nil
    if not p then return end
    local w = find_window(p.addr)
    if not w or not w.floating or (w.fullscreen and w.fullscreen ~= 0) then return end
    -- chi tinh khi cua so DUOC DI CHUYEN (doi vi tri, giu nguyen kich thuoc); keo doi kich thuoc thi bo qua
    if math.abs(w.size.x - p.sx) > 2 or math.abs(w.size.y - p.sy) > 2 then return end
    if math.abs(w.at.x - p.x) < 8 and math.abs(w.at.y - p.y) < 8 then return end
    local c = hl.get_cursor_pos and hl.get_cursor_pos()
    local m = mon_of(w)
    if not c or not m then return end
    local scale = (m.scale and m.scale > 0) and m.scale or 1
    local mw, mh = m.width / scale, m.height / scale
    local cx, cy = c.x - m.x, c.y - m.y
    local L, R = cx <= EDGE, cx >= mw - 1 - EDGE
    local T, B = cy <= EDGE, cy >= mh - 1 - EDGE
    if not (L or R or T or B) then return end
    -- goc: con tro nam gan goc theo ca 2 chieu
    local nx, ny = cx < mw * CORNER, cy < mh * CORNER
    local px, py = cx > mw * (1 - CORNER), cy > mh * (1 - CORNER)
    local x0, x1, y0, y1 = 0, 1, 0, 1
    if L or R then
        x0, x1 = (L and 0 or 0.5), (L and 0.5 or 1)
        if ny then y0, y1 = 0, 0.5 elseif py then y0, y1 = 0.5, 1 end
    else
        y0, y1 = (T and 0 or 0.5), (T and 0.5 or 1)
        if nx then x0, x1 = 0, 0.5 elseif px then x0, x1 = 0.5, 1 end
    end
    snap_to(w, x0, x1, y0, y1)
end

-- SUPER + SHIFT + mui ten: doi cho cua so hien tai voi cua so dang nam o huong do
-- (cua so co tam lech ve huong do, gan nhat; uu tien cung hang/cot). Hoan doi vi tri + kich thuoc.
function cael_swap(dirn)
    local w = find_window()
    if not w or (w.fullscreen and w.fullscreen ~= 0) then return end
    if not w.floating then
        dsp(hl.dsp.window.swap({ direction = dirn }))
        return
    end
    local function center(v) return v.at.x + v.size.x / 2, v.at.y + v.size.y / 2 end
    local cx, cy = center(w)
    local best, best_score
    for _, v in ipairs(hl.get_windows()) do
        if v.address ~= w.address and v.mapped ~= false and v.floating and not in_min(v)
            and v.workspace and w.workspace and v.workspace.id == w.workspace.id and (v.class or "") ~= "" then
            local vx, vy = center(v)
            local along, across
            if dirn == "left" then along, across = cx - vx, math.abs(cy - vy)
            elseif dirn == "right" then along, across = vx - cx, math.abs(cy - vy)
            elseif dirn == "up" then along, across = cy - vy, math.abs(cx - vx)
            else along, across = vy - cy, math.abs(cx - vx) end
            if along > 4 then
                local score = along + 2 * across
                if not best_score or score < best_score then best, best_score = v, score end
            end
        end
    end
    if not best then return end
    local a, b = w, best
    local ga = { a.at.x, a.at.y, a.size.x, a.size.y }
    local gb = { b.at.x, b.at.y, b.size.x, b.size.y }
    local function set(v, g)
        local sel = "address:" .. v.address
        dsp(hl.dsp.window.resize({ x = g[3], y = g[4], window = sel }))
        dsp(hl.dsp.window.move({ x = g[1], y = g[2], window = sel }))
    end
    set(a, gb)
    set(b, ga)
    dsp(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. b.address }))
    dsp(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. a.address }))
end
