#!/usr/bin/env bash
# Quantum Shell (Caelestia) - trình cài đặt cho Arch Linux.
# Cài gói, font, cấu hình Hyprland (Lua) và liên kết shell vào ~/.config/quickshell/caelestia.
#
#   ./install.sh              cài đặt bình thường
#   ./install.sh --yes        không hỏi xác nhận (pacman --noconfirm)
#   ./install.sh --no-aur     bỏ qua gói AUR (font Material Symbols sẽ phải tự cài)
#   ./install.sh --dry-run    chỉ in ra việc sẽ làm
#   ./install.sh --no-hypr    không đụng tới ~/.config/hypr
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/quantum"
BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"

YES=0 AUR=1 DRY=0 HYPR=1
for a in "$@"; do
  case "$a" in
    -y|--yes) YES=1 ;;
    --no-aur) AUR=0 ;;
    --dry-run) DRY=1 ;;
    --no-hypr) HYPR=0 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tuỳ chọn không hợp lệ: $a" >&2; exit 2 ;;
  esac
done

c() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
w() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
run() { if ((DRY)); then printf '  (dry-run) %s\n' "$*"; else "$@"; fi; }

# ---------- kiểm tra môi trường ----------
[[ $EUID -ne 0 ]] || die "Đừng chạy bằng root/sudo. Script sẽ tự gọi sudo khi cần."
[[ -r /etc/arch-release ]] || die "Script này chỉ dành cho Arch Linux (hoặc dẫn xuất có pacman)."
command -v pacman >/dev/null || die "Không tìm thấy pacman."
command -v sudo >/dev/null || die "Cần cài sudo trước (pacman -S sudo)."
[[ -f "$REPO/shell.qml" ]] || die "Không thấy shell.qml trong $REPO - chạy script từ thư mục source."

PAC=(sudo pacman -S --needed); ((YES)) && PAC+=(--noconfirm)

# ---------- gói từ repo chính thức ----------
PKGS=(
  # compositor + shell
  hyprland quickshell xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit-kde-agent
  # Qt6 mà các module QML import (Quick3D cho agentviz3d/agentoffice, Multimedia cho wallpaper động)
  qt6-declarative qt6-5compat qt6-multimedia qt6-quick3d qt6-svg qt6-wayland qt6-shadertools
  # âm thanh, mạng, bluetooth, nguồn
  pipewire pipewire-pulse pipewire-alsa wireplumber libpulse
  networkmanager nm-connection-editor bluez bluez-utils blueman
  upower power-profiles-daemon brightnessctl
  # công cụ shell gọi trực tiếp
  kitty cliphist wl-clipboard grim slurp playerctl libnotify jq curl git python
  pacman-contrib fastfetch ffmpeg xdg-utils
  # ứng dụng + font
  nautilus firefox ttf-inter ttf-jetbrains-mono noto-fonts noto-fonts-emoji
)
c "Cài gói từ repo chính thức (${#PKGS[@]} gói)"
run "${PAC[@]}" "${PKGS[@]}"

# ---------- gói AUR ----------
# Material Symbols Rounded: font icon bắt buộc (Theme.iconFont). MacTahoe là icon theme tuỳ chọn.
AUR_PKGS=(ttf-material-symbols-variable-git)
aur_helper() { for h in paru yay; do command -v "$h" >/dev/null && { echo "$h"; return; }; done; }
if ((AUR)); then
  H="$(aur_helper || true)"
  if [[ -z "$H" ]]; then
    c "Chưa có AUR helper - cài yay-bin"
    if ((DRY)); then echo "  (dry-run) git clone https://aur.archlinux.org/yay-bin.git && makepkg -si"
    else
      sudo pacman -S --needed --noconfirm base-devel git
      tmp="$(mktemp -d)"; git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
      (cd "$tmp/yay-bin" && makepkg -si --noconfirm); rm -rf "$tmp"; H=yay
    fi
  fi
  c "Cài gói AUR: ${AUR_PKGS[*]}"
  A=("${H:-yay}" -S --needed); ((YES)) && A+=(--noconfirm)
  run "${A[@]}" "${AUR_PKGS[@]}" || w "Cài AUR thất bại - icon trên shell sẽ hiện ô vuông cho tới khi có font 'Material Symbols Rounded'."
else
  w "Bỏ qua AUR: tự cài font 'Material Symbols Rounded' (ttf-material-symbols-variable-git)."
fi

# ---------- dịch vụ systemd ----------
c "Bật dịch vụ: NetworkManager, bluetooth, upower, power-profiles-daemon"
for s in NetworkManager bluetooth upower power-profiles-daemon; do
  run sudo systemctl enable --now "$s.service" || w "Không bật được $s.service"
done
run systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service || true

# ---------- liên kết shell vào quickshell ----------
c "Liên kết shell: $CFG/quickshell/caelestia -> $REPO"
run mkdir -p "$CFG/quickshell" "$STATE" "$BIN" "$CFG/quantum"
link() { # link <đích> <đường dẫn liên kết>
  local target="$1" dest="$2"
  if [[ -L "$dest" ]]; then run ln -sfn "$target" "$dest"
  elif [[ -e "$dest" ]]; then w "Sao lưu $dest -> $dest.bak-$STAMP"; run mv "$dest" "$dest.bak-$STAMP"; run ln -s "$target" "$dest"
  else run ln -s "$target" "$dest"; fi
}
link "$REPO" "$CFG/quickshell/caelestia"
link "$REPO" "$CFG/quickshell/quantum"        # bí danh: một số comment/tài liệu dùng "qs -c quantum"

# launcher cho các app phụ + .desktop (Wm.qml tra icon/tên qua DesktopEntries)
link "$REPO/bin/quantum-taskmgr" "$BIN/quantum-taskmgr"
link "$REPO/apps/agentoffice/claude-agentoffice" "$BIN/claude-agentoffice"
link "$REPO/apps/agentviz3d/claude-agentviz3d" "$BIN/claude-agentviz3d"
run mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
for d in quantum-personalize quantum-assistant; do
  run install -Dm644 "$REPO/assets/$d.desktop" "$HOME/.local/share/applications/$d.desktop"
  run install -Dm644 "$REPO/assets/$d.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/$d.svg"
done
run gtk-update-icon-cache -qf "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
case ":$PATH:" in *":$BIN:"*) ;; *) w "$BIN chưa nằm trong PATH - thêm: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

# ---------- cấu hình Hyprland (Lua) ----------
if ((HYPR)); then
  HC="$CFG/hypr"
  c "Cấu hình Hyprland: $HC"
  run mkdir -p "$HC"
  for f in quantum.lua minimize.lua; do
    [[ -f "$HC/$f" ]] && ! cmp -s "$REPO/hypr/$f" "$HC/$f" && { w "Sao lưu $HC/$f"; run cp "$HC/$f" "$HC/$f.bak-$STAMP"; }
    run install -Dm644 "$REPO/hypr/$f" "$HC/$f"
  done
  if [[ -f "$HC/hyprland.lua" ]]; then
    grep -q 'require("quantum")' "$HC/hyprland.lua" ||
      w "Bạn đã có hyprland.lua - thêm dòng này vào cuối file: require(\"quantum\")"
  elif [[ -f "$HC/hyprland.conf" ]]; then
    w "Bạn đang dùng hyprland.conf (cú pháp cũ). Quantum cần cấu hình Lua (Hyprland >= 0.55): tạo $HC/hyprland.lua từ $REPO/hypr/hyprland.lua"
  else
    run install -Dm644 "$REPO/hypr/hyprland.lua" "$HC/hyprland.lua"
  fi
fi

# ---------- kiểm tra cuối ----------
if ! ((DRY)); then
  c "Kiểm tra"
  v="$(Hyprland --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | tr -d v || true)"
  if [[ -n "$v" ]]; then
    echo "  Hyprland $v"
    [[ "$(printf '%s\n0.55\n' "$v" | sort -V | head -1)" == "0.55" ]] || w "Hyprland < 0.55 không đọc được cấu hình Lua / lệnh 'hyprctl eval' mà shell dùng. Hãy cập nhật (pacman -Syu)."
  fi
  command -v qs >/dev/null && echo "  quickshell: $(qs --version 2>/dev/null | head -1)" || w "Không thấy lệnh qs"
  fc-list | grep -qi 'Material Symbols' && echo "  font Material Symbols: OK" || w "Thiếu font Material Symbols Rounded"
  python3 -B -c 'import ast,glob,sys; [ast.parse(open(f).read()) for f in glob.glob(sys.argv[1]+"/scripts/*.py")]' "$REPO" && echo "  scripts python: OK"
fi

cat <<MSG

Hoàn tất. Cách chạy:
  • Từ TTY (đăng nhập bằng user thường):   Hyprland
  • Đang trong một phiên Hyprland:          qs -c caelestia      (xem log: qs -c caelestia log)
  • Phím tắt mặc định: Super+Space (launcher), Super+A (control center), Super+Tab (overview),
    Super+L (khoá), Super+, (Personalize), Super+Q (terminal). Xem hypr/quantum.lua.
MSG
