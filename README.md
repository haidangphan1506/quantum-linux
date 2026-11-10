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

1. cài ~55 gói từ repo chính thức (hyprland, quickshell, Qt6, pipewire, NetworkManager, bluez, kitty, **fish**, eza, starship, zoxide, cliphist, grim…);
2. cài font **Material Symbols Rounded** từ AUR (`ttf-material-symbols-variable-git`; dùng **paru**, tự cài `paru-bin` nếu chưa có; bỏ qua bằng `--no-aur`);
3. **gói còn thiếu cho Arch**: XWayland, openssh, mesa + driver GPU tự phát hiện (Intel/AMD/NVIDIA), gvfs/tumbler/thunar-volman/archive cho Thunar, font Nerd cho `eza --icons`, ripgrep, base-devel, `hyprlauncher`/`hyprshutdown` (Super+R / Super+M).
4. **gói bổ sung (chỉ cài cái còn thiếu)**: `blueman`, nhóm `fcitx5-im` + `fcitx5-unikey`, `htop`, `btop`, `pavucontrol`, `networkmanager` (có `nmcli`), `unzip`, `docker` + `docker-compose` (bật dịch vụ, thêm user vào nhóm `docker`), `lazygit`, `lazydocker`, `bun` (repo → AUR `bun-bin` → bun.sh), `opencode-ai` (qua `bun install -g`). Gói không có trong repo chính sẽ thử AUR. Bỏ qua cả nhóm bằng `--no-extras`;
5. bật dịch vụ NetworkManager, bluetooth, upower, power-profiles-daemon, pipewire;
6. liên kết repo vào `~/.config/quickshell/caelestia` (và bí danh `quantum`), launcher vào `~/.local/bin`, `.desktop` + icon vào `~/.local/share`;
7. **chép cấu hình vào hệ thống** (từ `config/`): `~/.config/hypr` (Hyprland Lua), `fish`, `Thunar`, `pavucontrol.ini`, `kitty/kitty.conf` (`shell /usr/bin/fish`), `xfce4/helpers.rc` (terminal = kitty). Thư mục/file đã tồn tại và khác sẽ được sao lưu thành `<tên>.bak-<ngày>`. Cuối cùng đặt **fish làm shell mặc định** (`chsh`).

Tuỳ chọn: `--yes`, `--dry-run`, `--no-aur`, `--no-hypr` (không đụng `~/.config/hypr`), `--no-dotfiles` (không chép fish/Thunar/kitty…), `--no-extras`.

Sau khi cài: đăng xuất/đăng nhập lại (nhóm `docker`, shell fish), chạy `fcitx5-configtool` để thêm bộ gõ Unikey.

## Chạy

| Tình huống | Lệnh |
|---|---|
| Từ TTY | `Hyprland` (đăng nhập bằng user thường) |
| Đang trong Hyprland | `qs -c caelestia` (xem log: `qs -c caelestia log`) |
| Chạy thử không cần cài | `qs -p /đường/dẫn/quantum-linux` |
| Nạp lại sau khi sửa | tự hot-reload; hoặc `pkill qs; qs -c caelestia -d` |

Cấu hình Hyprland nằm ở `config/hypr/` (`hyprland.lua` nạp các module trong `hyprlands/`; phím tắt trong `variable.lua`).

### Phím tắt chính (`config/hypr/variable.lua`)

**Terminal (kitty chạy fish): `Super+Enter`, `Super+Q`, `Ctrl+Alt+T`**; `Super+Shift+Enter` mở terminal chạy btop · `Super+Q` mở terminal · `Super+C` kill app đang focus (đã bỏ copy/paste kiểu macOS) ·
 `Super+E` file manager · `Super+R` hyprlauncher · `Super+Space`/tap `Super` launcher ·
`Super+A` control center · `Super+D` dashboard · `Super+X` menu phiên · `Super+L` khoá · `Super+W` hình nền ·
`Super+I` Personalize · `Super+Shift+V` clipboard · `Super+S` chụp vùng · `Alt+Tab` chuyển cửa sổ ·
`Ctrl+Shift+Esc` Task Manager · `Super+1..0` workspace · cử chỉ 3/4 ngón (touchpad).
Mọi thứ đều đi qua IPC: `qs -c caelestia ipc call <target> <hàm>` (xem `grep -rn IpcHandler .`).

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `shell.qml` | điểm vào: Splash → nạp lười toàn bộ desktop |
| `modules/` | từng thành phần giao diện (bar, dock, lock, launcher, overview, personalize, serpantium…) |
| `services/` | singleton: Settings, Theme, Audio, Net, Bt, Wm (cửa sổ), Updates, Weather, I18n… |
| `components/` | widget dùng chung |
| `apps/` | app Quickshell độc lập (`taskmgr`, `agentoffice`, `agentviz`, `agentviz3d`) |
| `config/` | cấu hình chép vào `~/.config`: `hypr/` (Lua + hàm `cael_*` trong `hyprlands/minimize.lua`), `fish/`, `Thunar/`, `pavucontrol.ini` |
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

**Cấu hình Hyprland (`config/hypr`).** Lấy từ repo `ARCH-LINUX-SYSTEM/hyprland` và đã review/sửa:
- đường dẫn cứng `/home/haidangphan/...` → `$HOME` (file manager tự rơi về `thunar` nếu không có `thunar-themed`; `CAELESTIA_WALLPAPERS_DIR`);
- `Super+E` bị gán trùng (file manager *và* `caelestia:settings`) → settings chuyển sang `Super+Shift+E`;
- `caelth` (bộ đổi profile) và CLI `caelestia` không bắt buộc: thiếu thì gọi thẳng `qs -c caelestia ipc call …` / `qs -c caelestia -d`;
- thêm `monitor` mặc định cho màn hình ngoài (trước chỉ có `eDP-1`), bỏ rule `epic-mouse-v1` mẫu thừa; autostart thêm `cliphist`, `blueman-applet`, polkit agent;
- các plugin `hyprbars.so` / `cael-minimize.so` là tuỳ chọn (không có thì bỏ qua, nhưng nút "_" của app như Brave sẽ không thu nhỏ được).
- Cú pháp Lua của mọi file đã được nạp thử với Hyprland API giả; **chưa chạy trên Hyprland thật**.

**fish.** Sửa: `ssh-agent` chỉ khởi động ở shell tương tác (trước đây sinh agent thừa mỗi lần chạy script), bỏ cờ `--apple-use-keychain` (chỉ macOS), `alias gc 'git commitm'`/`gpd 'git pulld…'` (lệnh không tồn tại) → `git commit`/`git pull`, bỏ `alias ps "podman ps"` (đè lệnh `ps`; thay bằng `dps` = docker ps), `TERMINAL` = `kitty` (trước là `fish`, vốn là shell chứ không phải terminal). Thêm alias `lg`, `lzd`.

Không đưa vào repo: `herdr-app/` (có telemetry id cá nhân), `mimeapps.list` (trỏ tới Brave và `cael-quicklook` chưa có), `fish_variables` (trạng thái máy, chứa đường dẫn user cũ) và các file `.bak`.

**Yêu cầu Hyprland ≥ 0.55.** Cú pháp `hl.dsp.*` / `hyprctl eval` chỉ có từ khi Hyprland chuyển sang cấu hình Lua. `hyprland.conf` kiểu cũ không dùng được.

**Nhất quán, dọn dẹp:**
- Code gọi `qs -c caelestia` nhưng một số comment ghi `qs -c quantum` và "Wayfire" (di sản từ bản trước). Installer tạo cả hai tên cấu hình để không lệch.
- `shell.qml` ghim icon theme `MacTahoe` (không có trong repo Arch) → dùng fallback; cài tay icon theme này nếu muốn đúng giao diện.
- Các chuỗi giao diện trộn Tây Ban Nha/Việt (`i18n/strings.js` là từ điển chung) — chủ ý, không phải lỗi.
- `apps/agentviz/__pycache__/*.pyc` từng bị commit → đã gỡ khỏi git và thêm `.gitignore`.
- Weather gọi `ipapi.co` / `open-meteo.com` (xác định vị trí theo IP khi chưa chọn thành phố) — lưu ý riêng tư.
- Python (`scripts/*.py`, `collector.py`) và `keybinds.sh` qua kiểm tra cú pháp; chưa có test tự động nào trong repo.
- `scripts/keybinds.sh` đọc `~/.config/hypr/variable.lua` — nay đã khớp vì installer chép file này.

## Xử lý sự cố

- **Icon hiện ô vuông** → thiếu font: `fc-list | grep -i "Material Symbols"`; cài `ttf-material-symbols-variable-git`.
- **`qs: config not found`** → kiểm tra `ls -l ~/.config/quickshell/`.
- **Không khoá được màn hình** → cần `pam/password.conf` (đi kèm repo) và `pam_unix` (có sẵn).
- **Không có wifi/bluetooth** → `systemctl status NetworkManager bluetooth`.
- **Lỗi QML khi khởi động** → `qs -c caelestia log`; đảm bảo `qt6-quick3d`, `qt6-5compat`, `qt6-multimedia` đã cài.

## Giấy phép

Xem [LICENSE](LICENSE).
