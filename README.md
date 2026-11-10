# Quantum Shell (Caelestia)

Desktop shell viết bằng [Quickshell](https://quickshell.org) (QML) cho **Hyprland** trên **Arch Linux**:
thanh menu kiểu macOS + dock, launcher, Launchpad, Mission Control (overview), control center, dashboard,
màn hình khoá (PAM), thông báo, OSD, screensaver, bộ chuyển cửa sổ Alt+Tab, hiệu ứng genie, trang
*Personalize* (màu, bar, dock, âm thanh, ngôn ngữ…), hai giao diện **Caelestial** / **Serpantium**, cùng các app phụ
(Task Manager, Claude Agents City/Viz).

## Cài đặt nhanh

```bash
git clone https://github.com/haidangphan1506/quantum-linux.git
cd quantum-linux
./install.sh          # thêm --yes để không bị hỏi, --dry-run để xem trước
```

`install.sh` (chạy bằng user thường, tự gọi `sudo`):

1. cài ~46 gói từ repo chính thức (hyprland, quickshell, Qt6, pipewire, NetworkManager, bluez, kitty, cliphist, grim…);
2. cài font **Material Symbols Rounded** từ AUR (`ttf-material-symbols-variable-git`; tự cài `yay-bin` nếu chưa có AUR helper; bỏ qua bằng `--no-aur`);
3. bật dịch vụ NetworkManager, bluetooth, upower, power-profiles-daemon, pipewire;
4. liên kết repo vào `~/.config/quickshell/caelestia` (và bí danh `quantum`), đặt launcher vào `~/.local/bin`, `.desktop` + icon vào `~/.local/share`;
5. chép cấu hình Hyprland Lua vào `~/.config/hypr/` (`quantum.lua`, `minimize.lua`; `hyprland.lua` chỉ tạo nếu bạn chưa có — file cũ không bị ghi đè, file trùng tên được sao lưu `.bak-<ngày>`).

Thêm `--no-hypr` nếu muốn tự quản lý cấu hình Hyprland.

## Chạy

| Tình huống | Lệnh |
|---|---|
| Từ TTY | `Hyprland` (đăng nhập bằng user thường) |
| Đang trong Hyprland | `qs -c caelestia` (xem log: `qs -c caelestia log`) |
| Chạy thử không cần cài | `qs -p /đường/dẫn/quantum-linux` |
| Nạp lại sau khi sửa | tự hot-reload; hoặc `pkill qs; qs -c caelestia -d` |

Nếu đã có `hyprland.lua` riêng, thêm vào cuối file: `require("quantum")`.

### Phím tắt mặc định (`hypr/quantum.lua`)

`Super+Space` launcher · `Super+V` clipboard · `Super+A` control center · `Super+D` dashboard · `Super+W` hình nền ·
`Super+,` Personalize · `Super+L` khoá · `Super+Esc` menu phiên · `Super+Tab` overview · `Super+G` Launchpad ·
`Alt+Tab` chuyển cửa sổ · `Super+C` đóng cửa sổ · `Super+Q` terminal · `Super+E` file · `Ctrl+Shift+Esc` Task Manager.
Mọi thứ đều đi qua IPC: `qs -c caelestia ipc call <target> <hàm>` (xem `grep -rn IpcHandler .`).

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `shell.qml` | điểm vào: Splash → nạp lười toàn bộ desktop |
| `modules/` | từng thành phần giao diện (bar, dock, lock, launcher, overview, personalize, serpantium…) |
| `services/` | singleton: Settings, Theme, Audio, Net, Bt, Wm (cửa sổ), Updates, Weather, I18n… |
| `components/` | widget dùng chung |
| `apps/` | app Quickshell độc lập (`taskmgr`, `agentoffice`, `agentviz`, `agentviz3d`) |
| `hypr/` | cấu hình Hyprland Lua + hàm `cael_*` (minimize, activate, close…) |
| `pam/` | cấu hình PAM cho màn hình khoá |
| `scripts/`, `tools/idle` | thu thập mức dùng Claude Code, phát hiện idle → screensaver |

Cấu hình người dùng lưu ở `~/.config/quantum/settings.json`, màu ở `~/.local/state/quantum/colors.json`.

## Review source — các điểm cần biết

**Phụ thuộc ngoài repo (chưa có trong source này).** Shell gọi một số lệnh `quantum-*` thuộc bản Quantum Linux đầy đủ.
Chúng *không* có ở đây nên khi chạy riêng, các tính năng liên quan sẽ không hoạt động (shell vẫn chạy, chỉ ghi lỗi vào log):

| Lệnh thiếu | Ảnh hưởng |
|---|---|
| `quantum-theme` | không sinh `colors.json` → dùng bảng màu mặc định; đổi màu/chế độ game trong Personalize không áp dụng ra GTK/Hyprland |
| `quantum-update`, hook `quantum-reboot.hook` | nút cập nhật hệ thống / nhắc khởi động lại |
| `quantum-center`, `quantum-display`, `quantum-files` | Trung tâm cài đặt, ánh sáng ban đêm/gamma, trình quản lý file được ghim sẵn trên dock |

Mặc định dock ghim `quantum-files`, `quantum-center` nên các ô này sẽ trống cho tới khi bạn đổi ghim trong Personalize → Dock (hoặc sửa `dock.pinned` trong `settings.json`).

**Hàm Lua `cael_*`.** Shell gọi `hyprctl eval "cael_activate(...)"` v.v. (`services/Wm.qml`, `Shell.qml`, `MacBar.qml`). Source gốc để chúng trong `minimize.lua` riêng
không có trong repo; bản `hypr/minimize.lua` ở đây là cài đặt lại tối thiểu. **Chưa kiểm thử trên Hyprland thật** (môi trường review không có Arch/Hyprland): `activate / minimize / close / hide_others / show_all` dùng `hl.dispatch` + `hyprctl clients -j | jq`; hiệu ứng genie (`ipc call genie play`) **chưa** được nối. Nếu lệnh nào lỗi, báo qua `notify-send`.

**Yêu cầu Hyprland ≥ 0.55.** Cú pháp `hl.dsp.*` / `hyprctl eval` chỉ có từ khi Hyprland chuyển sang cấu hình Lua. `hyprland.conf` kiểu cũ không dùng được.

**Nhất quán, dọn dẹp:**
- Code gọi `qs -c caelestia` nhưng một số comment ghi `qs -c quantum` và "Wayfire" (di sản từ bản trước). Installer tạo cả hai tên cấu hình để không lệch.
- `shell.qml` ghim icon theme `MacTahoe` (không có trong repo Arch) → dùng fallback; cài tay icon theme này nếu muốn đúng giao diện.
- Các chuỗi giao diện trộn Tây Ban Nha/Việt (`i18n/strings.js` là từ điển chung) — chủ ý, không phải lỗi.
- `apps/agentviz/__pycache__/*.pyc` từng bị commit → đã gỡ khỏi git và thêm `.gitignore`.
- Weather gọi `ipapi.co` / `open-meteo.com` (xác định vị trí theo IP khi chưa chọn thành phố) — lưu ý riêng tư.
- Python (`scripts/*.py`, `collector.py`) và `keybinds.sh` qua kiểm tra cú pháp; chưa có test tự động nào trong repo.
- `scripts/keybinds.sh` đọc `~/.config/hypr/variable.lua`; file này không có trong cấu hình mặc định ở đây nên mục "Phím tắt" trong menu Help sẽ trống.

## Xử lý sự cố

- **Icon hiện ô vuông** → thiếu font: `fc-list | grep -i "Material Symbols"`; cài `ttf-material-symbols-variable-git`.
- **`qs: config not found`** → kiểm tra `ls -l ~/.config/quickshell/`.
- **Không khoá được màn hình** → cần `pam/password.conf` (đi kèm repo) và `pam_unix` (có sẵn).
- **Không có wifi/bluetooth** → `systemctl status NetworkManager bluetooth`.
- **Lỗi QML khi khởi động** → `qs -c caelestia log`; đảm bảo `qt6-quick3d`, `qt6-5compat`, `qt6-multimedia` đã cài.

## Giấy phép

Xem [LICENSE](LICENSE).
