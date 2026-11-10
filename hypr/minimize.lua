-- Hàm Lua mà Quantum Shell gọi qua: hyprctl eval "cael_xxx(...)"
-- (Hyprland không có "minimize": cửa sổ bị cất vào workspace ẩn special:minimized)
-- Cần Hyprland >= 0.55 (cấu hình Lua). Mọi lệnh đều bọc pcall để lỗi không làm hỏng cả config.

local MIN_WS = "special:minimized"

local function dispatch(d)
    local ok, err = pcall(function() hl.dispatch(d) end)
    if not ok then hl.exec_cmd("notify-send 'Quantum' 'cael: " .. tostring(err):gsub("'", "") .. "'") end
end

local function win(addr) return "address:" .. addr end

function cael_activate(addr)
    -- đưa cửa sổ về lại từ special:minimized (nếu có) rồi focus
    dispatch(hl.dsp.window.move({ workspace = "e+0", follow = false, window = win(addr) }))
    dispatch(hl.dsp.focus({ window = win(addr) }))
end

function cael_minimize(addr)
    dispatch(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = win(addr) }))
end

function cael_close(addr)
    dispatch(hl.dsp.window.close({ window = win(addr) }))
end

-- Các hàm dưới cần liệt kê cửa sổ: dùng hyprctl clients -j + jq cho chắc, không phụ thuộc API Lua.
local function sh(cmd) hl.exec_cmd(cmd) end

function cael_hide_others(addr)
    sh("hyprctl clients -j | jq -r '.[] | select(.mapped and .workspace.id > 0 and .address != \"" .. addr ..
       "\") | .address' | while read a; do hyprctl eval \"cael_minimize('$a')\"; done")
end

function cael_show_all()
    sh("hyprctl clients -j | jq -r '.[] | select(.workspace.name == \"" .. MIN_WS ..
       "\") | .address' | while read a; do hyprctl eval \"cael_activate('$a')\"; done")
end

function cael_toggle_size(addr)
    dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = win(addr) }))
end

-- Đặt cửa sổ theo tiêu đề vào góc trên-phải với kích thước w x h (agentviz)
function cael_place_tr(title, w, h)
    sh("a=$(hyprctl clients -j | jq -r '.[] | select(.title == \"" .. title .. "\") | .address' | head -1); " ..
       "[ -n \"$a\" ] && hyprctl dispatch \"hl.dsp.window.resize({ x = " .. w .. ", y = " .. h ..
       ", exact = true, window = 'address:'..'$a' })\"")
end

return true
